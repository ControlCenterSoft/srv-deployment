#!/usr/bin/env python3
"""Fail-closed automated PR release gate.

Runs only from a trusted pull_request_target workflow checked out from protected
main. It never checks out or executes pull-request code. It validates immutable
GitHub metadata, exact-head CI, a strict independent Gemini review, then submits
an approval and merges only the reviewed exact head SHA.
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

# These paths define CI/security/deployment/runtime trust boundaries. They must
# never be auto-approved by the gate that protects them. Changes here require
# the independent break-glass/reviewer path already enforced by repository rules.
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


class GitHubAPI:
    def __init__(self, token: str):
        if not token:
            raise GateError("GITHUB_TOKEN is empty")
        self.token = token

    def _headers(self, accept: str = "application/vnd.github+json") -> dict[str, str]:
        return {
            "Accept": accept,
            "Authorization": f"Bearer {self.token}",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "control-center-trusted-release-gate",
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
            detail = exc.read().decode("utf-8", errors="replace")
            raise GateError(f"GitHub API {method} {path} failed: HTTP {exc.code}: {detail}") from exc
        except urllib.error.URLError as exc:
            raise GateError(f"GitHub API {method} {path} failed: {exc}") from exc

    def request_text(
        self,
        path: str,
        *,
        accept: str,
        max_bytes: int,
    ) -> str:
        url = path if path.startswith("https://") else f"{API_ROOT}{path}"
        req = urllib.request.Request(url, headers=self._headers(accept), method="GET")
        try:
            with urllib.request.urlopen(req, timeout=20) as resp:
                raw = resp.read(max_bytes + 1)
        except urllib.error.HTTPError as exc:
            # Never copy GitHub/provider bodies into logs from this path.
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
                f"EXACT_CI_PASS sha={sha} base={base} check={expected_check!r} workflow={expected_workflow!r}"
            )
            return
        if time.monotonic() >= deadline:
            raise GateError(
                f"exact-head CI did not become green before timeout: sha={sha} "
                f"check={expected_check!r} workflow={expected_workflow!r}"
            )
        time.sleep(20)


def require_same_head(api: GitHubAPI, repo: str, pr_number: int, expected_sha: str, stage: str) -> dict[str, Any]:
    current = api.request(f"/repos/{repo}/pulls/{pr_number}")
    if current.get("state") != "open" or current.get("draft"):
        raise GateError(f"pull request state changed {stage}")
    if ((current.get("head") or {}).get("sha")) != expected_sha:
        raise GateError(f"pull request head moved {stage}")
    return current


def run_independent_ai_review(api: GitHubAPI, repo: str, pr_number: int, sha: str) -> dict[str, Any]:
    # Import only trusted main-branch modules. The workflow never extends sys.path
    # with, imports, or executes pull-request-controlled files.
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


def run(repo: str, pr_number: int, wait_seconds: int, *, merge: bool) -> None:
    api = GitHubAPI(os.environ.get("GITHUB_TOKEN", ""))
    pr = api.request(f"/repos/{repo}/pulls/{pr_number}")
    files = api.paged(f"/repos/{repo}/pulls/{pr_number}/files")
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
        raise GateError(f"opaque/binary file changes require independent break-glass review: {opaque}")

    blockers = requested_changes_reviewers(api, repo, pr_number)
    if blockers:
        raise GateError(f"active requested-changes reviews block automation: {blockers}")

    base = pr["base"]["ref"]
    head_sha = pr["head"]["sha"]
    wait_for_exact_ci(api, repo, head_sha, base, wait_seconds)

    # Bind the provider-reviewed diff to the exact CI-tested head. A synchronize
    # race before or after provider review fails closed.
    require_same_head(api, repo, pr_number, head_sha, "before independent review")
    run_independent_ai_review(api, repo, pr_number, head_sha)
    require_same_head(api, repo, pr_number, head_sha, "before approval")

    blockers = requested_changes_reviewers(api, repo, pr_number)
    if blockers:
        raise GateError(f"requested-changes review appeared before approval: {blockers}")

    print(f"POLICY_PASS pr={pr_number} sha={head_sha} base={base}")
    api.request(
        f"/repos/{repo}/pulls/{pr_number}/reviews",
        method="POST",
        body={
            "event": "APPROVE",
            "body": (
                "Automated trusted release-gate approval. "
                f"Exact head `{head_sha}` passed protected-path policy, exact-head CI, "
                "and independent Gemini review with no HIGH/BLOCKER or CHANGES_REQUIRED verdict."
            ),
        },
    )
    print(f"AUTOMATED_APPROVAL_SUBMITTED pr={pr_number} sha={head_sha}")

    if not merge:
        return

    time.sleep(2)
    require_same_head(api, repo, pr_number, head_sha, "before merge")
    result = api.request(
        f"/repos/{repo}/pulls/{pr_number}/merge",
        method="PUT",
        body={"sha": head_sha, "merge_method": "merge"},
    )
    if not result or result.get("merged") is not True:
        raise GateError(f"GitHub refused protected merge: {result!r}")
    print(f"AUTOMATED_MERGE_COMPLETED pr={pr_number} sha={head_sha} merge_sha={result.get('sha')}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    parser.add_argument("--pr", required=True, type=int)
    parser.add_argument("--wait-seconds", type=int, default=900)
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
