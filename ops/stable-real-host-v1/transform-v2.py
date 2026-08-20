from pathlib import Path

base_path = Path(__file__).with_name("transform.py")
source = base_path.read_text()
old = '''def once(old: str, new: str, label: str) -> None:\n    global src\n    count = src.count(old)\n    if count != 1:\n        raise SystemExit(f"ERROR: {label}: expected exactly one anchor, found {count}")\n    src = src.replace(old, new, 1)\n'''
new = '''def once(old: str, new: str, label: str) -> None:\n    global src\n    if "\\n" in old or "\\r" in old:\n        count = src.count(old)\n        if count != 1:\n            raise SystemExit(f"ERROR: {label}: expected exactly one full-block anchor, found {count}")\n        src = src.replace(old, new, 1)\n        return\n    lines = src.splitlines(keepends=True)\n    matches = [i for i, line in enumerate(lines) if line.rstrip("\\r\\n") == old]\n    if len(matches) != 1:\n        raise SystemExit(f"ERROR: {label}: expected exactly one full-line anchor, found {len(matches)}")\n    i = matches[0]\n    ending = "\\n" if lines[i].endswith("\\n") else ""\n    lines[i] = new + ending\n    src = "".join(lines)\n'''
if source.count(old) != 1:
    raise SystemExit("ERROR: base transform once() contract mismatch")
code = source.replace(old, new, 1)
exec(compile(code, str(base_path), "exec"), {"__name__": "__main__", "__file__": str(base_path)})
