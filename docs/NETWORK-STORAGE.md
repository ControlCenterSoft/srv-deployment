# Сетевое хранилище — Control Center 1.0.11

## Назначение

Служба **Сетевое хранилище** активирует управляемый SMB-ресурс и может работать:

- отдельно от Домена — Samba standalone;
- как обязательная часть Домена — Samba AD-DC SMB.

Пользовательские данные по умолчанию:

```text
/srv/control-center/storage/public
```

Удаление службы не удаляет этот каталог и пользовательские файлы.

## Standalone

При установке Control Center:

- устанавливает Samba/smbclient/ACL packages, если нужны;
- создаёт только собственный managed `smb.conf`;
- не захватывает внешнюю Samba-конфигурацию;
- запускает standalone SMB service;
- сохраняет ownership packages в module state.

## Domain dependency

Домен без Сетевого хранилища не создаётся.

Если Storage отсутствует, Domain provisioning создаёт доменный SMB-resource автоматически.

Если standalone Storage уже существует:

1. его module/config сохраняются в root-only install context;
2. исходный SMB state попадает в pre-provision backup;
3. Samba переводится в AD-DC;
4. share добавляется в domain `smb.conf` между managed markers;
5. доступ получают `Domain Users`, административный доступ — `Domain Admins`;
6. при удалении Домена исходный standalone Storage восстанавливается.

## Ограничения

При активном Домене Storage удалить нельзя. Это обязательная dependency Домена.

## Удаление standalone Storage

Удаляется служебная Samba-конфигурация и package только когда package был установлен самой службой. Пользовательский data path сохраняется.

Cleanup audit:

```text
/var/lib/control-center-system/cleanup-audits/storage-<timestamp>.json
```

После удаления menu item деактивируется.

## RBAC

1.0.11 использует базовую модель доступа. Module помечается `rbac_ready`, а migration 005 создаёт RBAC schema для последующего связывания shares, пользователей и групп с granular permissions.
