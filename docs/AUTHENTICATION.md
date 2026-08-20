# Авторизация Control Center 1.0.11

## Режимы входа

Портал поддерживает:

- **Local** — Linux/PAM;
- **Domain** — после активного Samba AD-DC.

Без сессии доступны только `/login`, `/api/auth/login`, `/api/health` и static assets. Остальные API требуют сессию.

## Локальная авторизация

Root через Web не допускается. Системные UID также не используются как portal identities.

Bootstrap-роли:

- пользователь в `control-center-admins` → `admin`;
- другой допустимый локальный пользователь → `viewer`.

Если installer не находит локального администратора с рабочим паролем, создаётся `controladmin` с `/usr/sbin/nologin`. Случайный пароль показывается только в выводе установки.

## Доменная авторизация

После Domain provisioning портал принимает:

```text
user
DOMAIN\user
user@realm
```

При этом учётная запись всегда привязывается к локально управляемому домену. Cross-domain имя не принимается как локальный bootstrap login.

Доменная группа `Control Center Admins` получает bootstrap-роль `admin`; остальные успешно аутентифицированные доменные пользователи получают `viewer`.

Membership определяется через Samba SID, а не по UNIX GID.

## Изолированный auth daemon

Web-процесс не читает `/etc/shadow` и не получает `winbindd_priv`.

```text
control-center (unprivileged)
        │ Unix socket 0660 root:control-center
        ▼
control-center-authd (root, sandboxed)
        ├─ PAM/pamtester
        └─ ntlm_auth + wbinfo
```

Socket:

```text
/run/control-center-auth/auth.sock
```

Daemon проверяет `SO_PEERCRED` и принимает запросы только от UID `control-center`.

## Сессии

- HttpOnly;
- SameSite=Strict;
- Secure при HTTPS;
- lifetime 8 часов;
- session secret хранится в `/etc/control-center/auth.env` mode 0640;
- после удаления Домена secret ротируется и все старые сессии становятся недействительными.

## RBAC

Migration 005 создаёт:

```text
control_center.rbac_roles
control_center.rbac_bindings
```

Сейчас используется bootstrap `admin/viewer`. Эти таблицы предназначены для перехода к granular RBAC без смены модели идентификации пользователей.

## Audit

Успешные/неуспешные входы и отказы авторизации записываются в `control_center.audit_events`. Пароли туда не попадают.
