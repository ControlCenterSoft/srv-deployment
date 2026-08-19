# Samba AD-DC — Control Center 1.0.11

## Статус

В Control Center 1.0.11 активирован production lifecycle для **создания нового первичного Samba Active Directory Domain Controller**.

1.0.11 поддерживает provisioning нового домена. Автоматическое уничтожение домена, переименование активного DC и перенос DC на другой IP/interface в этот релиз не входят.

## Требования

Перед provisioning:

- выбранная WAN/LAN роль должна быть включена;
- роль должна использовать Static IPv4;
- LAN предпочтительна;
- WAN требует отдельного подтверждения;
- время сервера должно быть синхронизировано;
- production Samba packages должны быть доступны в APT;
- необходимо минимум 2 GiB свободного места;
- Realm должен быть полноценным DNS-доменом, не `.local`;
- NetBIOS domain: 1–15 символов;
- должен быть указан внешний IPv4 DNS forwarder.

## Readiness

```text
POST /api/samba/readiness
```

Проверяются:

- hostname и целевой FQDN;
- Realm/NetBIOS;
- Static IPv4 выбранной роли;
- NTP/time sync;
- Samba/Kerberos/Chrony packages;
- свободное место;
- текущие listeners 53/88/389/445;
- существующий `/etc/samba/smb.conf`;
- UFW state;
- DNS forwarder.

Если обнаружена внешняя Samba-конфигурация, provisioning блокируется до явного разрешения на backup и замену.

## Production plan

```text
POST /api/samba/plan
```

План описывает:

1. target Realm/FQDN/interface/IP;
2. backup;
3. package installation;
4. service cutover;
5. Samba domain provision;
6. Kerberos/resolver cutover;
7. signed NTP;
8. DHCP DNS integration;
9. acceptance;
10. rollback.

## Локальное подтверждение

Provisioning является root/high-impact операцией. Пока встроенная Web-аутентификация панели не завершена, одного Web POST недостаточно.

На сервере выполните:

```bash
sudo control-center-samba-approve
```

Команда создаёт одноразовый 8-символьный код. Хранится только SHA-256 кода:

```text
/run/control-center-root/samba-approval.json
```

Свойства:

- TTL 10 минут;
- one-time use;
- root-only 0600;
- файл удаляется после попытки проверки.

## Пароль Domain Administrator

Пароль Administrator:

- проверяется Web API и повторно privileged worker;
- 12–128 печатных символов;
- минимум 3 категории: lowercase/uppercase/digits/symbols;
- не хранится в PostgreSQL;
- не хранится в `/var/lib/control-center*`;
- не передаётся через `--adminpass` в process argv;
- secret request создаётся только в `/run/control-center/samba-provision.json` и удаляется worker сразу после чтения;
- для `smbclient` acceptance создаётся временный root-only auth file под `/run`, который удаляется после проверки.

## Root worker

Privileged worker:

```text
/usr/local/sbin/control-center-samba-apply
control-center-samba-apply.path
control-center-samba-apply.service
```

Перед изменением системы worker повторно проверяет:

- job ID;
- Realm;
- NetBIOS domain;
- interface/role;
- IPv4/prefix/network;
- DNS forwarder;
- password policy;
- WAN approval;
- one-time local approval;
- наличие фактического Static IPv4 на выбранном интерфейсе.

## Backup

До package/service/config changes создаётся:

```text
/var/lib/control-center-root/samba-backups/<job-id>/pre-provision.tar.gz
/var/lib/control-center-root/samba-backups/<job-id>/manifest.json
```

В backup при наличии входят:

```text
/etc/samba
/var/lib/samba
/var/cache/samba
/etc/krb5.conf
/etc/resolv.conf
/etc/hosts
/etc/systemd/resolved.conf
/etc/chrony
/var/lib/control-center-system/dhcp-config.json
/etc/dnsmasq.d/control-center-dhcp.conf
```

Manifest также хранит исходное active/enabled состояние затрагиваемых systemd units.

## Package installation

Worker устанавливает:

```text
samba
samba-dsdb-modules
samba-vfs-modules
winbind
krb5-user
dnsutils
acl
attr
smbclient
chrony
```

Во время APT используется временный `policy-rc.d`, чтобы Samba/Chrony services не стартовали до управляемого cutover.

## Domain provisioning

Используется:

```text
server role: dc
dns backend: SAMBA_INTERNAL
use-rfc2307: enabled
interfaces: lo + выбранный interface
bind interfaces only: yes
```

Realm, NetBIOS domain, DNS forwarder и сетевой интерфейс передаются как явные параметры. Administrator password вводится через stdin interactive provisioning и не появляется в argv.

До provisioning distro-generated `/etc/samba/smb.conf` удаляется из рабочего пути после backup.

## DNS и resolver

После успешного provision:

```text
/etc/resolv.conf
search <realm-lower>
nameserver <AD-DC IPv4>
```

Внешние DNS-запросы отправляет Samba Internal DNS через настроенный `dns forwarder`.

Доменным клиентам нельзя напрямую раздавать публичные DNS вместо AD DNS, иначе SRV discovery LDAP/Kerberos становится ненадёжным.

## DHCP integration

Если Control Center DHCP обслуживает тот же interface, worker автоматически заменяет DHCP DNS на:

```text
<AD-DC IPv4>
```

После активации DC API запрещает сохранить на этом DHCP interface другой DNS list. Внешние DNS остаются только Samba forwarders.

## Signed NTP

Chrony настраивается с:

```text
allow <AD network>
ntpsigndsocket /var/lib/samba/ntp_signd
```

`/var/lib/samba/ntp_signd` получает доступ группы `_chrony` (fallback `chrony`) и mode 0750.

## Acceptance

Provisioning считается успешным только после всех проверок:

```bash
samba-tool testparm
samba-tool ntacl sysvolcheck
samba-tool domain info <AD-IP>
samba-tool drs showrepl --summary
host -t A <DC-FQDN> <AD-IP>
host -t SRV _ldap._tcp.<realm> <AD-IP>
host -t SRV _kerberos._udp.<realm> <AD-IP>
kinit Administrator@REALM
smbclient -L //<DC-FQDN>
```

## Health API

```text
GET/POST /api/samba/health
```

Проверяется service state, domain info, replication, DNS A/SRV и SYSVOL ACL. Результаты сохраняются в:

```text
control_center.ad_dc_health_runs
```

и обновляют `health_state` профиля.

## PostgreSQL migration 004

Добавлены:

```text
control_center.ad_dc_lifecycle_jobs
control_center.ad_dc_health_runs
```

`ad_dc_profiles` расширен полями interface/IP/forwarder/managed/provisioned/health.

В lifecycle request сохраняются только публичные параметры. Administrator password и approval code туда не записываются.

## Защита активного DC

После успешного provisioning Control Center блокирует обычными endpoints:

- hostname rename;
- выключение роли DC;
- смену interface DC;
- смену IPv4/prefix DC;
- раздачу внешнего DNS через Control Center DHCP на DC interface.

Для изменения этих параметров потребуется отдельный AD migration lifecycle.

## Rollback

При ошибке worker:

1. прекращает generated Samba/Chrony runtime;
2. удаляет незавершённый generated Samba state;
3. восстанавливает archive;
4. возвращает исходные systemd service states;
5. возвращает Control Center DHCP config/service;
6. удаляет managed module marker;
7. записывает `rollback` в status/DB/колокольчик.

## Удаление Control Center

Автоматическое уничтожение AD domain в 1.0.11 запрещено. Если managed DC активен, обычный uninstall с удалением application data блокируется. Используйте `--keep-data`, если необходимо удалить панель, сохранив состояние управления. Samba database/SYSVOL автоматически не удаляются.
