#!/usr/bin/env python3
"""Validate Control Center deployment.json using the API contract."""

from __future__ import annotations

import argparse
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from api.server import ManifestError, load_manifest  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", nargs="?", default=str(ROOT / "deployment.json"))
    args = parser.parse_args()
    try:
        manifest = load_manifest(args.manifest)
    except ManifestError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    release = manifest["release"]
    print(
        "OK: deployment schema=1 "
        f"version={release['version']} status={release['status']} "
        f"acceptance={release['acceptance']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
