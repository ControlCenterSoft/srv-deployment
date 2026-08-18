# Control Center — системное администрирование

> Актуальная эксплуатационная модель production-линии. Исторические инструкции 0.x про отдельного bootstrap web-пользователя/пароль не применяются.

## Аутентификация и первый вход

Control Center не ведёт отдельную базу web-паролей. Первый интерактивный вход выполняется **существующей локальной Linux либо доменной Samba/winbind учётной записью**.

Поддерживаемая цепочка:

1. NSS разрешает identity и группы;
2. PAM выполняет authentication/account policy (`srv-control` PAM service);
3. для доменной identity Samba/winbind участвует в NSS/PAM;
4. после успешной authentication Control Center создаёт web-session;
5. RBAC определяет доступ к модулям/операциям.

`/var/lib/srv-control/admin-bootstrap.txt` относится к исторической архитектуре и не является способом текущего первого входа.

### Kerberos/SPNEGO

Kerberos/SPNEGO — **дополнительный SSO path**, а не замена PAM/NSS contract. Он считается рабочим только при согласованной настройке DNS, времени, SPN/keytab, reverse proxy и браузера/клиента. `401` с `WWW-Authenticate: Negotiate` может инициировать browser-level challenge; если SSO не развёрнут корректно, это не должно блокировать интерактивный PAM login.

При изменении SSO обязательно проверяйте отдельно `/login`, `/api/v1/auth/login`, `/api/v1/auth/status`, SSO endpoint и поведение session cookie через reverse proxy.

## Authentication, session и authorization — разные уровни

Успешный PAM/winbind login доказывает пароль/account policy, но ещё не доказывает корректность web-session или RBAC. Диагностика выполняется слоями:

```text
DNS/network → NSS identity → PAM/winbind → session cookie → RBAC → privileged action
```

Если POST login успешен, но следующий запрос снова попадает на `/login`, проверяйте `Set-Cookie`, возврат session cookie браузером, session signing key/TTL и reverse-proxy headers. Не диагностируйте такой случай как «неверный пароль» без подтверждения PAM failure.

Полный административный доступ определяется текущей full-admin/server-administrator политикой и RBAC. Обычным пользователям выдаются минимально необходимые Read/Write права.

## Привилегированные действия

Web-приложение работает без root-прав. Системные изменения выполняются через ограниченные root-owned helpers/systemd agents:

```text
Web UI/API → session + CSRF + RBAC → allowlisted action → privileged helper/agent → result/status
```

HTTP-параметры не должны превращаться в произвольные shell-команды. К privileged actions относятся, в зависимости от активного release: system maintenance/reboot, product/OS updates, backup/restore, Samba/domain/shares, Minecraft и install/remove/configure поддерживаемых сервисов.

## Обновления продукта и ОС

Product updater ориентируется на `deployment.json`, manifest активного frozen release и транзакцию:

```text
preflight → safety backup → apply → acceptance → healthcheck
                                      ↘ failure → rollback
```

Product update и обслуживание пакетов ОС — разные процессы. Updater должен различать check/apply, использовать fingerprint, не переустанавливать неизменившийся release после documentation-only commit и не зацикливать known-failed fingerprint. Major OS migration требует отдельного подтверждённого плана.

## Резервное копирование

Scheduled backup и safety backup before update — независимые политики. Restore — высокорисковая privileged operation; после восстановления выполняются release validation/health checks.

## Диагностика доступа

Проверяйте последовательно:

- DNS/доступность web/reverse proxy;
- `getent`/`id` для NSS identity и групп;
- Samba/winbind для domain identity;
- PAM authentication/account;
- HTTP login response и `Set-Cookie`;
- возврат session cookie и `/api/v1/auth/status`;
- Kerberos/SPNEGO только если SSO реально включён;
- RBAC и privileged-agent status.

Пароли, session signing keys, Kerberos key material, tokens и backup contents не сохраняются в Git или публичной диагностике.

См. также [`PRODUCT-MANUAL-RU.md`](PRODUCT-MANUAL-RU.md), [`AUTO-UPDATES.md`](AUTO-UPDATES.md), [`DEPLOYMENT-RELIABILITY.md`](DEPLOYMENT-RELIABILITY.md) и [`RELEASE-HISTORY.md`](RELEASE-HISTORY.md).