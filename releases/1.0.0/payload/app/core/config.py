from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import tomllib


CONFIG_FILE = Path("/etc/srv-control/control.toml")


@dataclass(frozen=True)
class AppConfig:
    name: str
    canonical_host: str
    bind_host: str
    bind_port: int
    state_path: str
    cache_path: str
    log_path: str


def load_config() -> AppConfig:
    data: dict = {}

    if CONFIG_FILE.exists():
        with CONFIG_FILE.open("rb") as handle:
            data = tomllib.load(handle)

    application = data.get(
        "application",
        {},
    )

    web = data.get(
        "web",
        {},
    )

    paths = data.get(
        "paths",
        {},
    )

    return AppConfig(
        name=application.get(
            "name",
            "SRV Control Center",
        ),
        canonical_host=web.get(
            "canonical_host",
            "hm.dm",
        ),
        bind_host=web.get(
            "bind_host",
            "127.0.0.1",
        ),
        bind_port=int(
            web.get(
                "bind_port",
                8876,
            )
        ),
        state_path=paths.get(
            "state",
            "/var/lib/srv-control",
        ),
        cache_path=paths.get(
            "cache",
            "/var/cache/srv-control",
        ),
        log_path=paths.get(
            "logs",
            "/var/log/srv-control",
        ),
    )


settings = load_config()
