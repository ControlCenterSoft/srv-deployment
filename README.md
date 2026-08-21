# Control Center

Control Center — локальная серверная платформа управления с Web UI, versioned API, RBAC, операциями, аудитом, диагностикой и подписанными атомарными обновлениями.

## Актуальный статус

- **Принятый production baseline:** `1.0.0`.
- **Канонический production release:** `deployment.json` → `1.0.0`, `production-ready`, acceptance `passed`.
- **Активная линия разработки:** `1.1.x`.
- **Текущий проверяемый кандидат:** `1.1.0-rc.2`, exact source `eabca443287996044a26ff23dfb35104cb55fde8`.
- **Тестовый сервер:** фактически уже работает на `1.1.0-rc.2`; повторный real-staging сейчас блокируется не установкой, а тем, что update path трактует exact same-version candidate как ошибку. Это отслеживается в issue `#116` и **не означает принятие 1.1.0**.

До прохождения полного real-server acceptance `main` и канонический production release остаются на `1.0.0`.

Подробный оперативный статус: [`docs/CURRENT-STATE.md`](docs/CURRENT-STATE.md).
План линии 1.1.x: [`docs/releases/1.1.x-development-plan.md`](docs/releases/1.1.x-development-plan.md).

## Принятый release 1.0.0

Stable `1.0.0` продвигает принятую RC-линию без изменения Auth/RBAC, state schema, operations schema, update trust и privileged architecture относительно принятого release contract.

### Release layout

```text
/usr/local/lib/control-center/releases/<release-id>/
/usr/local/lib/control-center/current -> releases/<release-id>
/usr/local/lib/control-center/previous -> releases/<release-id>
/usr/local/lib/control-center/staging/
/usr/local/sbin/control-center-update
/etc/control-center/update-public-key.pem
```

Systemd запускает `/usr/local/lib/control-center/current/control-center`. Release binaries хранятся root-owned и не должны быть writable в штатном режиме.

### Reproducible build

Принятый `1.0.0` собирается exact Go `1.23.2`, объявленным в `go.mod` и release metadata. Build metadata привязаны к полному Git commit SHA и immutable commit timestamp.

```bash
./scripts/build-release.sh
```

Повторная сборка того же commit тем же toolchain должна быть byte-identical.

### Signed update model

Пакет обновления содержит подписанный Ed25519 manifest и release artifact. Installed trusted runtime проверяет подпись, digest, platform, state-schema compatibility и release identity до запуска candidate code. Production private signing key не хранится в репозитории и не устанавливается на managed host.

Обычное обновление:

```bash
sudo control-center-update --package /path/to/control-center-release.tar.gz
```

Downgrade запрещён по умолчанию. Controlled rollback не отменяет проверки подписи, digest, platform и совместимости state schema.

### Installer / repair / uninstall

```bash
sudo ./install/install.sh
sudo ./install/install.sh --repair
sudo ./install/install.sh --reinstall
sudo ./install/uninstall.sh
```

Non-purge uninstall сохраняет configuration/state/trust. `--purge` является явно destructive операцией.

### Первый администратор

Bootstrap local `admin` создаётся только при пустом user state. Начальный credential хранится root-readable в `/var/lib/control-center/bootstrap-admin.secret` и удаляется после успешной смены пароля.

## Линия 1.1.x

Разработка ведётся короткими feature-ветками от актуальной `1.1.x`. Fast CI проверяет policy/secret scan, Go, shell/install, relevant contract/regression tests и быстрый runtime build. Полный candidate gate включает deterministic validation, reproducible amd64/arm64, exact rebuild stable `1.0.0`, disposable install/update/rollback, signed staging package и real test-server staging.

Production promotion 1.1.x запрещён без успешного full acceptance и подтверждённого real-server evidence.

## Архитектурные решения

Канонические ADR находятся в [`docs/adr`](docs/adr):

- ADR-0001 — platform architecture;
- ADR-0002 — installer / repair model;
- ADR-0003 — authentication / RBAC;
- ADR-0004 — state model;
- ADR-0005 — privileged worker;
- ADR-0006 — update integrity;
- ADR-0007 — operations / audit / diagnostics;
- ADR-0008 — parallel development pipeline.

## Локальная разработка

```bash
go test ./...
CONTROL_CENTER_STATE_DIR=$(mktemp -d) go run ./cmd/control-center bootstrap-admin
CONTROL_CENTER_STATE_DIR=<same-dir> CONTROL_CENTER_LOG_DIR=$(mktemp -d) go run ./cmd/control-center
```

Secure default bind остаётся локальным; временная HTTP/IP экспозиция тестового хоста относится только к ops/test configuration и не является production default.

## Проверки

Базовые deterministic checks включают secret/policy scan, unit/contract tests, installer/update acceptance и release-specific full acceptance workflows. Текущий authoritative gate — GitHub CI на exact candidate SHA; документация не может повышать release status без соответствующего evidence.
