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

`domain-pre` сохраняет DNS/Storage snapshots, deterministic fingerprints и останавливает standalone DNS для port-53 cutover.

До пакетных изменений `control-center-samba-package-guard` моделирует реальную APT-транзакцию Domain provisioning. Для всех затрагиваемых пакетов фиксируются исходные presence/version и manual/auto mark. Для уже установленных пакетов заранее сохраняются точные rollback `.deb`. Если точную обратимость обеспечить нельзя, provisioning не начинается.

Core создаёт root-only Samba backup, устанавливает packages, выполняет `samba-tool domain provision`, Kerberos/resolver/NTP cutover и acceptance.

`domain-post` активирует обязательные DNS/Storage dependencies и bootstrap-группу `Control Center Admins`. Группа, membership `Administrator` и SID resolution являются обязательными: ошибка на этом этапе считается ошибкой provisioning и вызывает полный rollback.

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
Administrator SID -> UID 0
smbclient
Control Center Admins -> Administrator membership
DNS dependency health
Storage dependency health
portal auth daemon health
```

Provisioning использует RFC2307 schema extension. На самом AD-DC системное SID→Unix сопоставление остаётся функцией локального `idmap.ldb`. Перед SMB acceptance Control Center отдельно доказывает, что встроенный `Administrator` (RID 500) преобразуется в UID 0. Если конкретная Samba-сборка не выполняет built-in mapping при локальном RFC2307 lookup, Control Center отключает только `idmap_ldb:use rfc2307` lookup на DC, сохраняя NIS schema, перезапускает AD-DC и повторно требует корректное SID→UID 0 перед продолжением.

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

После успешного provisioning точный пакетный pre-state до удаления хранится root-only в:

```text
/var/lib/control-center-root/domain-package-prestate/
```

После этого удаление Домена:

1. generated AD runtime удаляется;
2. восстанавливает точные версии пакетов, их исходное наличие/отсутствие и APT manual/auto marks;
3. восстанавливает pre-domain Samba/DNS/Kerberos/resolver/chrony/DHCP state;
4. возвращает standalone DNS/Storage, если они существовали до Домена;
5. ротирует portal session secret;
6. выполняет cleanup-audit;
7. сравнивает deterministic config fingerprints с состоянием до provisioning;
8. требует отсутствия generated `sam.ldb` и SYSVOL, если их не было до Домена;
9. удаляет пакетный recovery pre-state только после успешного его применения.

Пакетный rollback намеренно не выполняет `autoremove`, чтобы не удалить зависимости, которые могут использоваться посторонним ПО.

Recovery bundle destruction сохраняется намеренно как root-only аварийная копия.

## PostgreSQL

Migration 004 хранит AD lifecycle/health. Migration 005 добавляет RBAC/service dependency/cleanup schema.

Secrets в DB не сохраняются.
