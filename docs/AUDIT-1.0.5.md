# Аудит Control Center 1.0.5

Дата аудита: 2026-08-18.

## Область проверки

Проверены структура release/main, Web API и Web UI, installer/uninstaller, обновление Control Center, обновление ОС и пакетов, WAN/LAN, DHCP Market и DHCP configuration helper, Home/Professional licensing, документация, public website и bootstrap installer.

## Исправленные дефекты

### Критичные

- Подтверждённая Professional-лицензия ранее находилась в Web-writable state directory. Перенесена в `/var/lib/control-center-license`, владелец `root:root`; Web service получает только чтение.
- Для Professional создана реальная RSA key pair; в репозитории хранится только публичный ключ. Приватный ключ издателя не должен попадать в GitHub или на клиентские серверы.
- Старый updater мог отвергать корректный релиз из-за жёсткого шаблона `APP_VERSION`. 1.0.5 совместима со старым parser, новый parser допускает пробелы вокруг `=`.
- DHCP helper мог оставить повреждённый конфигурационный файл после неудачного `dnsmasq --test`. Добавлен backup/rollback.

### Существенные

- WAN live chart очищал первую линию при отрисовке второй; теперь RX и TX видны одновременно.
- Форма WAN/LAN не восстанавливала сохранённые настройки; восстановлено заполнение формы.
- Установка/удаление DHCP, installer и OS updater могли конкурировать за APT/dpkg; добавлен общий `/run/control-center-apt.lock`.
- `uninstall.sh` не удалял новые services/path/timers/helpers; теперь удаляет весь набор 1.0.5 и поддерживает `--keep-data`.
- DHCP validation дополнена запретом шлюза внутри выдаваемого диапазона.
- OS/package updater использует `upgrade --with-new-pkgs` и сообщает о требуемой перезагрузке.

### Документация и сайт

- `docs/INSTALL.md` был зафиксирован на 1.0.0, `docs/UPDATE.md` — на 1.0.1 и старой модели hour/day/week. Документация полностью синхронизирована с 1.0.5.
- Добавлены руководства Licensing, OS Updates, Network, DHCP, Security, Troubleshooting и индекс документации.
- Публичные страницы сайта статически показывали 1.0.1. Главная, Возможности, Релизы, Документация и Скачать обновлены до 1.0.5; добавлена страница Home/Professional.
- Bootstrap сайта проверен на `release/1.0.5`.
- Усилены HTTP security headers сайта, включая CSP.

## Автоматическая защита от регрессий

Добавлен `.github/workflows/validate-release.yml`, который проверяет:

- Python syntax;
- Bash syntax;
- валидность JSON;
- согласованность `APP_VERSION`, `deployment.json`, release manifest и installer VERSION;
- public RSA key;
- отсутствие приватного signing key в Git;
- наличие обязательных документов.

## Известное ограничение

В 1.0.5 ещё нет полноценной встроенной аутентификации Web UI. TCP/8080 нельзя публиковать напрямую в Интернет или недоверенную сеть. До реализации authentication/session/CSRF доступ должен ограничиваться доверенной LAN/VPN/firewall или защищённым reverse proxy.

## Что не является подтверждённым этим аудитом

Аудит исходников и конфигурации не заменяет acceptance-тест на реальном Ubuntu 26.04 сервере. В текущем инструментальном окружении не выполнялась полноценная VM-установка с systemd/Netplan/dnsmasq и не подтверждался фактический Cloudflare deployment публичного URL после последнего коммита.

## Acceptance checklist на сервере

```bash
cat /opt/control-center/VERSION
curl -fsS http://127.0.0.1:8080/api/health | python3 -m json.tool
systemctl status control-center --no-pager
systemctl list-timers --all | grep control-center
systemctl list-units --type=path | grep control-center
journalctl -p warning..alert --since '1 hour ago' --no-pager
```

Затем отдельно проверить WAN/LAN, установку/настройку/удаление DHCP, manual OS update и тестовую Professional activation.
