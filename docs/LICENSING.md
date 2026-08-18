# Редакции Home и Professional

## Home

Home — редакция по умолчанию. Она не требует активации. До установки подтверждённой Professional-лицензии API и Web UI показывают `Home`.

## Professional

Professional активируется криптографически подписанной лицензией, привязанной к конкретному серверу.

### ID устройства

Control Center вычисляет ID устройства как первые 24 hex-символа SHA-256 от `/etc/machine-id`. ID отображается в **Настройки → Редакция Control Center** и через:

```bash
curl -fsS http://127.0.0.1:8080/api/license
```

### Формат payload

```json
{
  "edition": "Professional",
  "device_id": "DEVICE_ID",
  "license_id": "LICENSE-ID",
  "issued_at": 0,
  "expires_at": 0
}
```

`expires_at` необязателен. Если он задан, используется Unix timestamp и лицензия перестаёт считаться активной после указанного времени.

### Подпись

Payload подписывается RSA/SHA-256 приватным ключом издателя. Сервер содержит только публичный ключ `/etc/control-center/license-public.pem`.

Приватный ключ **нельзя** помещать в GitHub, установочный пакет, Web UI или сервер клиента.

### Выпуск лицензии

На защищённой машине издателя:

```bash
python3 license/issue-license.py \
  --private-key /secure/control-center-professional-private.pem \
  --device-id DEVICE_ID \
  --license-id CUSTOMER-001
```

Утилита вернёт `payload` и `signature`. Их необходимо вставить в **Настройки → Активация Professional**.

### Проверка на сервере

Web UI создаёт `/var/lib/control-center/license-pending.json`. Затем root helper `control-center-license-apply`:

1. декодирует payload и signature;
2. проверяет RSA/SHA-256 подпись;
3. проверяет `edition=Professional`;
4. сверяет `device_id`;
5. проверяет срок действия;
6. сохраняет подтверждённую лицензию в `/var/lib/control-center-license/license.json`.

Каталог `/var/lib/control-center-license` принадлежит `root:root`; Web-процесс имеет только доступ на чтение. Результат активации записывается в `/var/lib/control-center/license-status.json`.

### Диагностика

```bash
curl -fsS http://127.0.0.1:8080/api/license | python3 -m json.tool
systemctl status control-center-license-apply.path --no-pager
journalctl -u control-center-license-apply.service -n 100 --no-pager
cat /var/lib/control-center/license-status.json
ls -ld /var/lib/control-center-license
ls -l /var/lib/control-center-license/license.json
```

Ожидаемые права подтверждённой лицензии: владелец `root:root`, файл не должен быть доступен Web-пользователю на запись.
