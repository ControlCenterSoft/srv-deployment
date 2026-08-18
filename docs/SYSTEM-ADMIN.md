# Control Center — системное администрирование

> Актуальное описание production-модели администрирования. Инструкции ранней 0.x линии про отдельного bootstrap web-пользователя являются историческими и не относятся к текущей архитектуре.

## Аутентификация и первый вход

Современная production-линия Control Center не ведёт собственную базу web-паролей и не создаёт отдельного bootstrap-пользователя `admin` со случайным первичным паролем.

Интерактивная authentication chain построена на системной identity-модели:

1. локальная Linux-учётная запись разрешается через NSS и проверяется PAM;
2. доменная учётная запись разрешается через Samba/winbind, NSS и PAM;
3. при корректной доменной настройке возможно Kerberos/SPNEGO SSO;
4. после успешной аутентификации Control Center применяет собственный RBAC.

Первый вход выполняется **существующей локальной либо доменной учётной записью**, которой предоставлены необходимые полномочия. Файл `/var/lib/srv-control/admin-bootstrap.txt` относится к исторической архитектуре ранних релизов и не должен использоваться как инструкция для текущей production-линии.

## Authentication и authorization — разные уровни

Authentication отвечает на вопрос «кто пользователь», RBAC — «что ему разрешено».

Успешный PAM/winbind login сам по себе не означает полный административный доступ. После определения identity Control Center учитывает пользователя, его локальные/доменные группы и назначенные права на модули/операции. Полный административный доступ предоставляется только субъектам, соответствующим действующей full-admin/server-administrator политике текущего релиза.

При диагностике входа проверяйте последовательно:

- разрешение пользователя и групп через NSS;
- состояние winbind/Samba для доменных пользователей;
- PAM authentication/account policy;
- Kerberos/SPNEGO, если используется SSO;
- назначения RBAC в Control Center.

Пароли, Kerberos key material, session secrets и другие секреты не должны сохраняться в Git, release metadata или публичной диагностике.

## Привилегированные действия

Web-приложение работает без root-прав. Операции, требующие системных привилегий, передаются специализированным root-owned helper/systemd-agent компонентам.

Типовой контракт:

```text
Web UI/API → session + CSRF + RBAC → allowlisted action request → privileged helper/systemd agent → result/status
```

Agent принимает только предусмотренные типы действий; HTTP-параметры не превращаются в произвольные shell-команды.

К привилегированным операциям, в зависимости от установленного релиза и RBAC, относятся:

- системное обслуживание и reboot;
- product/OS update actions;
- backup/restore;
- Samba/domain/shares;
- Minecraft management;
- install/remove/configure поддерживаемых сервисов.

## Обновления продукта и ОС

Обновление Control Center и обслуживание пакетов ОС — разные процессы.

Product updater ориентируется на `deployment.json`, manifest активного frozen release и транзакционный deployment pipeline:

```text
preflight → safety backup → apply → acceptance → healthcheck
                                      ↘ failure → rollback
```

Automatic updater должен сохранять выбранный режим/период, различать check и apply, не переустанавливать неизменившийся release fingerprint и подавлять бесконечное автоматическое повторение уже известного failed fingerprint до вмешательства администратора.

Control Center не должен автоматически выполнять неподтверждённый переход ОС на новый major distribution release.

## Резервное копирование

Backup schedule и backup-before-update являются независимыми настройками. Отключение планового ежедневного backup не должно автоматически отключать safety backup перед update и наоборот.

Restore — высокорисковая привилегированная операция. После восстановления должны выполняться предусмотренные release validation/health checks.

## AdGuard VPN

AdGuard VPN является отдельным управляемым компонентом. Учётные данные/токены внешних сервисов не должны попадать в Git, frozen payload или публичную диагностику. Доступность install/remove/configure действий определяется текущим release и RBAC.

## Диагностика доступа

Если web-вход не работает, различайте четыре основных класса проблемы:

1. identity не разрешается NSS;
2. PAM отклоняет authentication/account;
3. winbind/Kerberos/SPNEGO недоступен или настроен неверно;
4. authentication успешна, но RBAC не предоставляет нужный модуль/операцию.

Это принципиально отличается от устаревшей модели с отдельным web-паролем Control Center.

См. также `docs/PRODUCT-MANUAL-RU.md`, `docs/AUTO-UPDATES.md`, `docs/DEPLOYMENT-RELIABILITY.md` и `docs/RELEASE-HISTORY.md`.
