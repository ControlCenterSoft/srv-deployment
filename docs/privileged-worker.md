# Privileged Worker 1.1.x — implementation candidate

Статус: core implementation candidate; production acceptance не выполнен.

## Назначение

Privileged Worker отделяет узкие системные операции от непривилегированного Web/API runtime. Web-процесс не получает root, capabilities, sudo или произвольный shell.

## IPC contract

Worker слушает Unix socket `/run/control-center-privileged/worker.sock` и принимает только один typed JSON request на соединение:

- `schema` — версия IPC contract;
- `operation_id` — 32 lowercase hex символа для correlation;
- `action` — известный typed action;
- `target` — валидированный systemd unit.

Linux peer UID проверяется через `SO_PEERCRED`. Разрешён только пользователь `control-center`. Socket имеет ожидаемую модель `root:control-center` и `0660`.

## Allowlist

В коде существуют только известные действия `systemd.unit.status` и `systemd.unit.restart`; policy дополнительно сужает реально разрешённые действия и targets.

Первоначальный 1.1.x policy должен разрешать только:

```text
CONTROL_CENTER_PRIVILEGED_UNITS=control-center.service
CONTROL_CENTER_PRIVILEGED_ACTIONS=systemd.unit.status
```

Таким образом restart присутствует в typed contract для тестирования/следующих этапов, но по умолчанию fail-closed запрещён policy.

## Execution boundary

Worker не запускает shell. Для systemd используется фиксированный `/usr/bin/systemctl` и фиксированные argv с `--` перед target. Input не может определять executable, shell fragment, environment command или arbitrary arguments.

Timeout ограничен; command output ограничен; системная ошибка/stderr не возвращается клиенту. Worker пишет structured log с `operation_id`, action, target, result/error code и duration.

## Systemd hardening

`control-center-privileged.service` работает как root, но с `NoNewPrivileges=yes`, пустыми `CapabilityBoundingSet`/`AmbientCapabilities`, `ProtectSystem=strict`, `PrivateDevices=yes` и `RestrictAddressFamilies=AF_UNIX`.

Существующий `control-center.service` остаётся пользователем `control-center` без capabilities.

## Upgrade boundary

Stable updater 1.0.0 проверяет пакет с ровно `manifest.json`, `manifest.sig` и `control-center`. Он не имеет контракта на установку нового root-owned systemd unit или policy-файла.

Поэтому первый переход 1.0.0 → 1.1.0 с privileged worker обязан пройти отдельный installer/repair bootstrap с root-level lifecycle acceptance. Нельзя обходить это ограничение произвольными SSH-командами или расширять signed package несовместимо с доверенным updater 1.0.0.

После bootstrap следующая работа должна связать installer/update/uninstall lifecycle обоих services, rollback и acceptance.

## Core tests

Core gate включает:

- validation malformed/unknown JSON;
- target/action allowlist negative tests;
- command/target injection rejection до executor;
- fixed executable/argv proof;
- timeout fail-closed;
- redaction command errors;
- peer UID rejection;
- response operation identity check;
- refusal to overwrite non-socket path;
- `go test -race ./internal/privileged`;
- static systemd policy check.

Наличие этого core не означает production readiness до installer/lifecycle и systemd-host acceptance.
