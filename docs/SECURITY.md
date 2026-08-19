# Безопасность Control Center 1.0.11

## Web process

Web UI работает как непривилегированный `control-center`. Для 80/443 используется только `CAP_NET_BIND_SERVICE`. Root lifecycle вынесен в отдельные systemd workers.

## Авторизация портала активна

В 1.0.11 включена встроенная Local/Domain авторизация.

- без сессии административные API возвращают 401;
- `viewer` не может выполнять POST/PUT/PATCH/DELETE;
- `admin` получает изменения;
- root Web login запрещён;
- login rate-limit: 8 неуспешных попыток на IP+username за 5 минут.

Сессии: HttpOnly, SameSite Strict, Secure при HTTPS, lifetime 8 часов.

## Isolated auth daemon

Web-процесс не читает `/etc/shadow` и не получает `winbindd_priv`.

`control-center-authd` работает root, sandboxed и принимает запросы только через:

```text
/run/control-center-auth/auth.sock
root:control-center 0660
```

Daemon проверяет Linux `SO_PEERCRED`: peer UID должен быть UID `control-center`.

Local password проверяется PAM. Domain password — `ntlm_auth`; RBAC bootstrap membership вычисляется по Samba SID (`wbinfo --name-to-sid` + `--user-sids`). Пароли не сохраняются в audit/session/DB.

## Domain provisioning approval

Перед созданием Домена:

```bash
sudo control-center-samba-approve
```

Код:

- случайный 8-hex;
- TTL 600 секунд;
- one-time;
- purpose `samba-ad-dc-provision`;
- в root-only runtime хранится только SHA-256.

Domain Administrator password:

- валидируется Web API и root worker;
- не сохраняется в PostgreSQL/persistent state;
- request живёт только в `/run/control-center`;
- worker удаляет его сразу после чтения;
- пароль не передаётся как `--adminpass` argv.

## Domain removal approval

Destruction использует отдельный purpose-bound код:

```bash
sudo control-center-samba-approve --remove
```

UI дополнительно требует фразу подтверждения. Provision approval нельзя использовать для удаления и наоборот.

Удаление блокируется, если невозможно доказать, что контроллер в домене единственный. Перед destruction создаётся root-only recovery bundle.

## External takeover

Первоначальный мастер не захватывает внешний AD-DC. Если обнаружен неуправляемый Samba Active Directory Domain Controller, readiness/root preflight блокируют provisioning.

Управляемое Control Center standalone-хранилище — отдельный случай: оно может быть автоматически переведено в доменный режим после backup.

## Active DC invariants

После Domain activation запрещены обычными endpoints:

- hostname rename;
- выключение роли DC;
- DHCP вместо Static на DC interface;
- изменение interface/IP/prefix;
- удаление DNS;
- удаление Storage;
- выдача внешнего DNS доменным DHCP-клиентам;
- reservation на IPv4 самого DC.

## Backup / cleanup boundary

Root-only:

```text
/var/lib/control-center-root/samba-backups
/var/lib/control-center-root/domain-destroy-backups
/var/lib/control-center-root/domain-install-context*
```

После Domain removal cleanup-audit сравнивает deterministic pre-state fingerprints и отдельно проверяет generated AD database/SYSVOL. Recovery backup разрешён как единственный намеренно сохраняемый Domain artifact.

DNS/Storage также выполняют собственные cleanup audits.

## Uninstall

Uninstall панели не используется как shortcut для удаления серверных ролей. Полное удаление application state блокируется, пока Domain/DNS/Storage установлены. Службы сначала удаляются через lifecycle Маркета с cleanup-audit.

`--keep-data` сохраняет service metadata/data/recovery state.

## PostgreSQL

DB использует Unix socket + peer authentication. Migration 005 создаёт RBAC/service dependency/DHCP reservation/cleanup history schema. Passwords, approval codes и session secret в DB не хранятся.

## Professional license

Professional license продолжает проверяться RSA/SHA-256 только с vendor public key на сервере. Private signing key не должен попадать в GitHub или клиентскую систему.
