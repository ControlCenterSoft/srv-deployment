# Диагностика Control Center 1.0.8

## Быстрый acceptance

```bash
sudo bash scripts/acceptance-1.0.8.sh
```

## Определить текущий Web-порт

```bash
PORT=$(sed -n 's/^CONTROL_CENTER_PORT=//p' /etc/control-center/web.env)
echo "$PORT"
curl -fsS "http://127.0.0.1:${PORT}/api/health" | python3 -m json.tool
```

## PostgreSQL

```bash
systemctl status postgresql --no-pager
sudo -u postgres pg_isready
sudo -u control-center psql -d control_center -c 'select current_user,current_database(),version();'
curl -fsS "http://127.0.0.1:${PORT}/api/database/status" | python3 -m json.tool
```

Ожидаются role `control-center`, database `control_center` и local Unix-socket peer authentication.

## Маркет: статус не меняется

```bash
curl -fsS "http://127.0.0.1:${PORT}/api/market" | python3 -m json.tool
sudo cat /var/lib/control-center-system/market-status.json 2>/dev/null | python3 -m json.tool
sudo tail -n 50 /var/lib/control-center-system/market-events.jsonl 2>/dev/null
sudo tail -n 120 /var/lib/control-center-system/market-last.log 2>/dev/null
systemctl status control-center-market-apply.path --no-pager
systemctl status control-center-market-apply.service --no-pager
journalctl -u control-center-market-apply.service -n 200 --no-pager
```

Если `market-status.json` остаётся `installing` более 30 минут, API 1.0.8 переводит карточку в `Ошибка` как stale operation. Подробность доступна в `status.detail` и tooltip.

## DHCP не установился

Проверить пакет и protected state:

```bash
dpkg-query -W -f='${Status}\n' dnsmasq 2>/dev/null || true
sudo cat /var/lib/control-center-system/modules/dhcp.json 2>/dev/null | python3 -m json.tool
sudo cat /etc/dnsmasq.d/control-center-dhcp.conf 2>/dev/null
sudo dnsmasq --test --conf-file=/etc/dnsmasq.d/control-center-dhcp.conf 2>/dev/null || true
sudo tail -n 120 /var/lib/control-center-system/market-last.log
```

Если пакет `dnsmasq` уже установлен, а module state отсутствует, повторная кнопка **Установить** может выполнить recovery только когда есть признаки предыдущей операции Control Center и нет внешних DHCP directives. Это защищает существующий сторонний dnsmasq от автоматического захвата.

Проверить внешние DHCP directives:

```bash
sudo grep -RnsE '^[[:space:]]*(dhcp-range|dhcp-host|dhcp-option)[= ]' \
  /etc/dnsmasq.conf /etc/dnsmasq.d 2>/dev/null || true
```

Если обнаружена чужая конфигурация, сначала необходимо вручную решить конфликт; Control Center не удаляет и не присваивает её автоматически.

Если от старой неудачной версии осталась mask:

```bash
ls -l /etc/systemd/system/dnsmasq.service 2>/dev/null || true
```

1.0.8 удаляет ссылку на `/dev/null` автоматически только при подтверждённом Control Center recovery-контексте.

## Уведомления установки отсутствуют

```bash
sudo tail -n 50 /var/lib/control-center-system/market-events.jsonl
curl -fsS "http://127.0.0.1:${PORT}/api/notifications" | python3 -m json.tool
sudo -u control-center psql -d control_center -c \
  'select source,title,state,severity,is_read,last_seen_at,message from control_center.notification_events order by last_seen_at desc limit 50;'
```

## Кнопка «Установить обновление» неактивна

```bash
curl -fsS "http://127.0.0.1:${PORT}/api/settings/update/check" | python3 -m json.tool
```

Проверьте `remote.available=true` и `update_available=true`. Кнопка намеренно неактивна для актуальной версии/build.

Systemd manual trigger:

```bash
systemctl status control-center-update-now.path --no-pager
systemctl is-enabled control-center-update-now.path
journalctl -u control-center-update.service -n 200 --no-pager
```

Если marker остался:

```bash
ls -l /var/lib/control-center/update-now 2>/dev/null || true
```

Worker удаляет marker после захвата запроса.

## Web UI после смены порта

```bash
sudo cat /etc/control-center/web.env
sudo cat /var/lib/control-center-system/web-status.json 2>/dev/null || true
systemctl status control-center --no-pager
systemctl status control-center-web-apply.path --no-pager
journalctl -u control-center-web-apply.service -n 150 --no-pager
ss -ltnp | grep gunicorn
```

## WAN/LAN

```bash
ip -br link
ip -j -4 addr
curl -fsS "http://127.0.0.1:${PORT}/api/network/config" | python3 -m json.tool
sudo cat /var/lib/control-center-system/network-config.json 2>/dev/null || true
sudo cat /etc/netplan/90-control-center.yaml 2>/dev/null || true
sudo netplan generate
```

## DHCP после настройки

```bash
systemctl status control-center-dhcp-server.service --no-pager
journalctl -u control-center-dhcp-server.service -n 150 --no-pager
curl -fsS "http://127.0.0.1:${PORT}/api/dhcp/config" | python3 -m json.tool
sudo cat /var/lib/control-center-system/dhcp-status.json 2>/dev/null | python3 -m json.tool
```

## Control Center updater и rollback

```bash
systemctl status control-center-update.timer --no-pager
systemctl status control-center-update-now.path --no-pager
journalctl -u control-center-update.service -n 200 --no-pager
cat /opt/control-center/VERSION
cat /opt/control-center/BUILD
sudo find /var/lib/control-center-root -maxdepth 2 -name 'control-center-db.dump' -ls
```

## Professional

```bash
curl -fsS "http://127.0.0.1:${PORT}/api/license" | python3 -m json.tool
sudo cat /var/lib/control-center-system/license-status.json 2>/dev/null || true
```

## Все компоненты

```bash
systemctl list-unit-files | grep '^control-center'
systemctl list-timers --all | grep control-center
systemctl list-units --type=path | grep control-center
ls -l /usr/local/sbin/control-center-*
```
