# Control Center

Control Center — локальная серверная платформа управления с Web UI, versioned API, RBAC, операциями, аудитом, диагностикой и подписанными атомарными обновлениями.

## Актуальный статус

- **Принятый production baseline:** `1.0.0`.
- **Канонический production release:** `deployment.json` → `1.0.0`, `production-ready`, acceptance `passed`.
- **Активная линия разработки:** `1.1.x`.
- **Последний product/runtime-code merge в `1.1.x`:** PR `#176`, merge `e9f5420a8148c68d3b7ddeb96083acfa727993bc`, signed least-privilege diagnostics-agent staging chain. Последующие docs-only commits могут менять branch ref без изменения product/runtime identity.
- **Последний exact server candidate с полным real test-server acceptance:** `1.1.0-rc.6`, source `302eb6da97324d719849e7ae752fc10bdc557d9a`.
- **Тестовый сервер:** фактически остаётся на `1.1.0-rc.6`; установленный Ops Agent/Broker — `1.1.8`. Independently gated diagnostics agent `1.1.10` (`control-center-server-diagnostics#14`, exact `d4337bdd5f3111431ee06858fcd0d3338655751c`) ещё не считается установленным до signed staging и post-update runtime verification.

PR `#176` интегрирован только после зелёных exact-head deterministic CI, Contract & Regression QA PASS и Security Review PASS. Он не выполнял product release, production promotion или test-server mutation. Его задача — дать узкий recovery-aware путь установки только заранее одобренного diagnostics-agent artifact без general sudo и без изменения SO_PEERCRED broker boundary.

До нового полного exact-SHA acceptance `main` и канонический production release остаются на `1.0.0`.

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

### Diagnostics-agent staging boundary

Линия `1.1.x` содержит отдельный test-server-only путь для обновления diagnostics agent. Он намеренно не расширяет основной privileged worker или SO_PEERCRED broker:

- one-time root bootstrap устанавливает только `/usr/local/sbin/control-center-ops-agent-staging-update` и command-scoped sudo rule;
- signed package должен соответствовать pinned repository/path/commit/blob provenance и exact test-server product identity;
- полный root mutation path сериализуется; downgrade и same-version/different-artifact replacement блокируются;
- exact-artifact retry остаётся idempotent;
- failure path восстанавливает предыдущий agent, registration и timer state;
- general passwordless sudo, arbitrary shell и product updater access не выдаются.

Этот путь не является production deployment mechanism и не заменяет server-product Full Acceptance.

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

Production promotion 1.1.x запрещён без успешного full acceptance и подтверждённого real-server evidence на неизменившемся exact candidate SHA.

### Release governance

Каждый обычный новый релиз Control Center обязан включать минимум одну завершённую **User-facing improvement** — новую пользовательскую возможность либо заметное расширение существующего сценария. Release notes должны явно содержать пользовательскую доработку и связанное acceptance evidence.

Refactor, CI/CD, dependencies, документация, тесты, infrastructure, internal agent/transport и performance-only изменения могут интегрироваться в development line, но не должны сами инициировать обычный продуктовый релиз. Исключение — явно обозначенный emergency maintenance/security/hotfix release при риске безопасности, потери данных, недоступности продукта либо поломке update/rollback.

## Архитектурные решения

Канонические ADR находятся в [`docs/adr`](docs/adr):

- ADR-0001 — platform architecture;
- ADR-0002 — installer / repair model;
- ADR-0003 — authentication / RBAC;
- ADR-0004 — state model;
- ADR-0005 — privileged worker;
- ADR-0006 — update integrity;
- ADR-0007 — operations / audit / diagnostics;
- ADR-0008 — parallel development pipeline;
- ADR-0009 — release user-value policy;
- ADR-0010 — parallel delivery operating model;
- ADR-0011 — diagnostics-agent staging trust boundary.

## Локальная разработка

```bash
go test ./...
CONTROL_CENTER_STATE_DIR=$(mktemp -d) go run ./cmd/control-center bootstrap-admin
CONTROL_CENTER_STATE_DIR=<same-dir> CONTROL_CENTER_LOG_DIR=$(mktemp -d) go run ./cmd/control-center
```

Secure default bind остаётся локальным; временная HTTP/IP экспозиция тестового хоста относится только к ops/test configuration и не является production default.

## Проверки

Базовые deterministic checks включают secret/policy scan, unit/contract tests, installer/update acceptance и release-specific full acceptance workflows. Authoritative gate — GitHub CI/QA/Security/Quality/staging evidence на exact candidate SHA; документация не может повышать release status без соответствующего evidence.
