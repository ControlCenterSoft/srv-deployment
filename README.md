# Control Center 1.0.11

Control Center — web-панель управления Linux-сервером. Текущий release candidate: **1.0.11**, build **20260819.5**.

## Главное в 1.0.11

- активирован production lifecycle **Samba AD-DC** для создания нового первичного контроллера домена;
- Samba Internal DNS, Kerberos, LDAP, SYSVOL/NETLOGON и signed NTP через chrony;
- обязательный Static IPv4 на выбранной LAN/WAN роли;
- LAN предпочтителен, AD-DC на WAN требует отдельного подтверждения;
- одноразовое локальное подтверждение `sudo control-center-samba-approve` перед provisioning;
- пароль Domain Administrator не сохраняется в PostgreSQL или persistent state и не передаётся в argv процесса;
- root-only backup до изменений Samba/DNS/Kerberos и автоматический rollback при ошибке;
- acceptance после создания: Samba config/SYSVOL, domain info, replication, DNS A/SRV, Kerberos и SMB;
- интеграция с Control Center DHCP: доменным клиентам выдаётся только DNS контроллера;
- после создания домена блокируются переименование DC и изменение/отключение его интерфейса/IP;
- PostgreSQL migration `004` хранит lifecycle jobs и health history;
- отдельный раздел **Samba AD-DC** и статусы в Маркете/колокольчике.

## Создание домена

Сначала настройте серверу постоянный IPv4 в **Сети**. Затем откройте **Samba AD-DC**, укажите DNS Realm, NetBIOS domain, сетевую роль, DNS forwarder и пароль Administrator.

Непосредственно перед созданием домена выполните на сервере:

```bash
sudo control-center-samba-approve
```

Полученный одноразовый код действует 10 минут. После ввода кода и подтверждения Web UI передаёт операцию root worker. Секретный запрос находится только под `/run/control-center` и удаляется worker сразу после чтения.

## Backup и rollback

До первого изменения создаётся backup:

```text
/var/lib/control-center-root/samba-backups/<job-id>/
```

Сохраняются Samba state/config, Kerberos, resolver, hosts, chrony, Control Center DHCP и исходные состояния systemd services. Ошибка provisioning вызывает восстановление backup и публикацию события `rollback`.

## Сеть и DNS

AD-DC требует активную роль со Static IPv4. После успешного provisioning локальный resolver сервера использует Samba DNS, а внешние запросы передаются указанному DNS forwarder.

Если DHCP Control Center работает на том же интерфейсе, он автоматически начинает выдавать IP AD-DC как единственный DNS. Попытка раздать доменным клиентам внешний DNS напрямую блокируется.

## Защита активного DC

Когда Samba AD-DC активен, Control Center не позволяет обычными настройками:

- переименовать компьютер;
- выключить его сетевую роль;
- сменить interface/IP/prefix контроллера.

Эти действия требуют отдельного будущего lifecycle миграции AD.

## Установка

```bash
git clone --depth 1 --branch release/1.0.11 https://github.com/filosoff31/srv-deployment.git
cd srv-deployment
sudo bash install/install.sh
```

Для чистой установки Web UI стартует на `http://SERVER_IP:8080`.

## Acceptance

```bash
sudo bash scripts/acceptance-1.0.11.sh
```

Ожидаемо:

```text
VERSION 1.0.11
BUILD   20260819.5
PostgreSQL migration 004
ACCEPTANCE 1.0.11: PASSED
```

## Удаление

Control Center 1.0.11 не содержит автоматического уничтожения домена. Если управляемый AD-DC активен, uninstall с очисткой application data блокируется. Для удаления самой панели с сохранением данных используется `--keep-data`; `/etc/samba`, `/var/lib/samba`, SYSVOL и AD database не удаляются.

## Безопасность

Встроенная Web-аутентификация административной панели пока не реализована. Поэтому высокорисковый AD provisioning дополнительно требует локальный root-generated one-time code. Web UI необходимо ограничивать доверенной LAN/VPN/firewall и не публиковать напрямую в Интернет.
