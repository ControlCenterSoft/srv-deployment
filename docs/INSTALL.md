# Установка Control Center 1.0.10

Production build: **20260819.4**, audit `passed`.

## Установка / обновление

```bash
git clone --depth 1 --branch release/1.0.10 https://github.com/filosoff31/srv-deployment.git
cd srv-deployment
sudo bash install/install.sh
```

Целевая платформа: Ubuntu Server 26.04 LTS, systemd, Netplan, root/sudo и доступ к APT-репозиториям.

Installer наследует package-repair и DHCP recovery предыдущих релизов, затем:

1. устанавливает payload 1.0.10;
2. применяет PostgreSQL migrations до `003_samba_ad_dc_readiness.sql`;
3. устанавливает retry-service `control-center-db-migrate.service`, чтобы migrations догнали после временной недоступности PostgreSQL;
4. сохраняет текущие Web port/SSL/standard-mode при обновлении;
5. устанавливает Web apply, hostname apply и single-role network helpers;
6. выдаёт Web-службе только `CAP_NET_BIND_SERVICE` для 80/443;
7. выполняет HTTP/HTTPS health-check.

## После установки

```bash
cat /opt/control-center/VERSION
cat /opt/control-center/BUILD
sudo -u control-center psql -d control_center -Atqc \
  "select version from control_center.schema_migrations order by version desc limit 1"
sudo bash scripts/acceptance-1.0.10.sh
```

Ожидается при доступной PostgreSQL:

```text
1.0.10
20260819.4
003
ACCEPTANCE 1.0.10: PASSED
```

## Web UI

Для чистой установки:

```text
http://SERVER_IP:8080
```

В **Настройки → Web-панель** доступны:

- standard HTTP `80`;
- standard HTTPS `443`;
- custom HTTP/HTTPS `1024–65535`.

Смена Web runtime в 1.0.10 не зависит от доступности PostgreSQL. Источник фактического состояния:

```text
/etc/control-center/web.env
/var/lib/control-center-system/web-config.json
```

Если PostgreSQL временно недоступна, порт/SSL применяются и проходят локальный health-check. После восстановления БД GET Web settings выполняет reconciliation фактических параметров.

При первом включении SSL создаётся self-signed certificate. Браузер может показать предупреждение доверия.

## Переименование компьютера

В **Настройки → Имя компьютера** можно изменить hostname. Операцию выполняет:

```text
/usr/local/sbin/control-center-hostname-apply
```

Перед изменением сохраняются rollback-копии `/etc/hostname` и `/etc/hosts`. Разрешено DNS-совместимое single-label имя длиной до 63 символов.

## Сети

WAN и LAN могут быть выключены по отдельности. Обе роли одновременно выключить нельзя. Поддерживаются WAN+LAN, WAN-only и LAN-only.

## PostgreSQL

Runtime DSN:

```text
dbname=control_center user=control-center host=/var/run/postgresql
```

Локальное подключение использует Unix socket/peer authentication. Пароль PostgreSQL в приложении не хранится.

Migration `003` добавляет Samba AD-DC readiness history/change plans. `control-center-db-migrate.service` повторяет migration при временном DB failure до успешного завершения.

## Samba AD-DC readiness

Проверить подготовку без изменения доменной конфигурации:

```bash
PORT=$(sudo sed -n 's/^CONTROL_CENTER_PORT=//p' /etc/control-center/web.env)
SSL=$(sudo sed -n 's/^CONTROL_CENTER_SSL=//p' /etc/control-center/web.env)
if [[ "$SSL" == 1 ]]; then
  curl -kfsS "https://127.0.0.1:${PORT}/api/samba/readiness" | python3 -m json.tool
  curl -kfsS -X POST "https://127.0.0.1:${PORT}/api/samba/plan" | python3 -m json.tool
else
  curl -fsS "http://127.0.0.1:${PORT}/api/samba/readiness" | python3 -m json.tool
  curl -fsS -X POST "http://127.0.0.1:${PORT}/api/samba/plan" | python3 -m json.tool
fi
```

1.0.10 не выполняет domain provisioning; целевой релиз этого этапа — 1.0.11.

## Диагностика

```bash
systemctl status control-center --no-pager
systemctl status control-center-db-migrate.service --no-pager
systemctl status control-center-web-apply.path --no-pager
systemctl status control-center-hostname-apply.path --no-pager
journalctl -u control-center -n 200 --no-pager
journalctl -u control-center-web-apply.service -n 150 --no-pager
journalctl -u control-center-hostname-apply.service -n 100 --no-pager
sudo cat /etc/control-center/web.env
sudo cat /var/lib/control-center-system/web-status.json 2>/dev/null || true
```

Если меняется Web port или IP удалённо, внешний firewall/NAT/VPN должен разрешать новый адрес. Control Center проверяет локальный health, но не может проверить маршрут от удалённого браузера.

## Удаление

```bash
sudo bash install/uninstall.sh
```

С сохранением данных:

```bash
sudo bash install/uninstall.sh --keep-data
```

См. `WEB-PORT.md`, `SAMBA-AD-DC.md`, `NETWORK.md`, `NOTIFICATIONS.md` и `TROUBLESHOOTING.md`.
