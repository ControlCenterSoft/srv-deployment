# Установка Control Center 1.0.11

Production candidate build: **20260819.5**. Финальный `audit=passed` устанавливается только после успешных release/runtime workflow.

## Установка / обновление

```bash
git clone --depth 1 --branch release/1.0.11 https://github.com/filosoff31/srv-deployment.git
cd srv-deployment
sudo bash install/install.sh
```

Целевая платформа: Ubuntu Server 26.04 LTS, systemd, Netplan, root/sudo и доступ к APT.

Installer:

1. устанавливает payload 1.0.11;
2. применяет PostgreSQL migrations до `004_samba_ad_dc_lifecycle.sql`;
3. сохраняет Web port/SSL/standard-mode при обновлении;
4. устанавливает Web/network/DHCP/hostname helpers;
5. устанавливает `control-center-samba-apply` и `control-center-samba-approve`;
6. создаёт tmpfs runtime directories `/run/control-center` и `/run/control-center-root`;
7. включает `control-center-samba-apply.path`;
8. сохраняет migration retry service;
9. выполняет Web health-check.

## После установки

```bash
cat /opt/control-center/VERSION
cat /opt/control-center/BUILD
sudo -u control-center psql -d control_center -Atqc \
  "select version from control_center.schema_migrations order by version desc limit 1"
sudo bash scripts/acceptance-1.0.11.sh
```

Ожидаемо:

```text
1.0.11
20260819.5
004
ACCEPTANCE 1.0.11: PASSED
```

## Web UI

Чистая установка:

```text
http://SERVER_IP:8080
```

Механизм 1.0.10 для HTTP 80 / HTTPS 443 / custom ports и PostgreSQL-independent Web runtime сохраняется.

## Подготовка Samba AD-DC

Перед созданием домена:

1. назначьте Static IPv4 нужной LAN/WAN роли;
2. убедитесь, что время сервера синхронизировано;
3. откройте раздел **Samba AD-DC**;
4. укажите Realm, NetBIOS domain, сетевую роль и DNS forwarder;
5. выполните readiness.

LAN является предпочтительной ролью. WAN требует отдельного подтверждения.

## Одноразовое локальное подтверждение

Перед нажатием **Создать домен** выполните на сервере:

```bash
sudo control-center-samba-approve
```

Введите выданный код в Web UI. Код действует 10 минут и используется один раз.

Пароль Domain Administrator не сохраняется в PostgreSQL/persistent state. Секретный request живёт только под `/run` до чтения root worker.

## Samba lifecycle services

```bash
systemctl status control-center-samba-apply.path --no-pager
systemctl status control-center-samba-apply.service --no-pager
journalctl -u control-center-samba-apply.service -n 200 --no-pager
sudo cat /var/lib/control-center-system/samba-status.json 2>/dev/null || true
sudo cat /var/lib/control-center-system/modules/samba.json 2>/dev/null || true
```

## Backup

Перед provisioning создаётся root-only backup:

```text
/var/lib/control-center-root/samba-backups/<job-id>/
```

Не удаляйте backup, пока не убедились, что домен и клиенты работают штатно.

## Проверка активного домена

Из Web UI используйте **Samba AD-DC → Проверить состояние** или:

```bash
PORT=$(sudo sed -n 's/^CONTROL_CENTER_PORT=//p' /etc/control-center/web.env)
SSL=$(sudo sed -n 's/^CONTROL_CENTER_SSL=//p' /etc/control-center/web.env)
if [[ "$SSL" == 1 ]]; then
  curl -kfsS -X POST "https://127.0.0.1:${PORT}/api/samba/health" | python3 -m json.tool
else
  curl -fsS -X POST "http://127.0.0.1:${PORT}/api/samba/health" | python3 -m json.tool
fi
```

## Защита после provisioning

Control Center блокирует обычное переименование активного DC и изменение/отключение его interface/IP. DHCP на интерфейсе домена должен раздавать IP AD-DC как единственный DNS.

## Удаление

Автоматическое уничтожение домена не входит в 1.0.11. Если managed AD-DC активен, uninstall с очисткой application data блокируется.

Для удаления панели с сохранением данных:

```bash
sudo bash install/uninstall.sh --keep-data
```

Samba domain database, `/etc/samba`, `/var/lib/samba` и SYSVOL не удаляются автоматически.
