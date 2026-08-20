#!/usr/bin/env python3
"""Точка входа сервиса Control Center: миграция и проверка state до запуска HTTP."""

from __future__ import annotations

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from api.server import main as server_main  # noqa: E402
from api.store import StoreError, initialize_store  # noqa: E402


def main() -> int:
    try:
        connection = initialize_store()
    except (OSError, StoreError) as exc:
        raise SystemExit(f"state store initialization failed: {exc}") from exc
    else:
        connection.close()
    return server_main()


if __name__ == "__main__":
    raise SystemExit(main())
