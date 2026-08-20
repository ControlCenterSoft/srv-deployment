# DNS — Control Center 1.0.11

## Два режима

### Standalone

Устанавливается из Маркета независимо от Домена.

Provider: **Unbound**.

Требования:

- активная WAN или LAN роль;
- Static IPv4;
- минимум один внешний IPv4 forwarder.

Managed config:

```text
/etc/unbound/unbound.conf.d/control-center.conf
```

Module state:

```text
/var/lib/control-center-system/modules/dns.json
```

## Domain

При создании Домена DNS обязателен. Provider становится **Samba Internal DNS**.

Если standalone DNS уже был установлен:

1. его module/config сохраняются в root-only Domain install context;
2. Unbound останавливается перед port-53 cutover;
3. Samba Internal DNS получает IP контроллера;
4. внешний DNS используется только как Samba forwarder;
5. при штатном удалении Домена standalone DNS возвращается в исходное состояние.

Если DNS до Домена не существовал, dependency создаётся автоматически только в domain mode.

## Конфигурация

`POST /api/dns/config` изменяет forwarders.

В Domain mode Control Center изменяет `dns forwarder` Samba, проверяет `samba-tool testparm` и перезапускает `samba-ad-dc.service` с rollback `smb.conf` при ошибке.

## Ограничения

DNS нельзя удалить, пока активен Домен, потому что AD discovery зависит от DNS SRV/A records.

## Удаление standalone DNS

Удаляются только управляемые Control Center конфигурация/state и package, если именно Control Center его установил. Чужой pre-existing package не должен удаляться как owned package.

Cleanup audit сохраняется в:

```text
/var/lib/control-center-system/cleanup-audits/dns-<timestamp>.json
```

Audit проверяет отсутствие managed config/module и неуспешный/успешный итог отображается в колокольчике.
