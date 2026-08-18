# Диагностика Control Center 1.0.9

## Быстрый acceptance

```bash
sudo bash scripts/acceptance-1.0.9.sh
```

## Определить Web runtime

```bash
sudo cat /etc/control-center/web.env
source /etc/control-center/web.env
printf 'port=%s ssl=%s standard=%s\n' "$CONTROL_CENTER_PORT" "${CONTROL_CENTER_SSL:-0}" "${CONTROL_CENTER_STANDARD_PORT:-0}"
```

HTTP:

```bash
curl -fsS "http://127.0.0.1:${CONTROL_CENTER_PORT}/api/health" | python3 -m json.tool
```

HTTPS с self-signed certificate:

```bash
curl -kfsS "https://127.0.0.1:${CONTROL_CENTER_PORT}/api/health" | python3 -m json.tool
```

## Web UI не открывается после перехода на 80/443

```bash
systemctl status control-center --no-pager
systemctl cat control-center
journalctl -u control-center -n 150 --no-pager
journalctl -u control-center-web-apply.service -n 150 --no-pager
ss -ltnp | grep -E ':80 |:443 |gunicorn'
sudo cat /var/lib/control-center-system/web-status.json 2>/dev/null || true
```

Проверьте наличие:

```text
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
```

Если target port занят другим Web server/reverse proxy, Control Center отклонит изменение и должен оставить предыдущий runtime.

## HTTPS и сертификат

```bash
sudo ls -l /etc/control-center/tls
openssl x509 -in /etc/control-center/tls/server.crt -noout -subject -issuer -dates -ext subjectAltName
```

Предупреждение браузера для self-signed certificate ожидаемо. Оно не означает отсутствие шифрования, но сертификат не имеет публично доверенной цепочки.

## Samba AD-DC preflight

```bash
source /etc/control-center/web.env
if [[ "${CONTROL_CENTER_SSL:-0}" == 1 ]]; then
  curl -kfsS "https://127.0.0.1:${CONTROL_CENTER_PORT}/api/samba/preflight" | python3 -m json.tool
else
  curl -fsS "http://127.0.0.1:${CONTROL_CENTER_PORT}/api/samba/preflight" | python3 -m json.tool
fi
```

История:

```bash
sudo -u control-center psql -d control_center -c \
  'select id,created_at,hostname,fqdn,ready,checks from control_center.ad_dc_preflight_runs order by id desc limit 10;'
```

Типовые причины `ready=false`: нет полноценного FQDN, LAN не Static либо не подтверждена синхронизация времени. Занятый DNS/53 показывается отдельной проверкой и должен быть разрешён до будущего provisioning.

## PostgreSQL

```bash
systemctl status postgresql --no-pager
sudo -u postgres pg_isready
sudo -u control-center psql -d control_center -c 'select current_user,current_database(),version();'
sudo -u control-center psql -d control_center -c 'select * from control_center.schema_migrations order by version;'
```

Для 1.0.9 последняя migration — `002`.

## Маркет / DHCP

```bash
sudo cat /var/lib/control-center-system/market-status.json 2>/dev/null | python3 -m json.tool
sudo tail -n 50 /var/lib/control-center-system/market-events.jsonl 2>/dev/null
sudo tail -n 120 /var/lib/control-center-system/market-last.log 2>/dev/null
journalctl -u control-center-market-apply.service -n 200 --no-pager
dpkg-query -W -f='${Status}\n' dnsmasq 2>/dev/null || true
sudo dnsmasq --test --conf-file=/etc/dnsmasq.d/control-center-dhcp.conf 2>/dev/null || true
```

## Сеть

```bash
ip -br link
ip -j -4 addr
sudo cat /var/lib/control-center-system/network-config.json 2>/dev/null || true
sudo cat /etc/netplan/90-control-center.yaml 2>/dev/null || true
sudo netplan generate
```

## Обновления

```bash
systemctl status control-center-update.timer --no-pager
systemctl status control-center-update-now.path --no-pager
journalctl -u control-center-update.service -n 200 --no-pager
cat /opt/control-center/VERSION
cat /opt/control-center/BUILD
dpkg --audit
```

## Все компоненты

```bash
systemctl list-unit-files | grep '^control-center'
systemctl list-timers --all | grep control-center
systemctl list-units --type=path | grep control-center
ls -l /usr/local/sbin/control-center-*
```
