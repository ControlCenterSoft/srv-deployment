#!/usr/bin/env python3
"""Fail-closed automated PR release gate with independent GitHub App approval.

The workflow that runs this module is loaded only from protected ``main`` via
``pull_request_target``. Pull-request-controlled code is never checked out,
imported, sourced, or executed. A dedicated GitHub App installation token is
used only to submit the independent APPROVE review; the workflow token performs
the final exact-SHA merge only after that review and all deterministic/policy
checks have passed.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import Any, Iterable

API_ROOT = os.environ.get("GITHUB_API_URL", "https://api.github.com").rstrip("/")
GITHUB_ACTIONS_APP_ID = 15368
RELEASE_GATE_REVIEWER = "control-center-release-gate[bot]"
SHA40 = re.compile(r"^[0-9a-f]{40}$")
MAX_REVIEW_DIFF_BYTES = 180_000

REQUIRED_CHECKS = {
    "main": "integration-guard",
    "1.1.x": "Fast development gate",
}
REQUIRED_WORKFLOWS = {
    "main": "post-release-main",
    "1.1.x": "Control Center 1.1.x Fast CI",
}

# CI/security/deployment/runtime trust boundaries are never eligible for
# automatic App approval. They stay on the independent break-glass path.
PROTECTED_PREFIXES = (
    ".github/",
    "cmd/",
    "install/",
    "packaging/",
    "release/",
    "scripts/",
    "evidence/",
    "internal/auth/",
    "internal/httpserver/",
    "internal/network/",
    "internal/operations/",
    "internal/privileged/",
    "internal/release/",
    "internal/state/",
)
PROTECTED_EXACT = {
    ".gitmodules",
    "CLAUDE.md",
    "SECURITY.md",
    "VALIDATION.md",
    "deployment.json",
    "go.mod",
    "go.sum",
}

MAX_CHANGED_FILES = 40
MAX_ADDITIONS = 2500
MAX_DELETIONS = 2500


class GateError(RuntimeError):
    pass


@dataclass(frozen=True)
class Decision:
    allowed: bool
    reasons: tuple[str, ...]


def protected_reason(path: str) -> str | None:
    normalized = path.strip().removeprefix("./")
    if normalized in PROTECTED_EXACT:
        return f"protected exact path: {normalized}"
    for prefix in PROTECTED_PREFIXES:
        if normalized.startswith(prefix):
            return f"protected path prefix {prefix}: {normalized}"
    return None


def policy_decision(repo: str, pr: dict[str, Any], filenames: Iterable[str]) -> Decision:
    reasons: list[str] = []
    owner = repo.split("/", 1)[0]

    if pr.get("state") != "open":
        reasons.append("pull request is not open")
    if pr.get("draft"):
        reasons.append("pull request is draft")

    base = ((pr.get("base") or {}).get("ref"))
    if base not in REQUIRED_CHECKS:
        reasons.append(f"unsupported protected base: {base!r}")

    head = pr.get("head") or {}
    head_sha = head.get("sha") or ""
    if not SHA40.fullmatch(head_sha):
        reasons.append("head SHA is not an exact 40-hex commit")

    head_repo = (head.get("repo") or {}).get("full_name")
    if head_repo != repo:
        reasons.append("cross-repository pull requests are never auto-approved")

    author = ((pr.get("user") or {}).get("login"))
    if author != owner:
        reasons.append(f"PR author is not repository owner: {author!r}")

    if int(pr.get("changed_files") or 0) > MAX_CHANGED_FILES:
        reasons.append("changed-file count exceeds automatic gate limit")
    if int(pr.get("additions") or 0) > MAX_ADDITIONS:
        reasons.append("addition count exceeds automatic gate limit")
    if int(pr.get("deletions") or 0) > MAX_DELETIONS:
        reasons.append("deletion count exceeds automatic gate limit")

    for path in filenames:
        reason = protected_reason(path)
        if reason:
            reasons.append(reason)

    return Decision(not reasons, tuple(reasons))


def app_approval_decision(reviews: Iterable[dict[str, Any]], head_sha: str) -> Decision:
    latest: tuple[int, dict[str, Any]] | None = None
    for review in reviews:
        login = str(((review.get("user") or {}).get("login")) or "")
        if login.lower() != RELEASE_GATE_REVIEWER.lower():
            continue
        rid = int(review.get("id") or 0)
        if latest is None or rid >= latest[0]:
            latest = (rid, review)

    if latest is None:
        return Decision(False, (f"missing review from fixed App reviewer {RELEASE_GATE_REVIEWER}",))

    review = latest[1]
    state = str(review.get("state") or "").upper()
    commit_id = str(review.get("commit_id") or "")
    reasons: list[str] = []
    if state != "APPROVED":
        reasons.append(f"latest App review is not APPROVED: {state or 'UNKNOWN'}")
    if commit_id != head_sha:
        reasons.append("App approval is not anchored to the exact PR head")
    return Decision(not reasons, tuple(reasons))


def base_compare_decision(
    expected_base_sha: str,
    current_base_sha: str,
    payload: dict[str, Any],
) -> Decision:
    reasons: list[str] = []
    if current_base_sha != expected_base_sha:
        reasons.append("protected base moved after evidence was captured")
    if int(payload.get("behind_by") or 0) != 0:
        reasons.append("PR head is behind the current protected base")
    if str(payload.get("status") or "") not in {"ahead", "identical"}:
        reasons.append(f"PR head is not a clean descendant of current base: {payload.get('status')!r}")
    return Decision(not reasons, tuple(reasons))


class GitHubAPI:
    def __init__(self, token: str, *, role: str):
        if not token:
            raise GateError(f"{role} token is empty")
        self.token = token
        self.role = role

    def _headers(self, accept: str = "application/vnd.github+json") -> dict[str, str]:
        return {
            "Accept": accept,
            "Authorization": f"Bearer {self.token}",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": f"control-center-release-gate/{self.role}",
        }

    def request(self, path: str, *, method: str = "GET", body: Any | None = None) -> Any:
        url = path if path.startswith("https://") else f"{API_ROOT}{path}"
        data = None
        headers = self._headers()
        if body is not None:
            data = json.dumps(body, separators=(",", ":")).encode("utf-8")
            headers["Content-Type"] = "application/json"
        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=20) as resp:
                raw = resp.read()
                return json.loads(raw) if raw else None
        except urllib.error.HTTPError as exc:
            raise GateError(f"GitHub API {self.role} {method} {path} failed: HTTP {exc.code}") from exc
        except urllib.error.URLError as exc:
            raise GateError(f"GitHub API {self.role} {method} {path} failed") from exc

    def request_text(self, path: str, *, accept: str, max_bytes: int) -> str:
        url = path if path.startswith("https://") else f"{API_ROOT}{path}"
        req = urllib.request.Request(url, headers=self._headers(accept), method="GET")
        try:
            with urllib.request.urlopen(req, timeout=20) as resp:
                raw = resp.read(max_bytes + 1)
        except urllib.error.HTTPError as exc:
            raise GateError(f"GitHub API diff request failed: HTTP {exc.code}") from exc
        except urllib.error.URLError as exc:
            raise GateError("GitHub API diff request failed") from exc
        if len(raw) > max_bytes:
            raise GateError(f"pull-request diff exceeds automatic review limit: >{max_bytes} bytes")
        try:
            return raw.decode("utf-8", errors="strict")
        except UnicodeDecodeError as exc:
            raise GateError("pull-request diff is not valid UTF-8") from exc

    def paged(self, path: str) -> list[Any]:
        items: list[Any] = []
        page = 1
        sep = "&" if "?" in path else "?"
        while True:
            batch = self.request(f"{path}{sep}per_page=100&page={page}")
            if not isinstance(batch, list):
                raise GateError(f"expected paged list from {path}")
            items.extend(batch)
            if len(batch) < 100:
                return items
            page += 1


def latest_review_states(api: GitHubAPI, repo: str, pr_number: int) -> dict[str, str]:
    reviews = api.paged(f"/repos/{repo}/pulls/{pr_number}/reviews")
    latest: dict[str, tuple[int, str]] = {}
    for review in reviews:
        user = ((review.get("user") or {}).get("login"))
        state = (review.get("state") or "").upper()
        rid = int(review.get("id") or 0)
        if user and rid >= latest.get(user, (-1, ""))[0]:
            latest[user] = (rid, state)
    return {user: state for user, (_, state) in latest.items()}


def requested_changes_reviewers(api: GitHubAPI, repo: str, pr_number: int) -> list[str]:
    states = latest_review_states(api, repo, pr_number)
    return sorted(user for user, state in states.items() if state == "CHANGES_REQUESTED")


def require_app_approval(api: GitHubAPI, repo: str, pr_number: int, head_sha: str) -> None:
    decision = app_approval_decision(api.paged(f"/repos/{repo}/pulls/{pr_number}/reviews"), head_sha)
    if not decision.allowed:
        raise GateError("; ".join(decision.reasons))
    print(f"APP_APPROVAL_PASS reviewer={RELEASE_GATE_REVIEWER} sha={head_sha}")


def exact_check_passed(api: GitHubAPI, repo: str, sha: str, expected_name: str) -> bool:
    payload = api.request(f"/repos/{repo}/commits/{sha}/check-runs?per_page=100")
    runs = payload.get("check_runs", []) if isinstance(payload, dict) else []
    matching = [
        run
        for run in runs
        if run.get("name") == expected_name
        and ((run.get("app") or {}).get("id")) == GITHUB_ACTIONS_APP_ID
    ]
    if not matching:
        return False
    latest = max(matching, key=lambda run: int(run.get("id") or 0))
    return latest.get("status") == "completed" and latest.get("conclusion") == "success"


def exact_workflow_passed(api: GitHubAPI, repo: str, sha: str, expected_name: str) -> bool:
    q = urllib.parse.urlencode({"head_sha": sha, "event": "pull_request", "per_page": 100})
    payload = api.request(f"/repos/{repo}/actions/runs?{q}")
    runs = payload.get("workflow_runs", []) if isinstance(payload, dict) else []
    matching = [run for run in runs if run.get("name") == expected_name]
    if not matching:
        return False
    latest = max(matching, key=lambda run: int(run.get("id") or 0))
    return latest.get("status") == "completed" and latest.get("conclusion") == "success"


def wait_for_exact_ci(api: GitHubAPI, repo: str, sha: str, base: str, wait_seconds: int) -> None:
    expected_check = REQUIRED_CHECKS[base]
    expected_workflow = REQUIRED_WORKFLOWS[base]
    deadline = time.monotonic() + max(0, wait_seconds)
    while True:
        if exact_check_passed(api, repo, sha, expected_check) and exact_workflow_passed(
            api, repo, sha, expected_workflow
        ):
            print(
                f"EXACT_CI_PASS sha={sha} base={base} "
                f"check={expected_check!r} workflow={expected_workflow!r}"
            )
            return
        if time.monotonic() >= deadline:
            raise GateError(
                f"exact-head CI did not become green before timeout: sha={sha} "
                f"check={expected_check!r} workflow={expected_workflow!r}"
            )
        time.sleep(20)


def require_same_head(
    api: GitHubAPI,
    repo: str,
    pr_number: int,
    expected_sha: str,
    stage: str,
    *,
    expected_base: str | None = None,
) -> dict[str, Any]:
    current = api.request(f"/repos/{repo}/pulls/{pr_number}")
    if current.get("state") != "open" or current.get("draft"):
        raise GateError(f"pull request state changed {stage}")
    if ((current.get("head") or {}).get("sha")) != expected_sha:
        raise GateError(f"pull request head moved {stage}")
    if expected_base is not None and ((current.get("base") or {}).get("ref")) != expected_base:
        raise GateError(f"pull request base changed {stage}")
    return current


def current_base_sha(api: GitHubAPI, repo: str, base: str) -> str:
    quoted = urllib.parse.quote(base, safe="")
    payload = api.request(f"/repos/{repo}/git/ref/heads/{quoted}")
    sha = str(((payload.get("object") or {}).get("sha")) or "") if isinstance(payload, dict) else ""
    if not SHA40.fullmatch(sha):
        raise GateError(f"could not resolve exact protected base SHA for {base}")
    return sha


def require_current_base(
    api: GitHubAPI,
    repo: str,
    pr_number: int,
    head_sha: str,
    base: str,
    expected_base_sha: str | None,
    stage: str,
) -> str:
    require_same_head(api, repo, pr_number, head_sha, stage, expected_base=base)
    observed_base_sha = current_base_sha(api, repo, base)
    if expected_base_sha is None:
        expected_base_sha = observed_base_sha
    compare = api.request(f"/repos/{repo}/compare/{observed_base_sha}...{head_sha}")
    if not isinstance(compare, dict):
        raise GateError("GitHub compare result was not an object")
    decision = base_compare_decision(expected_base_sha, observed_base_sha, compare)
    if not decision.allowed:
        raise GateError("; ".join(decision.reasons))
    print(
        f"BASE_BINDING_PASS stage={stage!r} base={base} "
        f"base_sha={observed_base_sha} head_sha={head_sha}"
    )
    return observed_base_sha


def run_independent_ai_review(
    api: GitHubAPI,
    repo: str,
    pr_number: int,
    sha: str,
) -> dict[str, Any]:
    from release_gate_ai import automatic_gate_allows, blocking_findings, review_diff

    api_key = os.environ.get("GEMINI_API_KEY", "").strip()
    model = os.environ.get("GEMINI_MODEL", "gemini-3.7-flash").strip() or "gemini-3.7-flash"
    if not api_key:
        raise GateError("GEMINI_API_KEY is not configured; independent review fails closed")

    diff_text = api.request_text(
        f"/repos/{repo}/pulls/{pr_number}",
        accept="application/vnd.github.v3.diff",
        max_bytes=MAX_REVIEW_DIFF_BYTES,
    )
    try:
        review = review_diff(
            diff_text,
            repository=repo,
            pr_number=pr_number,
            sha=sha,
            api_key=api_key,
            model=model,
        )
    except (RuntimeError, ValueError, json.JSONDecodeError) as exc:
        raise GateError(f"independent Gemini review unavailable/invalid: {type(exc).__name__}") from exc

    blockers = blocking_findings(review)
    print(
        "INDEPENDENT_AI_REVIEW "
        f"verdict={review.get('verdict')} findings={len(review.get('findings', []))} "
        f"high_or_blocker={len(blockers)} model={model}"
    )
    if not automatic_gate_allows(review):
        raise GateError(
            "independent Gemini review blocked automatic approval: "
            f"verdict={review.get('verdict')} high_or_blocker={len(blockers)}"
        )
    return review


def submit_app_approval(
    review_api: GitHubAPI,
    repo: str,
    pr_number: int,
    head_sha: str,
    base_sha: str,
) -> None:
    result = review_api.request(
        f"/repos/{repo}/pulls/{pr_number}/reviews",
        method="POST",
        body={
            "event": "APPROVE",
            "body": (
                "Automated approval by the dedicated Control Center Release Gate GitHub App. "
                f"Exact head `{head_sha}` and protected base `{base_sha}` passed deterministic "
                "CI, static policy, current-base binding and independent AI review."
            ),
        },
    )
    if not isinstance(result, dict):
        raise GateError("GitHub App approval response was not an object")
    if str(result.get("state") or "").upper() != "APPROVED":
        raise GateError("GitHub App did not return an APPROVED review")
    if str(result.get("commit_id") or "") != head_sha:
        raise GateError("GitHub App approval response is not anchored to exact PR head")
    print(f"APP_APPROVAL_SUBMITTED reviewer={RELEASE_GATE_REVIEWER} sha={head_sha}")


def run(repo: str, pr_number: int, wait_seconds: int, *, merge: bool) -> None:
    read_api = GitHubAPI(os.environ.get("GITHUB_TOKEN", ""), role="read")
    review_api = GitHubAPI(
        os.environ.get("RELEASE_GATE_REVIEW_TOKEN", ""),
        role="app-review",
    )
    merge_api = GitHubAPI(
        os.environ.get("MERGE_TOKEN", os.environ.get("GITHUB_TOKEN", "")),
        role="merge",
    )

    pr = read_api.request(f"/repos/{repo}/pulls/{pr_number}")
    files = read_api.paged(f"/repos/{repo}/pulls/{pr_number}/files")
    filenames = [item.get("filename", "") for item in files]

    decision = policy_decision(repo, pr, filenames)
    if not decision.allowed:
        for reason in decision.reasons:
            print(f"POLICY_BLOCK: {reason}")
        raise GateError("pull request is outside automatic approval policy")

    opaque = [
        item.get("filename", "")
        for item in files
        if item.get("status") != "removed" and item.get("patch") is None
    ]
    if opaque:
        raise GateError(f"opaque/binary file changes require break-glass review: {opaque}")

    blockers = requested_changes_reviewers(read_api, repo, pr_number)
    if blockers:
        raise GateError(f"active requested-changes reviews block automation: {blockers}")

    base = pr["base"]["ref"]
    head_sha = pr["head"]["sha"]
    base_sha = require_current_base(
        read_api, repo, pr_number, head_sha, base, None, "before exact-head CI"
    )
    wait_for_exact_ci(read_api, repo, head_sha, base, wait_seconds)

    require_current_base(
        read_api, repo, pr_number, head_sha, base, base_sha, "before independent AI review"
    )
    run_independent_ai_review(read_api, repo, pr_number, head_sha)
    require_current_base(
        read_api, repo, pr_number, head_sha, base, base_sha, "after independent AI review"
    )

    blockers = requested_changes_reviewers(read_api, repo, pr_number)
    if blockers:
        raise GateError(f"requested-changes review appeared before App approval: {blockers}")

    submit_app_approval(review_api, repo, pr_number, head_sha, base_sha)
    time.sleep(2)

    require_current_base(
        read_api, repo, pr_number, head_sha, base, base_sha, "after App approval"
    )
    require_app_approval(read_api, repo, pr_number, head_sha)

    print(
        f"POLICY_PASS pr={pr_number} head_sha={head_sha} base={base} "
        f"base_sha={base_sha} reviewer={RELEASE_GATE_REVIEWER}"
    )
    if not merge:
        return

    require_current_base(
        read_api, repo, pr_number, head_sha, base, base_sha, "immediately before merge"
    )
    require_app_approval(read_api, repo, pr_number, head_sha)
    blockers = requested_changes_reviewers(read_api, repo, pr_number)
    if blockers:
        raise GateError(f"requested-changes review appeared immediately before merge: {blockers}")

    result = merge_api.request(
        f"/repos/{repo}/pulls/{pr_number}/merge",
        method="PUT",
        body={"sha": head_sha, "merge_method": "merge"},
    )
    if not result or result.get("merged") is not True:
        raise GateError("GitHub refused protected merge")
    print(
        f"AUTOMATED_MERGE_COMPLETED pr={pr_number} head_sha={head_sha} "
        f"base_sha={base_sha} merge_sha={result.get('sha')}"
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--pr", required=True, type=int)
    parser.add_argument("--wait-seconds", type=int, default=1800)
    parser.add_argument("--no-merge", action="store_true")
    args = parser.parse_args()
    try:
        run(args.repo, args.pr, args.wait_seconds, merge=not args.no_merge)
    except GateError as exc:
        print(f"RELEASE_GATE_BLOCKED: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
