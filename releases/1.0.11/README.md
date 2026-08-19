# Control Center 1.0.11

Build **20260819.5**. Статус до финальной публикации: **production candidate**.

## Состав релиза

1. **Домен** добавлен в Маркет и переведён в production lifecycle Samba AD-DC.
2. **DNS** добавлен как самостоятельная служба: standalone Unbound; вместе с Доменом — Samba Internal DNS.
3. **Сетевое хранилище** добавлено как самостоятельная служба: standalone Samba; вместе с Доменом — domain SMB.
4. Домен имеет обязательные зависимости DNS + Storage и автоматически активирует их.
5. Local/Domain авторизация портала включена через isolated root auth daemon.
6. Создан первоначальный Domain wizard.
7. После activation защищены hostname/interface/IP/prefix DC и обязательные зависимости.
8. Поддерживается guarded Domain removal для единственного DC с recovery и cleanup fingerprint audit.
9. DNS/Storage выполняют cleanup-audit при удалении; Storage сохраняет пользовательские файлы.
10. DHCP показывает clients и управляет IP reservations.
11. Migration **005** создаёт RBAC bootstrap, service dependencies, DHCP reservations и cleanup history.

## Domain wizard

Этапы:

```text
Readiness / Static network
Realm + NetBIOS
DNS + Storage dependencies
Administrator password + one-time approval
Final plan / create
```

Provision approval:

```bash
sudo control-center-samba-approve
```

Removal approval:

```bash
sudo control-center-samba-approve --remove
```

Оба кода one-time, TTL 10 минут и имеют разные purpose.

## Portal authentication

Local identities проверяются PAM, Domain identities — Samba `ntlm_auth`. Проверка выполняется `control-center-authd`; Web process остаётся непривилегированным.

Root через Web запрещён. Bootstrap roles: `admin`, `viewer`. Domain group `Control Center Admins` даёт `admin`. Migration 005 уже содержит schema для будущего granular RBAC.

## Domain dependencies

```text
Domain requires DNS
Domain requires Network Storage
```

Standalone DNS/Storage могут существовать без Domain. При Domain transition их исходные state/config сохраняются; после Domain removal они восстанавливаются.

## Cleanup / recovery

Перед Domain destruction создаётся root-only recovery bundle. Removal разрешён только когда доказано, что это единственный DC.

Cleanup audit проверяет:

- отсутствие active AD dependency state;
- возврат DNS/Storage к pre-domain providers;
- deterministic pre-state fingerprints;
- удаление generated `sam.ldb`/SYSVOL, если их не было до Domain;
- наличие recovery backup.

## DHCP 1.0.11

Client inventory объединяет leases и reservations. Можно бронировать/менять/освобождать IP. Проверяются subnet, gateway/network/broadcast, duplicate, active lease conflicts и DC IP.

## Acceptance

```bash
sudo bash scripts/acceptance-1.0.11.sh
```

Disposable CI дополнительно запускает:

```bash
sudo -E bash scripts/runtime-acceptance-1.0.11.sh
```

Runtime acceptance выполняет настоящий цикл standalone DNS/Storage → Domain → Domain auth/DHCP → Domain removal/restore → standalone DNS/Storage removal.

Финальный `deployment.json audit=passed` допускается только после зелёных release + runtime workflows на publication head.
