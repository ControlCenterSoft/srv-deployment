# Control Center — надёжность deployment

> **Статус:** текущий operational contract плюс исторический incident record. Раздел про 0.3.0 сохранён для трассируемости и не является инструкцией текущей production-линии.

## Текущая модель

Для production 2.0.x release transaction рассматривается как единое проверяемое изменение:

```text
preflight → policy-controlled backup → apply → acceptance → healthcheck
                                                   ↘ failure → rollback
```

`deployment.json` определяет опубликованный production target. Каталог `releases/<version>` после публикации считается frozen. Исправление выпускается новой версией, а не редактированием старого payload.

### Preflight

Preflight должен выявлять blockers до изменения production state: обязательные зависимости, доступность критичных путей, валидность metadata/manifest, совместимость migration path и другие release-specific условия.

Preflight не должен требовать здоровья компонента, который сам release предназначен восстановить, если этот компонент не является обязательной предпосылкой безопасного apply.

### Backup и rollback snapshot

Пользовательский `backup_before_update` определяется policy. Отдельно release apply может создавать внутренний rollback snapshot изменяемых файлов/state. Такой snapshot не должен подменять пользовательский backup в UI или нарушать выбранную backup policy.

### Apply

Apply изменяет только предусмотренные release contract области, выполняет migrations/units/helpers и обязан сохранять возможность rollback там, где это технически предусмотрено.

### Acceptance

Acceptance проверяет именно состояние после текущего release: release metadata, application/API health, необходимые systemd units, migrations и критичные release-specific contracts.

Проверки должны быть release-relative и не зависеть от устаревших абсолютных путей предыдущего release.

### Healthcheck

Общий healthcheck подтверждает, что Control Center после acceptance действительно обслуживает production path. Ложный отрицательный healthcheck не должен приводить к бесконечному повторному destructive apply.

### Rollback

Rollback должен возвращать предыдущую рабочую конфигурацию/payload/state в пределах заявленного release contract и затем повторно проверять service health. Нельзя считать rollback успешным только потому, что скрипт завершился с кодом 0.

## Idempotency и retry protection

Deployment orchestration должен защищаться от повторного применения уже успешно принятого release. Product updater использует accepted release fingerprint и блокирует бесконечное автоматическое повторение одного и того же known-failed fingerprint.

Documentation-only commits не должны запускать повторный apply неизменившегося product release.

## Service reload/restart

Способ reload/restart определяется активным release. Graceful reload предпочтителен там, где он подтверждён runtime contract; unit/runtime migrations могут требовать полноценного restart. Нельзя переносить конкретную механику Uvicorn 0.x на все будущие релизы без проверки активного unit.

---

## Исторический incident: release 0.3.0

Во время 0.3.0 наблюдался повторный restart с периодом GitHub agent. Причиной был не crash нового FastAPI кода, а устаревший общий healthcheck от `channel-probe`: после успешных preflight/apply/acceptance он ожидал старый marker, завершался ошибкой, не позволял записать успешный deployed SHA, и следующий timer-cycle повторял apply.

Исторические исправления включали:

- замену общего healthcheck на проверку фактического result/acceptance/health;
- защиту orchestrator от повторного apply уже принятого `release_id + remote_sha`;
- graceful Uvicorn worker rotation для тогдашней service model.

Эти сведения объясняют происхождение современных idempotency/health требований, но конкретные marker-файлы и worker mechanics 0.x не должны использоваться как текущая production-инструкция.

## Release gate

Перед переключением production pointer на новый release должны быть подтверждены:

1. syntax/static checks и manifest integrity;
2. preflight contract;
3. migration/backup/rollback readiness;
4. apply contract;
5. application/release-specific acceptance;
6. общий healthcheck;
7. updater/fingerprint state;
8. релевантные regression tests;
9. синхронизированная документация и release history;
10. отсутствие secrets в payload, docs и diagnostics.

Только после успешного gate новый release может считаться production-ready.

См. `AUTO-UPDATES.md`, `PRODUCT-MANUAL-RU.md`, `RELEASE-HISTORY.md` и version-specific validation в `2.0/`.