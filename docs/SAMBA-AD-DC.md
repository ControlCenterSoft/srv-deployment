# Домен / Samba AD-DC — Control Center 1.0.11

## Назначение

Служба **Домен** создаёт новый первичный Samba Active Directory Domain Controller и включает:

- Samba Internal DNS;
- Kerberos;
- LDAP;
- SYSVOL / NETLOGON;
- signed NTP через chrony;
- обязательное доменное Сетевое хранилище;
- Domain authentication для портала Control Center.

## Обязательные зависимости

Домен не может существовать без:

```text
DNS
Сетевого хранилища
```

Если службы отсутствуют, они активируются автоматически. Если standalone DNS/Storage уже были установлены Control Center, они сохраняются в install-context и переводятся в domain mode.

Автоматический takeover внешнего, неуправляемого AD-DC запрещён.

## Readiness / initial wizard

Проверяются:

- hostname;
- Realm и NetBIOS domain;
- активная Static IPv4 роль;
- time sync;
- APT packages;
- disk space;
- listeners 53/88/389/445;
- существующая Samba/DNS topology;
- DNS forwarder;
- отсутствие незавершённых DNS/Storage jobs.

LAN предпочтителен. WAN требует отдельного подтверждения.

## Provision approval

```bash
sudo control-center-samba-approve
```

Код purpose-bound, one-time, TTL 10 минут. В root runtime хранится только SHA-256.

Administrator password не сохраняется в PostgreSQL/persistent state и не передаётся через `--adminpass`.

## Provisioning

Orchestrator:

```text
control-center-domain-pre
control-center-samba-apply-core
control-center-domain-post
```

`domain-pre` сохраняет DNS/Storage snapshots, package topology, deterministic fingerprints и останавливает standalone DNS для port-53 cutover.

Core создаёт root-only Samba backup, устанавливает packages, выполняет `samba-tool domain provision`, Kerberos/resolver/NTP cutover и acceptance.

`domain-post` активирует обязательные DNS/Storage dependencies и bootstrap-группу `Control Center Admins`.

При любой ошибке pre-domain state восстанавливается.

## Acceptance

Успех требует:

```text
samba-tool testparm
samba-tool ntacl sysvolcheck
samba-tool domain info
samba-tool drs showrepl --summary
DNS A
LDAP SRV
Kerberos SRV
kinit Administrator
smbclient
DNS dependency health
Storage dependency health
portal auth daemon health
```

## DHCP

Если DHCP обслуживает interface контроллера, он автоматически выдаёт IP AD-DC как единственный DNS. Внешние DNS остаются Samba forwarders.

## Ограничения активного DC

Обычными настройками нельзя:

- переименовать DC;
- выключить его network role;
- сменить Static на DHCP;
- сменить interface/IP/prefix;
- удалить DNS;
- удалить Storage;
- забронировать DC IP DHCP-клиенту.

Такие изменения требуют отдельного будущего AD migration lifecycle.

## Domain authentication

После provisioning на портале доступен Domain login. `Administrator` добавляется в bootstrap-группу `Control Center Admins`; её membership даёт роль `admin`. Другие доменные пользователи получают `viewer` до перехода на granular RBAC.

## Удаление Домена

Поддерживается защищённое destruction для **единственного DC**.

Получить отдельный removal code:

```bash
sudo control-center-samba-approve --remove
```

Дополнительно UI требует фразу `УДАЛИТЬ ДОМЕН`.

Перед destruction создаётся:

```text
/var/lib/control-center-root/domain-destroy-backups/<timestamp>/
```

После этого:

1. generated AD runtime удаляется;
2. восстанавливается pre-domain Samba/DNS/Kerberos/resolver/chrony/DHCP state;
3. standalone DNS/Storage возвращаются, если существовали до Домена;
4. portal session secret ротируется;
5. выполняется cleanup-audit;
6. deterministic config fingerprints сравниваются с состоянием до provisioning;
7. generated `sam.ldb` и SYSVOL должны отсутствовать, если их не было до Домена.

Recovery bundle сохраняется намеренно как root-only аварийная копия.

## PostgreSQL

Migration 004 хранит AD lifecycle/health. Migration 005 добавляет RBAC/service dependency/cleanup schema.

Secrets в DB не сохраняются.
