# Control Center — руководство пользователя и администратора

> **Статус:** каноническое русскоязычное руководство production-линии. Фактический активный product release всегда определяется `deployment.json`. Опубликованные `releases/<version>` остаются frozen и не редактируются ради документации.

## 1. О продукте

Control Center — web-система централизованного управления серверной инфраструктурой. Текущая production-линия объединяет системный dashboard, PAM/AD authentication, RBAC, product/OS updates, резервное копирование, Samba Active Directory и сетевые ресурсы, AdGuard VPN, Minecraft Bedrock management, network overview/diagnostics и служебные административные операции.

На момент этой редакции `main/deployment.json` публикует **1.3.8**. Это cumulative repair release линии 1.3.x, устраняющий real-server acceptance blockers 1.3.7: доступ web-приложения к release metadata и восстановление privileged system-action watcher. Точная история patch-релизов находится в `RELEASE-HISTORY.md`.

Функции, перечисленные в `ROADMAP.md`, являются будущим scope и не должны считаться реализованными только потому, что присутствуют в roadmap.

## 2. Источники истины

При расхождении документов используйте следующий приоритет:

1. `deployment.json` — опубликованный production target;
2. frozen `releases/<active-version>` — точный код, manifest и release transaction активной версии;
3. актуальный `server-state` — реально установленная версия и runtime-состояние конкретного сервера;
4. `RELEASE-HISTORY.md` — история публикаций, repairs и известных production результатов;
5. это руководство — пользовательская/административная инструкция;
6. `ROADMAP.md` — будущий scope;
7. release-specific scope/incident документы — исторический контекст соответствующего периода.

Не путайте «файл релиза существует в репозитории», «релиз опубликован через `deployment.json`» и «релиз успешно установлен на конкретном сервере».

## 3. Роли, учётные записи и доступ

Control Center не является отдельным каталогом паролей.

Поддерживаемая identity chain:

- локальная Linux identity через NSS/PAM;
- доменная Samba/winbind identity через NSS/PAM;
- Kerberos/SPNEGO SSO в корректно настроенной доменной среде;
- RBAC Control Center после успешной authentication.

RBAC определяет доступ к модулям и операциям. Успешный вход не означает автоматически полный административный доступ. Полная серверная административная роль имеет расширенные полномочия; обычным пользователям выдаются только необходимые Read/Write права.

UI не является единственной границей безопасности: критичные операции также проверяются backend и выполняются через ограниченный privileged path.

## 4. Установка

Чистая production-установка запускается штатным `install.sh` из `main`:

```bash
curl -fL -o install.sh \
  https://raw.githubusercontent.com/filosoff31/srv-deployment/main/install.sh
chmod +x install.sh
sudo ./install.sh
```

Installer должен читать актуальный `deployment.json`, валидировать release metadata и разворачивать активный self-contained payload.

Перед установкой обеспечьте:

- поддерживаемую серверную Linux-среду согласно `INSTALL.md`;
- корректные сеть/DNS/время;
- root/sudo для installation transaction;
- резервную копию существующего сервера при миграции;
- отсутствие секретов в командной истории/публичных логах, где это применимо.

После установки проверяются как минимум web service/health, PostgreSQL, release metadata и необходимые systemd units/managed services.

## 5. Первый вход

В текущей production-архитектуре нет отдельного bootstrap web-пароля и нет обязательного чтения `/var/lib/srv-control/admin-bootstrap.txt`.

Первый вход выполняется существующей локальной Linux либо доменной учётной записью, которой назначены необходимые права.

Для локальной учётной записи должны успешно работать NSS и PAM. Для доменной — Samba/winbind, NSS и PAM. Для SSO дополнительно необходимы корректные Kerberos, DNS, время и настройки браузера/клиента.

Если пользователь проходит authentication, но не видит административный модуль, диагностируйте RBAC, а не пароль.

## 6. Интерфейс и основные модули

### Dashboard

Показывает состояние сервера, health и основные показатели текущей release line. Набор карточек и метрик может меняться между релизами.

### Система

Системный обзор, product updates, обслуживание пакетов ОС, backup/restore и предусмотренные административные действия. Product update и OS package update — независимые механизмы.

### Права пользователей

Каталог доступных локальных/доменных пользователей и групп и управление RBAC Read/Write согласно текущей модели ролей.

### Домен / Samba

Управление состоянием Samba Active Directory, пользователями/группами и предусмотренными domain backup/restore операциями.

### Сетевые ресурсы / Shares

Управление Samba shares, путями, доступом и разрешениями. Изменения должны проходить validation конфигурации перед безопасным reload/apply.

### Minecraft Bedrock

Управление поддерживаемым Bedrock server path, его состоянием, обновлениями и игроками. Линия 1.3.x содержит несколько repairs вокруг совместимости legacy/proven backend и update timers; эксплуатационные действия должны ориентироваться на активный release.

### AdGuard VPN

Управляемая интеграция AdGuard VPN CLI. Внешние credentials/tokens не должны попадать в Git или diagnostics.

### Сервисы

Каталог install/remove/status действий только для тех сервисов, которые реально реализованы активным релизом и разрешены RBAC.

### Network overview / diagnostics

Read-only/управляемые сетевые сведения текущего release. Будущие DHCP/PXE функции из roadmap не следует считать production-функциями до их публикации отдельным релизом.

## 7. Системное администрирование

Web-процесс не выполняет произвольные root-команды. Привилегированные действия проходят цепочку:

```text
UI/API → session/CSRF → RBAC → allowlisted request → root-owned helper/systemd agent → result
```

К таким операциям относятся updates, backup/restore, Samba/domain/shares, Minecraft и другие предусмотренные release действия.

Подробная модель: `SYSTEM-ADMIN.md`.

## 8. Обновления Control Center

`main` — production channel. `deployment.json` задаёт активный product release. Ветки `release/*` предназначены для подготовки/validation и не являются production target сами по себе.

Базовая транзакция:

```text
preflight → safety backup → apply → acceptance → healthcheck
                                      ↘ failure → rollback
```

Updater должен:

- различать check и apply;
- хранить сведения об активной/доступной версии;
- использовать product fingerprint;
- не применять повторно неизменившийся release из-за documentation-only commit;
- блокировать update при обязательном failed pre-update backup;
- предотвращать бесконечный автоматический retry одного и того же known-failed fingerprint;
- сохранять выбранный automatic/manual режим и период после release transaction.

См. `AUTO-UPDATES.md` и `DEPLOYMENT-RELIABILITY.md`.

## 9. Обновления ОС

Обслуживание системных пакетов не равно обновлению Control Center. Автоматический переход на новый major distribution release не должен происходить без отдельного подтверждённого migration plan.

Ручной и автоматический режимы OS maintenance должны учитывать текущие настройки backup-before-update и состояние соответствующих systemd units/timers.

## 10. Резервное копирование и восстановление

Backup schedule и safety backup перед update — разные настройки.

- отключение планового backup не должно автоматически менять `backup_before_update`;
- отключение backup-before-update не должно автоматически менять расписание ежедневных копий;
- restore является высокорисковой операцией;
- после restore должны выполняться предусмотренные validation/health checks.

Backup может включать Control Center state/config/database и управляемые системные области согласно конкретному release.

### Samba domain backup/restore

Domain restore нельзя подменять простым копированием Samba database files. Используйте поддерживаемый release workflow и Samba-инструменты с последующей проверкой SID, naming context, DNS/Kerberos и service health.

## 11. Samba Active Directory

Перед административными изменениями проверяйте:

- DNS;
- синхронизацию времени;
- Kerberos;
- Samba service health;
- разрешение пользователей/групп через NSS/winbind;
- RBAC пользователя Control Center.

При проблемах входа всегда разделяйте authentication и authorization.

## 12. Сетевые ресурсы

Для share важны одновременно:

- Samba share name;
- filesystem path;
- Samba configuration;
- filesystem ownership/ACL/permissions;
- доменные/локальные субъекты доступа.

После изменения конфигурация должна проходить `testparm` или эквивалентную release validation до reload. Наличие записи в UI не является доказательством корректного доступа к filesystem.

Destructive операции должны иметь явное подтверждение; удаление публикации и удаление данных не должны смешиваться в одно неразличимое действие.

## 13. Minecraft Bedrock

Minecraft management включает только возможности активного production release.

Для диагностики проверяйте:

- фактический процесс `bedrock_server`;
- UDP listening port;
- service/helper status;
- authoritative update timer/path текущего release;
- world/path settings;
- player/allow-list permissions;
- результаты monitor/acceptance.

Автоматическое обновление Bedrock и product update Control Center независимы.

Перед переустановкой игрового сервера или заменой мира следует создать отдельную safety copy существующего мира, если задача явно не требует его уничтожения.

## 14. Диагностика и устранение неполадок

Начинайте с фиксации трёх версий/состояний:

1. что опубликовано в `main/deployment.json`;
2. что фактически установлено в `release.json`/server-state;
3. чем завершилась последняя updater/deployment transaction.

### Web/UI

Проверяйте `srv-control.service`, health endpoint, application logs, database connectivity и соответствие release metadata.

### Вход

Проверяйте NSS → PAM → winbind/Kerberos при доменной identity → RBAC.

### Update

Проверяйте updater status, timer/service state, fingerprint state, preflight/apply/acceptance/healthcheck и rollback result.

### Samba

Проверяйте service state, DNS, time/Kerberos, `testparm`, domain state и NSS/winbind.

### Minecraft

Проверяйте process/socket, helper/service/timer, world path, updater и acceptance активного release.

Diagnostics/public server-state не должны содержать passwords, private keys, session secrets, tokens или содержимое backup archives.

## 15. Безопасность

Основные принципы:

- least privilege;
- PAM/AD как источник identity;
- RBAC как authorization;
- session/CSRF protection;
- root-owned privileged agents с allowlist действий;
- safety backup перед рискованными изменениями;
- release manifest/hash validation;
- acceptance и rollback;
- отсутствие секретов в Git и публичной диагностике;
- frozen published releases.

## 16. Версии и релизы

Версия имеет вид `MAJOR.MINOR.PATCH`.

- `MAJOR` — несовместимая/крупная архитектурная линия;
- `MINOR` — значимое функциональное расширение;
- `PATCH` — совместимое исправление/repair в текущей линии.

Published release directory frozen. Исправление выпускается новой версией.

Для 1.3.x это особенно важно: реальные deployment/acceptance дефекты 1.3.2–1.3.7 исправлялись последовательными patch-релизами; активный production pointer сейчас находится на 1.3.8.

## 17. Roadmap и будущие функции

`ROADMAP.md` описывает будущую разработку, включая DHCP/PXE и последующие operations/infrastructure возможности. Roadmap не гарантирует наличие функции в production.

Функция становится пользовательской production-возможностью только после:

```text
implementation → tests/regression → release acceptance → publication in deployment.json → documentation update
```

## 18. Редакции и lifecycle

Редакции и licensing/lifecycle architecture описываются в `PRODUCT-EDITIONS.md`. До официального коммерческого запуска нельзя выдумывать задним числом даты lifecycle или считать планируемое ограничение уже действующим, если оно не реализовано в опубликованном release.

## 19. Обновление этой документации

Это руководство обновляется при каждом новом product release или пользовательски значимом изменении архитектуры. Обновление документации выполняется вне frozen release payload и не должно менять уже опубликованные `releases/<version>`.
