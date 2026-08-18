# Диагностика Control Center 1.0.5

## Быстрый acceptance

Из checkout `release/1.0.5`:

```bash
sudo bash scripts/acceptance-1.0.5.sh
```

Если вывод заканчивается `ACCEPTANCE: FAILED`, исправляйте указанные FAIL сверху вниз.

## Общая проверка

```bash
cat /opt/control-center/VERSION
curl -fsS http://127.0.0.1:8080/api/health | python3 -m json.tool
systemctl status control-center --no-pager
systemctl cat control-center
ss -ltnp | grep ':8080'
```

## Web UI не открывается

```bash
journalctl -u control-center -n 200 --no-pager
systemctl restart control-center
curl -v http://127.0.0.1:8080/api/health
```

Проверьте, что `ExecStart` содержит Gunicorn и `wsgi:app`. Если локальный health работает, а браузер с другого ПК — нет, проверьте адрес, маршрутизацию и firewall.

## Проверка protected state

```bash
ls -ld /var/lib/control-center \
       /var/lib/control-center-system \
       /var/lib/control-center-root \
       /var/lib/control-center-license
find /var/lib/control-center-system -maxdepth 2 -ls
```

Ожидается:
- system-state: `root:control-center`, `0750`;
- root rollback-state: `root:root`, `0700`;
- license-state: `root:control-center`, `0750`.

## Control Center не обновляется

```bash
cat /var/lib/control-center/update-settings.json
sudo cat /var/lib/control-center-system/update-status.json 2>/dev/null || true
systemctl status control-center-update.timer --no-pager
sudo systemctl start control-center-update.service
journalctl -u control-center-update.service -n 200 --no-pager
```

Старый updater до исправления аудита мог отклонять релиз из-за формата `APP_VERSION`. Один раз установите актуальную 1.0.5 вручную через bootstrap.

## Обновление ОС не запускается

```bash
cat /var/lib/control-center/os-update-settings.json
sudo cat /var/lib/control-center-system/os-update-status.json 2>/dev/null || true
systemctl status control-center-os-update.timer --no-pager
journalctl -u control-center-os-update.service -n 200 --no-pager
```

Если менеджер пакетов занят, дождитесь другой APT-операции. Внутренние операции Control Center используют `/run/control-center-apt.lock`.

## Сеть не применяется

```bash
sudo cat /var/lib/control-center-system/network-status.json
sudo cat /var/lib/control-center-system/network-config.json 2>/dev/null || true
journalctl -u control-center-network-apply.service -n 200 --no-pager
sudo netplan generate
sudo cat /etc/netplan/90-control-center.yaml
ip -br addr
ip route
```

Статус `rejected` означает, что privileged helper повторно проверил запрос и отказался применять его.

## DHCP не устанавливается

```bash
sudo cat /var/lib/control-center-system/market-status.json 2>/dev/null || true
journalctl -u control-center-market-apply.service -n 200 --no-pager
sudo cat /var/lib/control-center-system/modules/dhcp.json 2>/dev/null || true
```

Если `dnsmasq` уже установлен вне Control Center, автоматический захват намеренно запрещён. Не удаляйте внешний сервис автоматически; сначала определите, кому он принадлежит и какую конфигурацию обслуживает.

## DHCP установлен, но не выдаёт адреса

```bash
systemctl status control-center-dhcp-server.service --no-pager
journalctl -u control-center-dhcp-server.service -n 150 --no-pager
sudo cat /var/lib/control-center-system/dhcp-status.json
sudo cat /etc/dnsmasq.d/control-center-dhcp.conf
sudo dnsmasq --test --conf-file=/etc/dnsmasq.d/control-center-dhcp.conf
```

Managed DHCP должен работать через `control-center-dhcp-server.service`, а не через `dnsmasq.service`.

## Professional не активируется

```bash
curl -fsS http://127.0.0.1:8080/api/license | python3 -m json.tool
sudo cat /var/lib/control-center-system/license-status.json 2>/dev/null || true
journalctl -u control-center-license-apply.service -n 100 --no-pager
ls -ld /var/lib/control-center-license
ls -l /var/lib/control-center-license/license.json 2>/dev/null || true
```

Типовые причины: неверная подпись, другой `device_id`, истёк `expires_at` или ключ выпущен другой signing pair.

## Проверка всех компонентов

```bash
systemctl list-unit-files | grep '^control-center'
systemctl list-timers --all | grep control-center
systemctl list-units --type=path | grep control-center
ls -l /usr/local/sbin/control-center-*
```

## Общие ошибки последнего часа

```bash
journalctl -p warning..alert --since '1 hour ago' --no-pager
```
