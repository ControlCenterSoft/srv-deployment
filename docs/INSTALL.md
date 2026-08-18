# Установка Control Center 1.0.8

Текущий production build: **20260819.2**.

## Обычная установка / обновление

```bash
git clone --depth 1 --branch release/1.0.8 https://github.com/filosoff31/srv-deployment.git
cd srv-deployment
sudo bash install/install.sh
```

Целевая платформа: Ubuntu Server 26.04 LTS, systemd, Netplan, root/sudo и доступ к APT-репозиториям.

Installer автоматически:

1. выполняет guarded repair `dpkg --configure -a` / `apt-get -f install -y` перед основной миграцией;
2. не удаляет существующую конфигурацию dnsmasq;
3. блокирует автозапуск `dnsmasq` во время package-repair через временный `policy-rc.d`;
4. устанавливает/проверяет PostgreSQL;
5. применяет SQL migrations;
6. сохраняет текущий Web-порт;
7. устанавливает root helpers, timers/path units и production Gunicorn runtime;
8. проверяет `/api/health` и `/api/database/status`.

## Сервер застрял на 1.0.6 после code 100

Если наблюдаются одновременно:

- Control Center остаётся на `1.0.6`;
- notification: `Обновление ... завершилось ошибкой; восстановлена версия 1.0.6`;
- Market: `код 100` или `dnsmasq, установленный вне Control Center`;
- OS/package update также завершается ошибкой,

используйте специальный recovery script:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/filosoff31/srv-deployment/release/1.0.8/scripts/repair-upgrade-1.0.6-to-1.0.8.sh \
  | sudo bash
```

Скрипт не заменяет updater. Он:

1. создаёт backup/diagnostics в `/var/lib/control-center-root/manual-repair-<timestamp>/`;
2. сохраняет dnsmasq config и текущие update/Market statuses;
3. подготавливает safe recovery marker только если stale dnsmasq не имеет активной внешней конфигурации;
4. временно разрешает немедленную production-проверку;
5. запускает существующий updater 1.0.6, поэтому его штатный application rollback остаётся активным;
6. после успешного перехода на 1.0.8 восстанавливает пользовательские настройки автообновления;
7. при безопасном legacy-сценарии восстанавливает DHCP module state.

Если обнаружена активная пользовательская конфигурация `/etc/dnsmasq.conf` или `/etc/dnsmasq.d/*`, автоматический захват пакета не выполняется.

## После установки

```bash
cat /opt/control-center/VERSION
cat /opt/control-center/BUILD
PORT=$(sed -n 's/^CONTROL_CENTER_PORT=//p' /etc/control-center/web.env)
curl -fsS "http://127.0.0.1:${PORT}/api/health" | python3 -m json.tool
curl -fsS "http://127.0.0.1:${PORT}/api/database/status" | python3 -m json.tool
curl -fsS "http://127.0.0.1:${PORT}/api/market" | python3 -m json.tool
sudo bash scripts/acceptance-1.0.8.sh
```

Ожидается:

```text
1.0.8
20260819.2
ACCEPTANCE: PASSED
```

## PostgreSQL

Runtime DSN:

```text
dbname=control_center user=control-center host=/var/run/postgresql
```

Локальное подключение идёт через Unix socket/peer authentication. Пароль PostgreSQL в приложении не хранится, внешний PostgreSQL listener installer не включает.

## Web UI

По умолчанию:

```text
http://SERVER_IP:8080
```

Если Web-порт был изменён ранее, installer сохраняет его.

## Удаление

```bash
sudo bash install/uninstall.sh
```

С сохранением application data:

```bash
sudo bash install/uninstall.sh --keep-data
```

## Диагностика

```bash
journalctl -u control-center-update.service -n 200 --no-pager
journalctl -u control-center-market-apply.service -n 200 --no-pager
journalctl -u control-center-os-update.service -n 200 --no-pager
sudo tail -n 100 /var/lib/control-center-root/upgrade-preflight-1.0.8.log 2>/dev/null || true
sudo tail -n 100 /var/lib/control-center-system/market-last.log 2>/dev/null || true
dpkg --audit
```
