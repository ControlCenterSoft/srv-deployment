# Samba AD-DC — подготовка Control Center 1.0.10

## Статус

Control Center 1.0.10 — последний подготовительный этап перед включением production provisioning в следующем релизе.

В **1.0.10 установка Samba и `samba-tool domain provision` намеренно отключены**. Релиз выполняет только чтение состояния, readiness, формирование dry-run change plan и сохранение результатов.

Целевой релиз включения provisioning: **1.0.11**.

## PostgreSQL

Migration `002` сохраняется неизменной и содержит базовые таблицы:

```text
control_center.ad_dc_profiles
control_center.ad_dc_nodes
control_center.ad_dc_preflight_runs
```

Migration `003_samba_ad_dc_readiness.sql` добавляет:

```text
control_center.ad_dc_readiness_runs
control_center.ad_dc_change_plans
```

и дополнительные поля readiness/planning в `ad_dc_profiles`.

Секрет Administrator, Kerberos keys и другие секреты в этих таблицах не сохраняются.

## Readiness API

```text
GET/POST /api/samba/readiness
```

Проверки разделены на **blocker** и **warning**.

### Blocker

- DNS-совместимое имя компьютера;
- полноценный FQDN, не `.local`;
- минимум один активный статический IPv4 на WAN или LAN;
- подтверждённая синхронизация времени;
- доступность обязательных APT-пакетов;
- минимум 2 GiB свободного места на `/`.

Обязательные пакеты readiness:

```text
samba
samba-dsdb-modules
samba-vfs-modules
winbind
krb5-user
dnsutils
acl
attr
```

### Warning / будущий cutover

Проверяются текущие listeners:

```text
53   DNS
88   Kerberos
389  LDAP
445  SMB
```

Наличие listener не всегда блокирует подготовку, но обязательно входит в план cutover/rollback.

Дополнительно фиксируются:

- `systemd-resolved`;
- Control Center DHCP/dnsmasq;
- фактическая цель `/etc/resolv.conf`;
- существующий `/etc/samba/smb.conf`;
- установленная версия Samba;
- активные WAN/LAN роли.

## Dry-run plan

```text
GET/POST /api/samba/plan
```

API не изменяет Samba/DNS/Kerberos. Он формирует воспроизводимый change plan и SHA-256 плана.

План содержит:

1. обязательный набор пакетов;
2. выбранную сетевую роль и planned IPv4;
3. DNS backend `SAMBA_INTERNAL`;
4. список backup targets;
5. порядок service cutover;
6. порядок rollback;
7. acceptance-команды.

Backup targets перед будущим provisioning:

```text
/etc/samba
/etc/krb5.conf
/etc/resolv.conf
/etc/netplan/90-control-center.yaml
/var/lib/samba
```

## План acceptance для 1.0.11

После будущего provisioning должны пройти минимум:

```text
samba-tool domain info
samba-tool drs showrepl
kinit Administrator
host -t SRV _ldap._tcp
host -t SRV _kerberos._udp
smbclient -L localhost
timedatectl NTPSynchronized=yes
```

До прохождения этих проверок AD-DC не должен считаться успешно опубликованным.

## Поддержка одной сетевой роли

1.0.10 допускает работу Control Center:

- WAN + LAN;
- только WAN;
- только LAN.

Readiness AD-DC выбирает LAN как предпочтительную статическую роль. Если LAN выключен, допускается единственная статическая WAN-роль — метка роли не должна искусственно блокировать одноинтерфейсный сервер.

## Имя компьютера

В **Настройки → Имя компьютера** можно изменить hostname перед будущим provisioning. Разрешено single-label DNS-совместимое имя длиной 1–63 символа: латинские буквы, цифры и дефис.

Изменение выполняется отдельным root-helper с backup `/etc/hostname`, `/etc/hosts` и rollback.

## Почему provisioning отключён

Provisioning AD-DC меняет критические компоненты сервера: DNS, Kerberos, LDAP, SMB, resolver, Samba database и SYSVOL. Поэтому 1.0.10 не содержит скрытого или экспериментального вызова `samba-tool domain provision`.

1.0.11 должен добавить provisioning только вместе с:

- отдельным privileged lifecycle worker;
- секретом Administrator без plaintext в PostgreSQL;
- backup до первого изменения;
- DNS/resolver cutover;
- rollback;
- automated acceptance;
- Market lifecycle status и уведомлениями.

## Диагностика

При HTTP:

```bash
PORT=$(sudo sed -n 's/^CONTROL_CENTER_PORT=//p' /etc/control-center/web.env)
curl -fsS "http://127.0.0.1:${PORT}/api/samba/readiness" | python3 -m json.tool
curl -fsS -X POST "http://127.0.0.1:${PORT}/api/samba/plan" | python3 -m json.tool
```

При self-signed HTTPS используйте `https://` и `curl -k`.

PostgreSQL history:

```bash
sudo -u control-center psql -d control_center -c \
  'select id,created_at,hostname,fqdn,ready,blockers,warnings from control_center.ad_dc_readiness_runs order by id desc limit 10;'

sudo -u control-center psql -d control_center -c \
  'select plan_id,state,checksum,created_at from control_center.ad_dc_change_plans order by created_at desc limit 10;'
```
