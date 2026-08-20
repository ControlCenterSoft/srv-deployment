#!/usr/bin/env python3
"""Classify changed Control Center paths for path-based CI."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Iterable

AI_PATHS = {
    "scripts/gemini_review.py",
    "scripts/perplexity_research.py",
    "scripts/ci_scope.py",
    "tests/test_gemini_review.py",
    "tests/test_perplexity_research.py",
    "tests/test_ci_scope.py",
}


def classify(paths: Iterable[str]) -> dict[str, bool]:
    normalized = [p.strip().lstrip("./") for p in paths if p.strip()]
    go = any(p.endswith(".go") or p in {"go.mod", "go.sum"} for p in normalized)
    shell = any(
        p.endswith(".sh") and (p.startswith("scripts/") or p.startswith("install/"))
        for p in normalized
    )
    ai = any(p in AI_PATHS for p in normalized)
    runtime = any(
        p.startswith(("cmd/", "internal/", "packaging/", "install/"))
        or p in {"go.mod", "go.sum"}
        or (p.startswith("scripts/") and p.endswith(".sh"))
        for p in normalized
    )
    docs = bool(normalized) and all(
        p.startswith("docs/")
        or p in {"README.md", "VALIDATION.md"}
        or p.endswith(".md")
        for p in normalized
    )
    return {"go": go, "shell": shell, "ai": ai, "runtime": runtime, "docs": docs}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--github-output", type=Path)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    import sys

    result = classify(sys.stdin.read().splitlines())
    if args.github_output:
        with args.github_output.open("a", encoding="utf-8") as fh:
            for key, value in result.items():
                fh.write(f"{key}={'true' if value else 'false'}\n")
    if args.json or not args.github_output:
        print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
