# Редакции Home и Professional

## Home

Home — редакция по умолчанию. Она не требует активации. До установки подтверждённой Professional-лицензии API и Web UI показывают `Home`.

## Professional

Professional активируется криптографически подписанной лицензией, привязанной к конкретному серверу.

### ID устройства

Control Center вычисляет ID устройства как первые 24 hex-символа SHA-256 от `/etc/machine-id`. ID отображается в **Настройки → Редакция Control Center** и через:

```bash
curl -fsS http://127.0.0.1:8080/api/license | python3 -m json.tool
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

`expires_at` необязателен. Если он задан, используется Unix timestamp; после его истечения Control Center снова сообщает редакцию Home.

### Подпись

Payload подписывается RSA/SHA-256 приватным ключом издателя. Клиентский сервер содержит только публичный ключ:

```text
/etc/control-center/license-public.pem
```

Приватный ключ **нельзя** помещать в GitHub, установочный пакет, Web UI или сервер клиента.

### Выпуск лицензии

На защищённой машине издателя:

```bash
python3 license/issue-license.py \
  --private-key /secure/control-center-professional-private.pem \
  --device-id DEVICE_ID \
  --license-id CUSTOMER-001
```

Утилита возвращает `payload` и `signature`. Их нужно вставить в **Настройки → Активация Professional**.

### Проверка на сервере

Web UI создаёт только запрос:

```text
/var/lib/control-center/license-pending.json
```

Далее root helper `control-center-license-apply`:

1. декодирует payload и signature;
2. проверяет RSA/SHA-256 подпись;
3. проверяет `edition=Professional`;
4. сверяет `device_id`;
5. проверяет `license_id` и срок действия;
6. сохраняет подтверждённую лицензию в `/var/lib/control-center-license/license.json`.

Подтверждённая лицензия находится вне Web-writable state. Ожидаемые права:

```text
/var/lib/control-center-license             root:control-center 0750
/var/lib/control-center-license/license.json root:control-center 0640
```

Web service может прочитать лицензию как член группы `control-center`, но не может её изменить.

Результат активации хранится в защищённом system-state:

```text
/var/lib/control-center-system/license-status.json
```

Для совместимости Web UI видит его через read-only ссылку `/var/lib/control-center/license-status.json`.

### Диагностика

```bash
curl -fsS http://127.0.0.1:8080/api/license | python3 -m json.tool
systemctl status control-center-license-apply.path --no-pager
journalctl -u control-center-license-apply.service -n 100 --no-pager
sudo cat /var/lib/control-center-system/license-status.json
sudo ls -ld /var/lib/control-center-license
sudo ls -l /var/lib/control-center-license/license.json 2>/dev/null || true
```

## Перенос лицензии

Professional-лицензия привязана к `device_id`. Копирование файла лицензии на сервер с другим `/etc/machine-id` не активирует Professional. При замене сервера следует получить новый device ID и выпустить новую лицензию.
