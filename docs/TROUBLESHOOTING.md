# Диагностика Control Center 1.0.7

## Быстрый acceptance

```bash
sudo bash scripts/acceptance-1.0.7.sh
```

## Определить текущий Web-порт

```bash
PORT=$(sed -n 's/^CONTROL_CENTER_PORT=//p' /etc/control-center/web.env)
echo "$PORT"
curl -fsS "http://127.0.0.1:${PORT}/api/health" | python3 -m json.tool
```

Не используйте автоматически `8080` при диагностике: пользователь мог изменить порт.

## PostgreSQL недоступен

```bash
systemctl status postgresql --no-pager
sudo -u postgres pg_isready
sudo -u control-center psql -d control_center -c 'select current_user,current_database(),version();'
journalctl -u postgresql -n 150 --no-pager
```

Ожидается локальный current user `control-center` и database `control_center`.

Если `psql` сообщает `Peer authentication failed`, проверьте локальные правила `pg_hba.conf`. Control Center 1.0.7 рассчитывает на local Unix-socket peer authentication для одноимённой Linux/PostgreSQL УЗ и не хранит DB password.

## Проверить migrations

```bash
sudo -u control-center psql -d control_center -c \
  'select version,name,checksum,applied_at from control_center.schema_migrations order by version;'
```

Если runner сообщает `checksum mismatch`, не изменяйте уже применённый migration. Верните исходный файл и создайте следующий migration с новым номером.

## Database API

```bash
curl -fsS "http://127.0.0.1:${PORT}/api/database/status" | python3 -m json.tool
```

Проверьте `database=control_center`, `role=control-center`, migration и зарегистрированный local node.

## Web UI не открывается после смены порта

На самом сервере:

```bash
sudo cat /etc/control-center/web.env
sudo cat /var/lib/control-center-system/web-status.json 2>/dev/null || true
systemctl status control-center --no-pager
systemctl status control-center-web-apply.path --no-pager
journalctl -u control-center-web-apply.service -n 150 --no-pager
ss -ltnp | grep gunicorn
```

Если localhost health на новом порту работает, а удалённый браузер — нет, проверьте firewall/ACL/reverse proxy. Control Center не изменяет внешний firewall при смене порта.

Root helper должен автоматически вернуть старый порт, если restart/localhost health-check не прошёл.

## Настройки обновлений не сохраняются

```bash
sudo -u control-center psql -d control_center -c \
  "select key,value,updated_at from control_center.settings where key in ('control_center.update','os.update','web.port');"
cat /var/lib/control-center/update-settings.json
cat /var/lib/control-center/os-update-settings.json
```

PostgreSQL — application source для Web-настроек; JSON остаётся compatibility mirror для root workers.

## Уведомления

```bash
curl -fsS "http://127.0.0.1:${PORT}/api/notifications" | python3 -m json.tool
sudo -u control-center psql -d control_center -c \
  'select source,title,state,severity,is_read,last_seen_at from control_center.notification_events order by last_seen_at desc limit 30;'
```

Read/unread теперь хранится в БД, а не в localStorage.

## Audit

```bash
sudo -u control-center psql -d control_center -c \
  'select created_at,action,resource,status,remote_addr from control_center.audit_events order by id desc limit 30;'
```

До встроенной authentication audit содержит remote address, но не подтверждённую пользовательскую identity.

## Сетевые интерфейсы / WAN / LAN

```bash
ip -br link
ip -j -4 addr
curl -fsS "http://127.0.0.1:${PORT}/api/network/config" | python3 -m json.tool
sudo cat /var/lib/control-center-system/network-config.json 2>/dev/null || true
sudo cat /etc/netplan/90-control-center.yaml 2>/dev/null || true
sudo netplan generate
```

## DHCP

```bash
systemctl status control-center-dhcp-server.service --no-pager
sudo cat /var/lib/control-center-system/dhcp-config.json 2>/dev/null || true
sudo cat /etc/dnsmasq.d/control-center-dhcp.conf 2>/dev/null || true
sudo dnsmasq --test --conf-file=/etc/dnsmasq.d/control-center-dhcp.conf
curl -fsS "http://127.0.0.1:${PORT}/api/dhcp/config" | python3 -m json.tool
```

Если DHCP не установлен, 404 для DHCP API допустим.

## Control Center updater

```bash
systemctl status control-center-update.timer --no-pager
journalctl -u control-center-update.service -n 200 --no-pager
cat /opt/control-center/VERSION
cat /opt/control-center/BUILD
sudo find /var/lib/control-center-root -maxdepth 2 -name 'control-center-db.dump' -ls
```

Начиная с 1.0.7 updater создаёт PostgreSQL dump перед будущим обновлением, если БД уже существует.

## Professional

```bash
curl -fsS "http://127.0.0.1:${PORT}/api/license" | python3 -m json.tool
sudo cat /var/lib/control-center-system/license-status.json 2>/dev/null || true
journalctl -u control-center-license-apply.service -n 100 --no-pager
```

## Все компоненты

```bash
systemctl list-unit-files | grep '^control-center'
systemctl list-timers --all | grep control-center
systemctl list-units --type=path | grep control-center
ls -l /usr/local/sbin/control-center-*
```

## Ошибки последнего часа

```bash
journalctl -p warning..alert --since '1 hour ago' --no-pager
```
