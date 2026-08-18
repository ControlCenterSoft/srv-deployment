# Обновление Control Center 1.0.8

## Проверка доступности

`GET /api/settings/update/check` сравнивает установленный `release/build` с Production metadata и возвращает:

```json
{
  "current_version": "1.0.8",
  "current_build": "20260819.1",
  "remote": {},
  "update_available": false,
  "reason": "up-to-date"
}
```

`update_available=true`, если remote release выше либо release совпадает, но Production build отличается.

## Кнопка «Установить обновление»

В **Настройки → Обновления Control Center** кнопка автоматически:

- отключена при актуальной версии;
- активируется только при обнаружении нового Production release/build;
- показывает целевую версию, когда она известна.

Нажатие вызывает:

```text
POST /api/settings/update/install
  -> /var/lib/control-center/update-now
  -> control-center-update-now.path
  -> control-center-update.service
```

Ручной запрос не превращает Web-процесс в root: marker создаёт непривилегированный API, а actual install выполняет существующий root updater.

## Отличие ручного запуска

Manual update request обходится без ожидания выбранного интервала и выполняется даже если automatic updates выключены. Все проверки Production metadata, target payload, version/build, PostgreSQL backup и rollback остаются обязательными.

## Rollback и PostgreSQL

Перед изменением существующей БД updater создаёт root-only `pg_dump -Fc`. При ошибке installer восстанавливаются application payload, systemd unit, Web-port state и PostgreSQL dump.

Если DB backup создать невозможно, updater не начинает обновление.

## Version/build metadata

Authoritative target:

```text
deployment.json
app/release.json
release/<version>
```

Начиная с 1.0.8 `app/release.json` является каноническим payload marker для updater. Runtime version выставляется release extension после загрузки базового приложения.

## Systemd

```bash
systemctl status control-center-update.timer --no-pager
systemctl status control-center-update-now.path --no-pager
systemctl status control-center-update.service --no-pager
journalctl -u control-center-update.service -n 200 --no-pager
```

## API диагностика

```bash
PORT=$(sed -n 's/^CONTROL_CENTER_PORT=//p' /etc/control-center/web.env)
curl -fsS "http://127.0.0.1:${PORT}/api/settings/update/check" | python3 -m json.tool
```

Запуск вручную через API допустим только если `update_available=true`:

```bash
curl -fsS -X POST -H 'Content-Type: application/json' -d '{}' \
  "http://127.0.0.1:${PORT}/api/settings/update/install" | python3 -m json.tool
```

## Compatibility mirror

Web settings хранятся в PostgreSQL, а `/var/lib/control-center/update-settings.json` остаётся compatibility mirror для root updater.

Control Center updater и OS/package updater — независимые механизмы.
