# Control Center — руководство пользователя и администратора

> **Статус:** каноническое русскоязычное руководство, развиваемое вместе с production-линией. Фактическая активная версия всегда определяется `deployment.json`; исторические release-файлы остаются frozen.

## 1. О продукте

Control Center — web-система централизованного управления серверной инфраструктурой. Текущая production-линия объединяет системный dashboard, аутентификацию PAM/AD, RBAC, обновления и резервное копирование, Samba Active Directory и сетевые ресурсы, AdGuard VPN и Minecraft Bedrock management. Дальнейшее развитие фиксируется в `ROADMAP.md`.

На момент создания этой редакции `main/deployment.json` указывает production release **1.3.3**. История также фиксирует известный real-server preflight defect 1.3.3; исправление готовится отдельным 1.3.4, без изменения frozen 1.3.3.

## 2. Роли, учётные записи и доступ

Control Center не является отдельным каталогом паролей. Пользователь проходит системную аутентификацию через Linux/PAM либо доменную Samba/winbind PAM/NSS; в доменной среде возможен Kerberos/SPNEGO SSO. После аутентификации применяется RBAC Control Center.

Права назначаются на модули и операции и могут зависеть от локальных или доменных групп. Полная серверная административная роль имеет полный доступ; обычному пользователю выдаются только необходимые Read/Write полномочия. UI не является единственной границей безопасности: критические операции дополнительно контролируются backend и privileged helpers.

## 3. Установка

Чистая установка выполняется штатным `install.sh` из production-ветки `main`. Installer читает `deployment.json`, проверяет release metadata и разворачивает self-contained payload активного релиза. Перед установкой следует обеспечить поддерживаемую Ubuntu/Debian-среду, сеть, DNS и права root/sudo.

После установки необходимо проверить `srv-control.service`, web health endpoint, PostgreSQL и состояние компонентов, необходимых выбранным модулям. Подробности: `INSTALL.md`.

## 4. Первый вход

В текущей архитектуре нет отдельного bootstrap-пароля web-интерфейса. Первый вход выполняется существующей локальной Linux или доменной учётной записью с назначенными правами. Для доменного входа должны корректно работать Samba/winbind, NSS и PAM; для SSO дополнительно требуется рабочая Kerberos/SPNEGO конфигурация клиента.

Если пользователь успешно проходит PAM, но не видит административный модуль, проверяется RBAC, а не пароль.

## 5. Интерфейс и модули

### Dashboard
Показывает состояние сервера и ключевые показатели/health. Состав карточек зависит от release line.

### Система
Системный обзор, предусмотренные административные операции, состояние обновлений и связанные настройки. Product update и OS package update являются разными механизмами.

### Права пользователей
Каталог локальных/доменных пользователей и групп и назначение RBAC Read/Write.

### Домен / Samba
Управление Samba AD, состоянием доменных компонентов и предусмотренными backup/restore операциями.

### Общий / сетевой доступ
Управление Samba shares, путями и разрешениями. Изменения должны проходить validation конфигурации до применения.

### Minecraft
Управление Minecraft Bedrock, включая предусмотренные release-функции сервера, обновления и игроков. В линии 1.3.x этот модуль проходил несколько compatibility/repair patch-релизов; перед эксплуатационным изменением учитывайте текущий release status.

### AdGuard VPN и Сервисы
Управление поддерживаемыми компонентами согласно RBAC и возможностям установленного релиза.

## 6. Системное администрирование

Web-процесс не должен выполнять произвольные root-команды. Привилегированные действия проходят через специализированные helpers/systemd agents с ограниченным контрактом. Для подробной модели PAM/NSS/RBAC и privileged actions см. `SYSTEM-ADMIN.md`.

## 7. Обновления Control Center

`main` — production update channel. `deployment.json` задаёт активный product release. Ветки `release/*` используются для подготовки и проверки и не должны восприниматься production updater как опубликованный релиз.

Транзакция обновления: `preflight → backup → apply → acceptance → healthcheck`. Ошибка приводит к rollback по правилам релиза. Published release directories считаются frozen; исправление опубликованной версии выполняется новым patch-релизом.

Updater различает проверку наличия обновления и его применение. Документационные commits без изменения product fingerprint не должны инициировать повторный deployment неизменившегося релиза. См. `AUTO-UPDATES.md` и `DEPLOYMENT-RELIABILITY.md`.

## 8. Резервные копии и восстановление

Backup-модель охватывает данные Control Center и управляемые state/config области согласно релизу. Перед product update может быть обязательным успешный backup. Restore является привилегированной операцией и должен сопровождаться post-restore validation/health checks.

Samba domain backup/restore имеет отдельные требования: используйте поддерживаемые Samba-инструменты и не подменяйте domain restore простым копированием файлов базы.

## 9. Samba Active Directory

Перед изменениями домена проверяются DNS, время/Kerberos, состояние Samba и разрешение пользователей/групп через NSS. Доменные административные операции должны выполняться только пользователями с соответствующим RBAC и через предусмотренный privileged path.

При проблемах входа разделяйте authentication (PAM/winbind/Kerberos) и authorization (RBAC).

## 10. Сетевые ресурсы

Для share важны имя ресурса, filesystem path, Samba configuration и ACL/permissions. После изменения конфигурация должна проходить `testparm`/эквивалентную validation до безопасного reload. Нельзя считать наличие пункта в UI доказательством корректного filesystem доступа.

## 11. Minecraft Bedrock

Minecraft management включает только функции, реально присутствующие в текущем релизе. Линия 1.3.x содержит исторические исправления backend/update path; `RELEASE-HISTORY.md` является источником статуса конкретных patch-релизов. Автоматическое обновление игрового сервера и product update Control Center — независимые процессы.

## 12. Диагностика и устранение неполадок

Начинайте с определения трёх состояний: версия, опубликованная в `main/deployment.json`; версия, фактически установленная на сервере; последний результат updater/deployment. Они могут различаться после failed preflight/acceptance и rollback.

Для web-проблем проверяйте service health и журнал приложения; для входа — NSS/PAM/winbind/Kerberos и затем RBAC; для update — updater status, preflight/apply/acceptance result и rollback; для Samba — service/DNS/Kerberos/testparm; для Minecraft — соответствующие helper/service/timer и acceptance текущего релиза.

Диагностические публикации не должны содержать пароли, private keys, session secrets или другие секреты.

## 13. Безопасность

Основные принципы: least privilege; PAM/AD как источник identity; RBAC как authorization; CSRF/session protection для web; root-only privileged agents; allowlisted actions; backup before рискованных изменений; release hash/metadata validation; rollback; отсутствие секретов в Git и публичной диагностике.

## 14. Версии и релизы

Версия имеет вид `MAJOR.MINOR.PATCH`. Published release directory frozen. `deployment.json` — источник текущего production target, `RELEASE-HISTORY.md` — исторический статус, `ROADMAP.md` — будущий scope.

Не следует путать «релиз присутствует в репозитории», «релиз опубликован в main» и «релиз подтверждён на реальном production-сервере». Для 1.3.x это различие существенно: 1.3.3 опубликован в `main`, но real-server deployment выявил preflight failure; repair вынесен в 1.3.4.

## 15. Редакции и жизненный цикл

Архитектура предусматривает Control Center Home и Professional на общем Core. Коммерческая модель и release-based lifecycle описаны в `PRODUCT-EDITIONS.md`. До официального коммерческого запуска даты Professional lifecycle не должны выдумываться задним числом.

## 16. Источники истины

- `deployment.json` — активный production target;
- `RELEASE-HISTORY.md` — опубликованная история и известные production результаты;
- `ROADMAP.md` — согласованный будущий roadmap;
- `PRODUCT-EDITIONS.md` — редакции, лицензирование и lifecycle;
- frozen `releases/<version>` — точный код/metadata конкретного опубликованного релиза;
- `server-state` — фактическое состояние реального сервера, когда опубликована свежая диагностика.

Это руководство должно обновляться документационным commit/PR при изменении пользовательской архитектуры или опубликованного поведения, не переписывая frozen release payload.