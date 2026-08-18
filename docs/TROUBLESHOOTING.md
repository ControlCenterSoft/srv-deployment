# Диагностика Control Center 1.0.5

## Общая проверка

```bash
cat /opt/control-center/VERSION
curl -fsS http://127.0.0.1:8080/api/health | python3 -m json.tool
systemctl status control-center --no-pager
ss -ltnp | grep ':8080'
```

## Web UI не открывается

```bash
journalctl -u control-center -n 200 --no-pager
systemctl restart control-center
curl -v http://127.0.0.1:8080/api/health
```

Если локальный health работает, а браузер с другого ПК — нет, проверьте адрес сервера, маршрутизацию и firewall.

## Control Center не обновляется

```bash
cat /var/lib/control-center/update-settings.json
cat /var/lib/control-center/update-status.json 2>/dev/null || true
systemctl status control-center-update.timer --no-pager
sudo systemctl start control-center-update.service
journalctl -u control-center-update.service -n 200 --no-pager
```

Старый updater до исправления аудита мог отклонять релиз из-за формата строки `APP_VERSION`. Один раз установите исправленную 1.0.5 вручную через bootstrap.

## Обновление ОС не запускается

```bash
cat /var/lib/control-center/os-update-settings.json
cat /var/lib/control-center/os-update-status.json 2>/dev/null || true
systemctl status control-center-os-update.timer --no-pager
journalctl -u control-center-os-update.service -n 200 --no-pager
```

Если в журнале указан занятый менеджер пакетов, дождитесь завершения другой операции Control Center/APT и повторите позже.

## Сеть не применяется

```bash
cat /var/lib/control-center/network-status.json
journalctl -u control-center-network-apply.service -n 200 --no-pager
sudo netplan generate
sudo cat /etc/netplan/90-control-center.yaml
ip -br addr
ip route
```

## DHCP не устанавливается

```bash
cat /var/lib/control-center/market-status.json 2>/dev/null || true
journalctl -u control-center-market-apply.service -n 200 --no-pager
systemctl status dnsmasq --no-pager
```

## DHCP-конфигурация отклонена

```bash
cat /var/lib/control-center/dhcp-status.json
journalctl -u control-center-dhcp-apply.service -n 200 --no-pager
sudo dnsmasq --test
```

При ошибке исправленная 1.0.5 восстанавливает предыдущую конфигурацию DHCP.

## Professional не активируется

```bash
curl -fsS http://127.0.0.1:8080/api/license | python3 -m json.tool
cat /var/lib/control-center/license-status.json 2>/dev/null || true
journalctl -u control-center-license-apply.service -n 100 --no-pager
ls -ld /var/lib/control-center-license
```

Типовые причины: неверная подпись, лицензия выпущена для другого `device_id`, истёк `expires_at` или использован ключ от старой тестовой пары.

## Список всех компонентов

```bash
systemctl list-unit-files | grep '^control-center'
systemctl list-timers --all | grep control-center
systemctl list-units --type=path | grep control-center
ls -l /usr/local/sbin/control-center-*
```
