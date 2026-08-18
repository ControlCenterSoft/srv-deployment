#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys


def fail(message: str) -> None:
    raise SystemExit(f"INSTALL PAYLOAD BUILD FAIL: {message}")


def inside(root: Path, relative: str) -> Path:
    candidate = (root / relative).resolve()
    try:
        candidate.relative_to(root)
    except ValueError:
        fail(f"path escapes repository: {relative}")
    return candidate


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("repo_root")
    parser.add_argument("profile")
    parser.add_argument("output")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    profile_path = Path(args.profile).resolve()
    output = Path(args.output).resolve()
    if not repo_root.is_dir():
        fail("repository root is missing")
    if not profile_path.is_file():
        fail("install profile is missing")

    profile = json.loads(profile_path.read_text(encoding="utf-8"))
    if profile.get("schema_version") != 1:
        fail("unsupported install profile schema")
    layers = profile.get("payload_layers")
    patches = profile.get("post_assembly_patches") or []
    if not isinstance(layers, list) or not layers:
        fail("payload_layers must be a non-empty array")

    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True, mode=0o750)

    applied_layers: list[str] = []
    for raw in layers:
        if not isinstance(raw, str) or not raw:
            fail("invalid payload layer")
        layer = inside(repo_root, raw)
        if not layer.is_dir():
            fail(f"payload layer is missing: {raw}")
        shutil.copytree(layer, output, dirs_exist_ok=True, symlinks=True)
        applied_layers.append(raw)

    applied_patches: list[dict[str, str]] = []
    for item in patches:
        if not isinstance(item, dict):
            fail("invalid post_assembly_patches item")
        script_raw = item.get("script")
        target_raw = item.get("target")
        if not isinstance(script_raw, str) or not isinstance(target_raw, str):
            fail("patch script/target must be strings")
        script = inside(repo_root, script_raw)
        target = inside(output, target_raw)
        if not script.is_file():
            fail(f"patch script is missing: {script_raw}")
        if not target.is_file():
            fail(f"patch target is missing after assembly: {target_raw}")
        result = subprocess.run(
            [sys.executable, str(script), str(target)],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
            timeout=60,
        )
        if result.returncode != 0:
            fail(f"patch failed: {script_raw}: {(result.stdout or '').strip()[-2000:]}")
        applied_patches.append({"script": script_raw, "target": target_raw})

    required = [
        "app",
        "templates",
        "static",
        "migrations",
        "alembic.ini",
        "requirements.lock",
        "app/main.py",
        "app/routers/minecraft_legacy.py",
        "templates/minecraft.html",
        "static/js/minecraft-status-2.1.2.js",
    ]
    missing = [item for item in required if not (output / item).exists()]
    if missing:
        fail("assembled payload is incomplete: " + ", ".join(missing))

    router = (output / "app/routers/minecraft_legacy.py").read_text(encoding="utf-8")
    if '["/usr/bin/sudo", "-n", str(helper), *args]' in router:
        fail("assembled Minecraft router still contains forbidden sudo privilege path")
    template = (output / "templates/minecraft.html").read_text(encoding="utf-8")
    if "/static/js/minecraft-status-2.1.2.js" not in template:
        fail("assembled Minecraft template is missing live status layer")

    print(json.dumps({
        "ok": True,
        "baseline_release": profile.get("baseline_release"),
        "payload_layers": applied_layers,
        "patches": applied_patches,
        "output": str(output),
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
