# Установка Control Center 1.0.6

## Целевая платформа

Ubuntu Server 26.04 LTS, systemd, Netplan, root/sudo и доступ к APT-репозиториям. Web UI слушает TCP/8080.

## Установка

```bash
git clone --depth 1 --branch release/1.0.6 https://github.com/filosoff31/srv-deployment.git
cd srv-deployment
sudo bash install/install.sh
```

После установки:

```text
http://IP_СЕРВЕРА:8080
```

## Что сохраняется при обновлении

Повторный запуск установщика сохраняет:

```text
/var/lib/control-center
/var/lib/control-center-system
/var/lib/control-center-root
/var/lib/control-center-license
```

Сохраняются применённые WAN/LAN и DHCP настройки, статусы, Professional license и параметры обновления.

## Live configuration read access

Для корректной загрузки уже настроенных параметров 1.0.6 предоставляет Web service только чтение:

```text
/etc/netplan/90-control-center.yaml        root:control-center 0640
/etc/dnsmasq.d/control-center-dhcp.conf   read-only для Web service
```

Web service не имеет права изменять эти файлы. Запись выполняют только root helpers.

## Web runtime

```text
Gunicorn -> wsgi:app -> Flask application
```

JavaScript вынесен в `/opt/control-center/app/static/app.js`, поэтому CSP 1.0.6 больше не требует `unsafe-inline`.

## Проверка после установки

```bash
cat /opt/control-center/VERSION
curl -fsS http://127.0.0.1:8080/api/health | python3 -m json.tool
systemctl status control-center --no-pager
```

Ожидаемая версия: `1.0.6`.

## Acceptance

```bash
sudo bash scripts/acceptance-1.0.6.sh
```

Проверка не изменяет конфигурацию. Она тестирует:

- version/build/health API;
- CSP и Gunicorn;
- protected state;
- перечень сетевых интерфейсов;
- hydration WAN/LAN;
- notification API;
- Netplan generate;
- DHCP config/status/check при установленном DHCP;
- наличие новой мобильной/UI-разметки.

## Удаление

Полное:

```bash
sudo bash install/uninstall.sh
```

С сохранением state и служебной identity:

```bash
sudo bash install/uninstall.sh --keep-data
```

## Диагностика

```bash
journalctl -u control-center -n 200 --no-pager
ss -ltnp | grep ':8080'
curl -v http://127.0.0.1:8080/api/health
```

См. `docs/TROUBLESHOOTING.md`, `docs/NETWORK.md`, `docs/DHCP.md`, `docs/NOTIFICATIONS.md`.
