# Сети Control Center 1.0.11

## Сетевые роли

Поддерживаются:

```text
WAN + LAN
только WAN
только LAN
```

В каждой роли есть **«Выключен»**. Обе роли одновременно выключить нельзя.

## Маршрутизация

- WAN Static требует gateway.
- При включённом WAN LAN не создаёт второй default route.
- LAN DHCP при включённом WAN использует `dhcp4-overrides.use-routes: false`.
- В LAN-only режиме LAN может использовать DHCP default route или Static gateway.

## Samba AD-DC

Начиная с 1.0.11 новая доменная роль может использовать только активную WAN/LAN роль со **Static IPv4**.

Предпочтение:

1. Static LAN;
2. Static WAN только при явном подтверждении.

Web API не принимает произвольный IP для AD-DC: interface/IP/prefix определяются из уже применённой Control Center network configuration.

Перед изменением системы privileged Samba worker повторно проверяет, что заявленный IPv4/prefix фактически присутствует на выбранном interface.

## Защита активного контроллера

После успешного Samba AD-DC provisioning обычный POST `/api/network/config` не может:

- выключить роль DC;
- изменить interface DC;
- перевести роль на DHCP;
- изменить IPv4;
- изменить prefix.

Параметры другой сетевой роли можно изменять штатно. Изменение сетевой идентичности самого DC будет отдельным migration lifecycle.

## DNS домена

Локальный resolver активного AD-DC использует IP самого контроллера. Внешнее разрешение выполняет Samba Internal DNS через configured DNS forwarder.

Если Control Center DHCP обслуживает interface DC, DHCP clients получают только AD-DC IPv4 как DNS. Публичные DNS не должны раздаваться доменным клиентам напрямую.

## Dashboard

`/api/system` возвращает `enabled` отдельно для WAN и LAN. UI показывает только графики активных ролей.

## Effective configuration

Applied-state:

```text
/var/lib/control-center-system/network-config.json
```

Выключенная роль сохраняется явно:

```json
{"enabled": false, "interface": "", "method": "disabled"}
```

## Netplan apply

POST `/api/network/config` создаёт request:

```text
/var/lib/control-center/network-pending.json
```

Root helper повторно валидирует configuration, генерирует только активные interfaces в:

```text
/etc/netplan/90-control-center.yaml
```

и выполняет:

```bash
netplan generate
netplan apply
```

Rollback:

```text
/var/lib/control-center-root/90-control-center.yaml.rollback
```

## Диагностика

```bash
curl -fsS http://127.0.0.1:8080/api/network/config | python3 -m json.tool
sudo cat /var/lib/control-center-system/network-config.json
sudo cat /etc/netplan/90-control-center.yaml
ip -br addr
ip route
resolvectl status 2>/dev/null || true
journalctl -u control-center-network-apply.service -n 100 --no-pager
```

После активации Samba AD-DC дополнительно:

```bash
sudo cat /var/lib/control-center-system/modules/samba.json
ip -4 addr show dev <AD-interface>
```
