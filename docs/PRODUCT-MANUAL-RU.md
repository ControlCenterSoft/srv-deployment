# Control Center — руководство пользователя и администратора

> **Статус:** каноническое русскоязычное руководство production-линии. Активный product release всегда определяется `deployment.json`. Опубликованные `releases/<version>` являются frozen и не редактируются ради документации.

## 1. О продукте

Control Center — web-система централизованного управления серверной инфраструктурой. Текущий production target — **Control Center 2.0.0**, опубликованный через `main/deployment.json` и frozen-каталог `releases/2.0.0`.

2.0.0 является новым major baseline и включает переработанный интерфейс, новый update controller, bulk backup management, исправленную политику backup-before-update, health-first восстановление Minecraft Bedrock и перенесённое DHCP/PXE управление. Точный состав определяется manifest и frozen payload 2.0.0.

## 2. Источники истины

При расхождении документов используйте следующий приоритет:

1. `deployment.json` — опубликованный production target;
2. frozen `releases/<active-version>` — точный код, manifest и release transaction;
3. актуальный `server-state` — реально установленная версия и runtime-состояние конкретного сервера;
4. `RELEASE-HISTORY.md` — история публикаций и repairs;
5. это руководство — текущая пользовательская/административная инструкция;
6. `ROADMAP.md` — будущий scope;
7. release-specific scope/incident документы — исторический контекст.

Не путайте существование release-файлов, публикацию release через `deployment.json` и успешную установку на конкретном сервере.

## 3. Роли, учётные записи и доступ

Control Center не является отдельным каталогом паролей.

Поддерживаемая identity chain:

- локальная Linux identity через NSS/PAM;
- доменная Samba/winbind identity через NSS/PAM;
- Kerberos/SPNEGO SSO в корректно настроенной доменной среде;
- RBAC Control Center после успешной authentication.

Authentication отвечает на вопрос «кто пользователь», RBAC — «что ему разрешено». Успешный login не означает автоматически полный административный доступ. Обычным пользователям выдаются только необходимые Read/Write права, а full-admin/server-administrator права должны оставаться ограниченными.

## 4. Установка

Чистая production-установка запускается штатным `install.sh` из `main`:

```bash
curl -fL -o install.sh \
  https://raw.githubusercontent.com/filosoff31/srv-deployment/main/install.sh
chmod +x install.sh
sudo ./install.sh
```

Installer читает текущий `deployment.json`, проверяет release metadata и разворачивает активный self-contained payload.

Перед установкой обеспечьте корректные сеть/DNS/время, root/sudo, резервную копию существующей системы при миграции и отсутствие секретов в публичных логах/репозитории.

## 5. Первый вход

В production 2.0.0 **нет отдельного bootstrap web-пароля** и не требуется файл `/var/lib/srv-control/admin-bootstrap.txt`.

Первый вход выполняется существующей локальной Linux либо доменной учётной записью, которой назначены необходимые права. Для локального пользователя должны работать NSS и PAM. Для доменного — Samba/winbind, NSS и PAM. Для SSO дополнительно требуются корректные Kerberos, DNS, время и настройки клиента/браузера.

Если authentication успешна, но модуль недоступен, проверяйте RBAC, а не пароль.

## 6. Интерфейс и модули

### Dashboard

Показывает health, состояние сервера и основные показатели. Интерфейс 2.0.0 использует новую визуальную систему и унифицированную навигацию.

### Система

Содержит product updates, OS maintenance, backup/restore и системные административные действия. Product update и OS update — разные механизмы.

В блоке product update используются отдельные состояния:

- **Последняя проверка обновления**;
- diagnostic timestamp последней попытки apply, если он нужен backend;
- **Последнее успешное обновление**.

### Пользователи и права

Отображаются доступные локальные/доменные identities и RBAC Read/Write. Полный доступ определяется серверной admin policy, а не только успешным входом.

### Samba / Домен

Управление Samba Active Directory, пользователями, группами и поддерживаемыми domain backup/restore операциями.

### Сетевые ресурсы / Shares

Управление SMB shares, путями и правами. После изменения конфигурация должна проходить validation до безопасного reload/apply.

### DHCP

В 2.0.0 перенесено управление DHCP из ранее подготовленного функционального scope. Используйте только те операции и параметры, которые реально доступны в active frozen payload. Изменения сети требуют повышенной осторожности и последующей проверки lease/service/network state.

### PXE

2.0.0 содержит PXE management и публичный путь выдачи PXE media. PXE-клиент должен иметь разрешённый профиль согласно реализованному workflow; отсутствие development-функции в UI нельзя компенсировать неподдерживаемыми ручными изменениями production state.

### Minecraft Bedrock

2.0.0 сохраняет proven single-server management path и совместимый multi-instance API, но health/recovery логика перестроена. Восстановление выполняется health-first: здоровый сервер не переустанавливается. Destructive recovery допускается только после safety backup существующего состояния.

### AdGuard VPN

Управляемая интеграция AdGuard VPN CLI. Credentials/tokens не должны попадать в Git или публичную диагностику.

### Network overview / diagnostics

Сетевые сведения, diagnostics и поддерживаемые действия текущего release. Roadmap-функции не считаются production до отдельной публикации.

## 7. Системное администрирование

Web-процесс не должен выполнять произвольные root-команды. Привилегированные действия проходят цепочку:

```text
UI/API → session/CSRF → RBAC → allowlisted request → root-owned helper/systemd agent → result
```

К таким операциям относятся updates, backup/restore, Samba/domain/shares, DHCP/PXE, Minecraft и другие поддерживаемые release actions.

Подробности: `SYSTEM-ADMIN.md`.

## 8. Обновления Control Center

`main` — production channel. `deployment.json` задаёт активный product release. Ветки `release/*` не являются production target сами по себе.

2.0.0 использует переработанный update controller. Основные принципы:

- отдельные `check` и `apply`;
- product/release fingerprint вместо решения только по commit SHA;
- suppression автоматического повторения одного known-failed fingerprint;
- безопасный manual retry;
- восстановление update runtime/configuration после apply;
- timer не должен оставаться выключенным после неуспешной транзакции;
- хранение timestamps последней проверки, попытки apply и успешного update;
- documentation-only commit не должен запускать повторный product apply.

Типовая транзакция:

```text
preflight → policy-controlled safety backup → apply → acceptance → healthcheck
                                                   ↘ failure → rollback
```

См. `AUTO-UPDATES.md` и `DEPLOYMENT-RELIABILITY.md`.

## 9. Обновления ОС

OS package maintenance независимо от Control Center product update. Автоматический переход на новый major distribution release не должен происходить без отдельного migration plan.

Ручной/автоматический OS maintenance учитывает текущую `backup_before_update` policy и состояние соответствующих systemd units/timers.

## 10. Резервное копирование и восстановление

Backup schedule и backup-before-update — независимые настройки.

В 2.0.0:

- отключение scheduled backup не должно менять `backup_before_update`;
- отключение `backup_before_update` должно реально запрещать пользовательский pre-update backup и для product update, и для OS update;
- внутренний rollback snapshot release transaction не считается пользовательским backup;
- доступно массовое удаление backup с явным подтверждением;
- restore остаётся высокорисковой операцией и требует validation/health checks.

### Samba domain backup/restore

Domain restore нельзя заменять простым копированием Samba database files. Используйте поддерживаемый workflow с последующей проверкой SID, naming context, DNS/Kerberos и service health.

## 11. Samba Active Directory

Перед изменениями проверяйте DNS, время, Kerberos, Samba service health, NSS/winbind и RBAC пользователя Control Center.

При проблемах входа разделяйте authentication и authorization.

## 12. Сетевые ресурсы

Для share одновременно важны Samba share name, filesystem path, Samba configuration, filesystem ownership/ACL/permissions и субъекты доступа.

После изменения конфигурация должна проходить `testparm` или эквивалентную release validation. Наличие записи в UI не доказывает корректный filesystem access.

Удаление публикации ресурса и удаление данных должны оставаться различимыми destructive действиями.

## 13. DHCP и PXE

DHCP/PXE в production 2.0.0 являются carried-forward модулями. Для безопасной эксплуатации:

- перед изменением DHCP фиксируйте действующий interface/subnet/range/options;
- после apply проверяйте service state, leases и доступность сети;
- PXE media публикуются только через предусмотренный path;
- PXE installation workflow должен ограничиваться разрешёнными client profiles;
- MAC является основным идентификатором PXE client, если это предусмотрено активной конфигурацией;
- DHCP/PXE operations должны проходить RBAC и privileged helper boundary.

Если конкретная функция описана только в `ROADMAP.md`, но отсутствует в active payload/API/UI, она ещё не считается production-функцией.

## 14. Minecraft Bedrock

Для диагностики проверяйте:

- процесс `bedrock_server`;
- UDP listening port;
- service/helper status;
- authoritative update timer/path;
- world/path settings;
- player/allow-list permissions;
- monitor/acceptance results.

Health-first recovery не должен разрушать исправный runtime. Если обычный repair/update/restart не восстанавливает сервис, destructive recovery с новым recovery world допустим только после успешного safety backup старого состояния.

## 15. Диагностика и troubleshooting

Начинайте с трёх состояний:

1. что опубликовано в `main/deployment.json`;
2. что установлено в `release.json`/server-state;
3. чем завершилась последняя updater/deployment transaction.

### Web/UI

Проверяйте `srv-control.service`, health endpoint, application logs, database connectivity и release metadata.

### Вход

Проверяйте NSS → PAM → winbind/Kerberos при доменной identity → RBAC.

### Update

Проверяйте updater status, timer/service state, fingerprint/blocked-release state, preflight/apply/acceptance/healthcheck и rollback.

### Backup

Проверяйте `backup-config`, timer state и отдельно значение `backup_before_update`.

### Samba

Проверяйте service state, DNS, time/Kerberos, `testparm`, domain state и NSS/winbind.

### DHCP/PXE

Проверяйте service state, listen sockets, interface binding, leases/media paths и клиентский профиль.

### Minecraft

Проверяйте process/socket, helper/service/timer, world path, updater и acceptance.

Diagnostics/public server-state не должны содержать passwords, private keys, session secrets, tokens или содержимое backup archives.

## 16. Безопасность

Основные принципы:

- least privilege;
- PAM/AD как источник identity;
- RBAC как authorization;
- session/CSRF protection;
- root-owned privileged agents с allowlist действий;
- policy-controlled safety backup перед рискованными изменениями;
- release manifest/hash validation;
- acceptance и rollback;
- отсутствие секретов в Git/публичной диагностике;
- frozen published releases.

## 17. Версии и релизы

Версия имеет вид `MAJOR.MINOR.PATCH`.

- `MAJOR` — крупная архитектурная линия;
- `MINOR` — значимое функциональное расширение;
- `PATCH` — совместимый repair.

Текущий major baseline — **2.0.0**. Линия 1.3.x остаётся исторической release lineage и источником причин, которые привели к перестройке updater/backup/Minecraft mechanisms в 2.0.0.

Published release directory frozen. Исправление 2.0.0 должно выпускаться новой версией, а не модификацией `releases/2.0.0`.

## 18. Roadmap и product editions

`ROADMAP.md` описывает только будущий scope после текущего production release. Если старый roadmap перечислял требование как часть 2.0.0, но оно не подтверждается active manifest/frozen payload, оно должно быть перенесено в будущий 2.x scope, а не документироваться как реализованное.

`PRODUCT-EDITIONS.md` описывает editions/licensing architecture. Licensing stage считается реализованным только после появления подтверждаемого production implementation и соответствующей release history.

## 19. Обновление этого руководства

При каждом новом release необходимо сверить `deployment.json`, manifest/frozen payload, обновить `RELEASE-HISTORY.md`, это руководство и профильные инструкции. Документация не должна опережать production implementation и не должна изменять frozen release payload.

Связанные документы: `README.md`, `INSTALL.md`, `SYSTEM-ADMIN.md`, `AUTO-UPDATES.md`, `DEPLOYMENT-RELIABILITY.md`, `ROADMAP.md`, `PRODUCT-EDITIONS.md`, `RELEASE-HISTORY.md`.
