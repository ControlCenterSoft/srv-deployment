# Безопасность Control Center 1.0.11

## Web process

Web UI работает от непривилегированной системной УЗ `control-center`. Root operations выполняются отдельными systemd workers через проверяемые pending requests.

Для Web ports 80/443 службе выдаётся только `CAP_NET_BIND_SERVICE`; Flask/Gunicorn не запускаются от root.

## Встроенная Web-аутентификация

Полноценная встроенная Web-аутентификация административной панели пока не завершена. Поэтому Web UI должен быть доступен только из доверенной LAN/VPN/firewall и не должен публиковаться напрямую в Интернет.

## Samba AD-DC: двойное подтверждение

Domain provisioning — высокорисковая root-операция. В 1.0.11 одного Web POST недостаточно.

Перед созданием домена требуется локально выполнить:

```bash
sudo control-center-samba-approve
```

Команда генерирует случайный 8-hex one-time code. В `/run/control-center-root/samba-approval.json` сохраняется только SHA-256 кода.

Свойства approval:

- root-only;
- TTL 600 секунд;
- purpose-bound `samba-ad-dc-provision`;
- одноразовый;
- удаляется после проверки.

## Administrator password

Domain Administrator password:

- проверяется на совпадение/длину/сложность в Web API;
- повторно проверяется privileged worker;
- не хранится в PostgreSQL;
- не хранится в `/var/lib/control-center*`;
- secret pending request существует только в `/run/control-center`;
- `/run/control-center` доступен только пользователю `control-center` и root;
- worker удаляет pending request сразу после чтения;
- пароль не передаётся как `--adminpass` или другой argv parameter;
- `smbclient` acceptance использует временный root-only credentials file в `/run/control-center-root`, который удаляется после проверки.

Runtime directories создаются через systemd-tmpfiles:

```text
/run/control-center       control-center:control-center 0700
/run/control-center-root  root:root                     0700
```

Они очищаются после reboot как tmpfs runtime state.

## Privileged revalidation

`control-center-samba-apply` не доверяет данным Web validation. Перед mutation он повторно проверяет:

- job ID;
- Realm/NetBIOS syntax;
- сетевую роль;
- interface name;
- IPv4/prefix/network consistency;
- DNS forwarder;
- password policy;
- WAN confirmation;
- approval code;
- фактическое наличие requested Static IPv4 на interface.

## Backup boundary

Samba rollback backups находятся вне Web-writable state:

```text
/var/lib/control-center-root/samba-backups
```

Пользователь `control-center` не имеет доступа к этому каталогу. Backup может содержать существующую Samba database и поэтому должен рассматриваться как секретный материал.

## APT/service cutover

Samba package installation защищена общим APT lock. Временный `policy-rc.d` запрещает автоматический старт Samba/Winbind/Chrony до управляемого cutover. Existing `policy-rc.d`, если он был, восстанавливается.

## Active DC invariants

После provisioning backend блокирует обычными настройками:

- rename hostname активного DC;
- disable/change interface DC;
- change IPv4/prefix DC;
- выдачу внешнего DNS через Control Center DHCP на DC interface.

Это предотвращает случайное разрушение DNS/Kerberos identity домена.

## Domain destruction

1.0.11 не реализует автоматическое удаление/уничтожение AD domain. Uninstall Control Center не удаляет Samba domain database/SYSVOL. Если managed DC активен, uninstall с очисткой application data блокируется.

## PostgreSQL

PostgreSQL использует локальный Unix socket + peer authentication. В lifecycle tables сохраняются только публичные параметры domain plan/job и health results. Administrator password и one-time approval code не должны попадать в DB.

## Professional license

Professional license проверяется RSA/SHA-256. Client/server Control Center содержит только vendor public key. Vendor private signing key не должен храниться в GitHub, installer или пользовательском сервере.
