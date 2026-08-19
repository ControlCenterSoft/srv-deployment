# Control Center 1.0.11

Статус: **production candidate** до завершения финального CI, build **20260819.5**.

## Samba AD-DC активирован

В 1.0.11 подготовительный слой 1.0.10 переведён в рабочий production lifecycle для создания **нового первичного Samba Active Directory Domain Controller**.

Поддерживается:

- проверка Realm и NetBIOS domain;
- выбор активной статической LAN/WAN роли;
- Samba Internal DNS и внешний DNS forwarder;
- установка Samba/Kerberos/Winbind/Chrony и сопутствующих пакетов;
- создание домена;
- Kerberos configuration;
- локальный resolver на AD DNS;
- LDAP/Kerberos/DNS/SMB/SYSVOL/NETLOGON;
- signed NTP через chrony + `ntp_signd`;
- интеграция с Control Center DHCP;
- PostgreSQL lifecycle/health history;
- Market status и события в колокольчике.

## Безопасное подтверждение

Пока встроенная Web-аутентификация панели не завершена, destructive provisioning не разрешается только по Web-запросу.

Перед созданием домена на самом сервере выполняется:

```bash
sudo control-center-samba-approve
```

Команда выдаёт одноразовый 8-символьный код. Код:

- действует 10 минут;
- используется один раз;
- хранится только как SHA-256 в root-only `/run/control-center-root`;
- после проверки удаляется.

Пароль Domain Administrator:

- не записывается в PostgreSQL;
- не записывается в persistent Control Center state;
- не передаётся в argv `samba-tool`;
- передаётся root worker только через `/run/control-center` и удаляется сразу после чтения;
- временный файл авторизации `smbclient`, используемый acceptance, создаётся root-only в `/run` и удаляется.

## Backup и rollback

До изменения Samba/DNS/Kerberos создаётся root-only backup в:

```text
/var/lib/control-center-root/samba-backups/<job-id>/
```

В backup входят существующие Samba state/config, Kerberos, resolver, hosts, chrony и управляемая DHCP-конфигурация. Также сохраняются состояния затрагиваемых systemd services.

При ошибке provisioning worker:

1. останавливает созданный Samba runtime;
2. удаляет незавершённое generated state;
3. возвращает backup;
4. восстанавливает прежние service states;
5. восстанавливает DHCP state;
6. публикует `rollback` в Samba status и колокольчик.

## Acceptance после provisioning

Provisioning считается успешным только после:

```text
samba-tool testparm
samba-tool ntacl sysvolcheck
samba-tool domain info
samba-tool drs showrepl --summary
DNS A record
LDAP SRV record
Kerberos SRV record
kinit Administrator
smbclient
```

## Сеть

AD-DC разрешён только на активной роли со **Static IPv4**. LAN является предпочтительной ролью. WAN требует отдельного подтверждения в UI.

После успешного создания домена Control Center блокирует:

- переименование DC;
- выключение его WAN/LAN роли;
- смену интерфейса;
- смену IPv4/prefix.

Для таких операций позднее будет отдельный AD migration lifecycle.

## DHCP

Если Control Center DHCP обслуживает тот же интерфейс, после provisioning DNS автоматически меняется на IP контроллера домена. Последующие попытки раздать доменным клиентам внешний DNS напрямую блокируются: внешнее разрешение выполняет Samba DNS forwarder.

## Удаление

1.0.11 **не содержит автоматического уничтожения домена**. Обычный uninstall Control Center не удаляет `/etc/samba`, `/var/lib/samba`, SYSVOL или AD database. Если управляемый AD-DC активен, uninstall с очисткой application data блокируется; допускается `--keep-data`.

## Проверка релиза

```bash
sudo bash scripts/acceptance-1.0.11.sh
```

Финальная публикация разрешена только после static/integration CI и отдельного disposable runtime provisioning test.
