# Control Center 1.0.5

## Что нового

- две редакции: **Home** и **Professional**;
- Home используется по умолчанию и остается бесплатной редакцией;
- Professional активируется подписанным ключом, привязанным к ID устройства;
- Web UI показывает текущую редакцию, версию, ID устройства и состояние лицензии;
- приватный ключ активации не хранится в репозитории: в продукт включен только публичный ключ проверки;
- в Настройки добавлены обновления ОС и пакетов: автоматический режим с интервалом в минутах и ручной запуск;
- обновления ОС выполняются отдельным root systemd worker, Web UI root-доступ не получает.

## Professional activation

Запрос активации содержит `payload` и `signature`. Root helper проверяет RSA/SHA-256 подпись публичным ключом `/etc/control-center/license-public.pem`, сверяет `device_id` с текущим сервером и только после этого сохраняет Professional-лицензию в `/var/lib/control-center/license.json`.

По умолчанию редакция — Home. Поддерживается срок действия Professional-лицензии через `expires_at`.

## Обновления

### Control Center

Автоматическое обновление Control Center сохраняет существующую логику production-канала и интервал в минутах.

### ОС и пакеты

Настройки: `/var/lib/control-center/os-update-settings.json`.

- автоматическое обновление можно включить/выключить;
- интервал: 60–10080 минут;
- кнопка **Обновить сейчас** запускает ручное обновление;
- worker выполняет `apt-get update` и `apt-get -y upgrade`;
- результат и требование перезагрузки записываются в `/var/lib/control-center/os-update-status.json`.

## Службы 1.0.5

- `control-center.service`
- `control-center-update.timer`
- `control-center-os-update.timer`
- `control-center-license-apply.path`
- `control-center-network-apply.path`
- `control-center-market-apply.path`
- `control-center-dhcp-apply.path`

## Установка

```bash
sudo bash install/install.sh
```

Web UI: `http://SERVER_IP:8080`
