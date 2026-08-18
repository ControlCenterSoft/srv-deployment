#!/usr/bin/env python3
"""Validate release upgrade_from contracts.

This is intentionally dependency-free so GitHub Actions and release tooling can
run it with the system Python. It validates the manifest's semantic version
range and can require that every earlier patch in the target minor line is an
accepted source version.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys

VERSION_RE = re.compile(r"^(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$")
CLAUSE_RE = re.compile(r"^(>=|<=|>|<|==)\s*(\d+\.\d+\.\d+)$")


def version(value: str) -> tuple[int, int, int]:
    match = VERSION_RE.match(value.strip())
    if not match:
        raise ValueError(f"unsupported semantic version: {value!r}")
    return tuple(map(int, match.groups()))


def accepted(candidate: tuple[int, int, int], spec: str) -> bool:
    for raw_clause in spec.split(","):
        clause = raw_clause.strip()
        match = CLAUSE_RE.match(clause)
        if not match:
            raise ValueError(f"unsupported upgrade_from clause: {clause!r}")
        op, rhs_text = match.groups()
        rhs = version(rhs_text)
        checks = {
            ">=": candidate >= rhs,
            "<=": candidate <= rhs,
            ">": candidate > rhs,
            "<": candidate < rhs,
            "==": candidate == rhs,
        }
        if not checks[op]:
            return False
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=pathlib.Path)
    parser.add_argument("--require-version", action="append", default=[])
    parser.add_argument(
        "--require-patch-line",
        action="store_true",
        help="Require all earlier patch releases in target major.minor line.",
    )
    parser.add_argument(
        "--server-state-release",
        type=pathlib.Path,
        help="Optional release.json from server-state; installed version must be accepted.",
    )
    args = parser.parse_args()

    data = json.loads(args.manifest.read_text(encoding="utf-8"))
    target_text = str(data.get("release_version") or data.get("release_id") or "")
    spec = str(data.get("upgrade_from") or "").strip()
    if not spec:
        raise SystemExit("manifest upgrade_from is missing")
    target = version(target_text)

    required = list(args.require_version)
    if args.require_patch_line:
        major, minor, patch = target
        required.extend(f"{major}.{minor}.{p}" for p in range(patch))

    if args.server_state_release:
        state = json.loads(args.server_state_release.read_text(encoding="utf-8"))
        installed = str(state.get("version") or state.get("release_version") or "").strip()
        if not installed:
            raise SystemExit("server-state release.json has no installed version")
        required.append(installed)
        print(f"current server-state installed version: {installed}")

    failures: list[str] = []
    seen: set[str] = set()
    for text in required:
        if text in seen:
            continue
        seen.add(text)
        candidate = version(text)
        ok = accepted(candidate, spec)
        print(f"upgrade contract: {text} -> {target_text}: {'PASS' if ok else 'FAIL'} ({spec})")
        if not ok:
            failures.append(text)

    # A release must never advertise an upgrade range that accepts a version
    # newer than the target itself.
    future = (target[0], target[1], target[2] + 1)
    if accepted(future, spec):
        raise SystemExit(
            f"upgrade_from {spec!r} incorrectly accepts future version "
            f"{future[0]}.{future[1]}.{future[2]} for target {target_text}"
        )

    if failures:
        raise SystemExit(
            "upgrade_from does not accept required installed version(s): "
            + ", ".join(failures)
        )

    print("upgrade compatibility contract PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
