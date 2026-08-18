# Установка Control Center 1.0.9

Production build: **20260819.3**, audit `passed`.

## Установка / обновление

```bash
git clone --depth 1 --branch release/1.0.9 https://github.com/filosoff31/srv-deployment.git
cd srv-deployment
sudo bash install/install.sh
```

Целевая платформа: Ubuntu Server 26.04 LTS, systemd, Netplan, root/sudo и доступ к APT-репозиториям.

Installer наследует package-repair и DHCP recovery линии 1.0.8, затем:

1. устанавливает payload 1.0.9;
2. применяет PostgreSQL migrations, включая `002_samba_ad_dc_preparation.sql`;
3. сохраняет текущий Web-порт/режим при обновлении;
4. устанавливает `control-center-web-run` и новый Web apply helper;
5. переводит Web service на непривилегированный Gunicorn wrapper;
6. выдаёт только `CAP_NET_BIND_SERVICE` для портов 80/443;
7. выполняет HTTP/HTTPS health-check.

## После установки

```bash
cat /opt/control-center/VERSION
cat /opt/control-center/BUILD
sudo -u control-center psql -d control_center -Atqc \
  "select version from control_center.schema_migrations order by version desc limit 1"
sudo bash scripts/acceptance-1.0.9.sh
```

Ожидается:

```text
1.0.9
20260819.3
002
ACCEPTANCE: PASSED
```

## Web UI

По умолчанию сохраняется HTTP на текущем пользовательском порту; для чистой установки это:

```text
http://SERVER_IP:8080
```

В **Настройки → Web-панель** можно включить:

- стандартный HTTP порт `80`;
- стандартный HTTPS порт `443`;
- HTTPS на пользовательском порту `1024–65535`.

При первом включении SSL создаётся self-signed certificate. Браузер может показать предупреждение доверия.

Если вы меняете Web runtime удалённо, убедитесь заранее, что firewall/VPN разрешает целевой порт. Control Center проверяет локальный health, но не может гарантировать доступ с вашей рабочей станции через внешний firewall/NAT.

## PostgreSQL

Runtime DSN:

```text
dbname=control_center user=control-center host=/var/run/postgresql
```

Локальное подключение использует Unix socket/peer authentication. Пароль PostgreSQL в приложении не хранится.

Migration `002` добавляет data model будущего Samba AD-DC; provisioning домена при установке 1.0.9 не выполняется.

## Samba AD-DC preflight

После установки можно проверить prerequisites без изменения системы:

```bash
PORT=$(sed -n 's/^CONTROL_CENTER_PORT=//p' /etc/control-center/web.env)
SSL=$(sed -n 's/^CONTROL_CENTER_SSL=//p' /etc/control-center/web.env)
if [[ "$SSL" == 1 ]]; then
  curl -kfsS "https://127.0.0.1:${PORT}/api/samba/preflight" | python3 -m json.tool
else
  curl -fsS "http://127.0.0.1:${PORT}/api/samba/preflight" | python3 -m json.tool
fi
```

## Серверы со старым повреждённым dpkg

Recovery 1.0.8 остаётся частью поддерживаемого upgrade path для старых установок 1.0.6. Если `dpkg --audit` показывает незавершённые пакеты, сначала необходимо привести пакетную систему в чистое состояние штатным recovery-механизмом 1.0.8, а затем переходить на 1.0.9.

## Удаление

```bash
sudo bash install/uninstall.sh
```

С сохранением application data, PostgreSQL и TLS material:

```bash
sudo bash install/uninstall.sh --keep-data
```

## Диагностика

```bash
systemctl status control-center --no-pager
systemctl status control-center-web-apply.path --no-pager
journalctl -u control-center -n 200 --no-pager
journalctl -u control-center-web-apply.service -n 150 --no-pager
sudo cat /etc/control-center/web.env
sudo cat /var/lib/control-center-system/web-status.json 2>/dev/null || true
```

См. `WEB-PORT.md`, `SAMBA-AD-DC.md`, `UI.md` и `TROUBLESHOOTING.md`.
