#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time
import urllib.request

REPO = os.environ.get("CHATSSH_REPO", "ControlCenterSoft/srv-deployment")
COMMAND_BRANCH = os.environ.get("CHATSSH_COMMAND_BRANCH", "ops/chatssh-control")
RESULT_BRANCH = os.environ.get("CHATSSH_RESULT_BRANCH", "ops/chatssh-results")
STATE_DIR = Path(os.environ.get("CHATSSH_STATE_DIR", "/var/lib/chatssh-gateway"))
RESULT_REPO = STATE_DIR / "results-repo"
LAST_ID = STATE_DIR / "last-command-id"
COMMAND_URL = f"https://raw.githubusercontent.com/{REPO}/{COMMAND_BRANCH}/ops/chatssh/command.json"
SHA_RE = re.compile(r"^[0-9a-f]{40}$")
HEX256_RE = re.compile(r"^[0-9a-f]{64}$")
ID_RE = re.compile(r"^[A-Za-z0-9._:-]{1,96}$")


def fetch_bytes(url: str, timeout: int = 20) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": "ControlCenter-ChatSSH/1"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read()


def load_command() -> dict:
    payload = json.loads(fetch_bytes(COMMAND_URL).decode("utf-8"))
    if not isinstance(payload, dict) or payload.get("schema") != 1:
        raise ValueError("invalid command schema")
    if payload.get("enabled") is not True:
        raise ValueError("command disabled")
    command_id = payload.get("id")
    script_sha = payload.get("script_sha")
    script_path = payload.get("script_path")
    digest = payload.get("sha256")
    timeout = payload.get("timeout_seconds", 300)
    if not isinstance(command_id, str) or not ID_RE.fullmatch(command_id):
        raise ValueError("invalid command id")
    if not isinstance(script_sha, str) or not SHA_RE.fullmatch(script_sha):
        raise ValueError("script_sha must be immutable 40-hex commit")
    if not isinstance(script_path, str) or not script_path.startswith("ops/chatssh/jobs/"):
        raise ValueError("script_path outside allowed prefix")
    if ".." in Path(script_path).parts:
        raise ValueError("unsafe script path")
    if not isinstance(digest, str) or not HEX256_RE.fullmatch(digest):
        raise ValueError("invalid sha256")
    if not isinstance(timeout, int) or not 1 <= timeout <= 1800:
        raise ValueError("invalid timeout")
    return payload


def ensure_result_repo() -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    if (RESULT_REPO / ".git").is_dir():
        return
    subprocess.run(
        ["git", "clone", f"https://github.com/{REPO}.git", str(RESULT_REPO)],
        check=True,
        stdout=subprocess.DEVNULL,
    )


def publish_result(result: dict) -> None:
    try:
        ensure_result_repo()
        subprocess.run(["git", "-C", str(RESULT_REPO), "fetch", "origin"], check=True, stdout=subprocess.DEVNULL)
        remote = subprocess.run(
            ["git", "-C", str(RESULT_REPO), "show-ref", "--verify", f"refs/remotes/origin/{RESULT_BRANCH}"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        ).returncode == 0
        if remote:
            subprocess.run(["git", "-C", str(RESULT_REPO), "checkout", "-B", RESULT_BRANCH, f"origin/{RESULT_BRANCH}"], check=True, stdout=subprocess.DEVNULL)
        else:
            subprocess.run(["git", "-C", str(RESULT_REPO), "checkout", "--orphan", RESULT_BRANCH], check=True, stdout=subprocess.DEVNULL)
            for child in RESULT_REPO.iterdir():
                if child.name != ".git":
                    if child.is_dir():
                        subprocess.run(["rm", "-rf", str(child)], check=True)
                    else:
                        child.unlink()
        out_dir = RESULT_REPO / "ops" / "chatssh" / "results"
        out_dir.mkdir(parents=True, exist_ok=True)
        out_file = out_dir / f"{result['id']}.json"
        out_file.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        subprocess.run(["git", "-C", str(RESULT_REPO), "config", "user.name", "chatssh-gateway"], check=True)
        subprocess.run(["git", "-C", str(RESULT_REPO), "config", "user.email", "chatssh-gateway@localhost"], check=True)
        subprocess.run(["git", "-C", str(RESULT_REPO), "add", str(out_file.relative_to(RESULT_REPO))], check=True)
        subprocess.run(["git", "-C", str(RESULT_REPO), "commit", "-m", f"ChatSSH result {result['id']}"], check=True, stdout=subprocess.DEVNULL)
        subprocess.run(["git", "-C", str(RESULT_REPO), "push", "origin", f"HEAD:{RESULT_BRANCH}"], check=True, stdout=subprocess.DEVNULL)
    except Exception as exc:
        fallback = STATE_DIR / "last-result.json"
        result = dict(result)
        result["publish_error"] = str(exc)
        fallback.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    try:
        command = load_command()
    except Exception:
        return 0
    command_id = command["id"]
    if LAST_ID.exists() and LAST_ID.read_text(encoding="utf-8").strip() == command_id:
        return 0
    script_url = f"https://raw.githubusercontent.com/{REPO}/{command['script_sha']}/{command['script_path']}"
    started = int(time.time())
    result = {
        "schema": 1,
        "id": command_id,
        "script_sha": command["script_sha"],
        "script_path": command["script_path"],
        "started_unix": started,
        "host": os.uname().nodename,
    }
    try:
        script = fetch_bytes(script_url)
        actual = hashlib.sha256(script).hexdigest()
        if actual != command["sha256"]:
            raise RuntimeError(f"script sha256 mismatch: {actual}")
        with tempfile.NamedTemporaryFile(prefix="chatssh-", suffix=".sh", delete=False) as fh:
            fh.write(script)
            script_file = fh.name
        os.chmod(script_file, 0o700)
        try:
            proc = subprocess.run(
                ["/bin/bash", script_file],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=command.get("timeout_seconds", 300),
                env={**os.environ, "CHATSSH_COMMAND_ID": command_id},
            )
        finally:
            Path(script_file).unlink(missing_ok=True)
        result.update({
            "exit_code": proc.returncode,
            "stdout": proc.stdout[-131072:],
            "stderr": proc.stderr[-131072:],
            "finished_unix": int(time.time()),
        })
    except subprocess.TimeoutExpired as exc:
        result.update({"exit_code": 124, "stdout": (exc.stdout or "")[-131072:], "stderr": (exc.stderr or "")[-131072:] + "\nTIMEOUT", "finished_unix": int(time.time())})
    except Exception as exc:
        result.update({"exit_code": 125, "stdout": "", "stderr": str(exc), "finished_unix": int(time.time())})
    LAST_ID.write_text(command_id + "\n", encoding="utf-8")
    publish_result(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
