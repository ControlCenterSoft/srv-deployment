# Control Center — каноническое руководство пользователя и администратора

> **Статус:** основное русскоязычное руководство production-линии. Активная версия определяется `../deployment.json`; опубликованные `../releases/<version>` frozen и не редактируются ради документации.

## 1. Назначение продукта

Control Center — единая web-платформа управления серверной инфраструктурой. Текущий production target — **2.1.2**. Линия 2.1.x стабилизирует Minecraft Bedrock runtime: один канонический systemd service, сохранение существующего мира и настроек, подтверждённые состояния управления и live-status в web-интерфейсе.

Текущая линия включает dashboard/health, PAM/NSS и Samba/winbind identity, RBAC, privileged administration, product/OS updates, backup/restore, Samba AD/shares, Minecraft Bedrock, AdGuard VPN и network/system diagnostics. Roadmap описывает будущее; функция становится production-функцией только после acceptance и публикации через `deployment.json`.

## 2. Источники истины

При расхождении: (1) `deployment.json`; (2) frozen manifest/files активного release; (3) `server-state`/`release.json` конкретного сервера; (4) `RELEASE-HISTORY.md`; (5) это руководство и профильные docs; (6) `ROADMAP.md`; (7) incident/release-specific notes как история.

Не путайте существующий каталог релиза, опубликованный production target и реально установленную на сервере версию.

## 3. Роли, identities и доступ

Control Center не хранит отдельные web-пароли. Локальная Linux identity разрешается NSS и проверяется PAM; доменная — Samba/winbind + NSS/PAM. Kerberos/SPNEGO — дополнительный SSO при корректной настройке. После authentication RBAC определяет Read/Write доступ к модулям и операциям. Критичные действия дополнительно защищены session/CSRF/RBAC и allowlisted privileged path.

## 4. Установка

```bash
curl -fL -o install.sh https://raw.githubusercontent.com/filosoff31/srv-deployment/main/install.sh
chmod +x install.sh
sudo ./install.sh
```

Перед установкой проверьте Linux-среду, сеть/DNS/время, root/sudo и backup при миграции. Installer читает `deployment.json`, валидирует metadata и разворачивает активный self-contained release. Детали — `INSTALL.md`.

## 5. Первый вход

Отдельного bootstrap web-пароля в современной архитектуре нет. Используйте существующую локальную либо доменную учётную запись с необходимыми правами. `admin-bootstrap.txt` — исторический механизм 0.x.

Цепочка интерактивного входа: `NSS identity → PAM/account policy → web-session → RBAC`. Для доменной identity в NSS/PAM участвует Samba/winbind. Для SSO отдельно проверяются DNS, время, SPN/keytab, reverse proxy и браузер. Успешный PAM login с возвратом на `/login` требует проверки session cookie, а не автоматической смены пароля.

## 6. Интерфейс и модули

**Обзор/Dashboard** — health и сводное состояние. **Сеть** — реализованные сетевые настройки и диагностика. **DHCP**, **PXE Windows**, **PXE Linux** — только фактически реализованные contracts активного release. **Домен и доступ** — Samba AD/identity. **Сетевые ресурсы** — shares/permissions. **Minecraft** — Bedrock runtime. **AdGuard VPN** — VPN-интеграция. **Сервисы** — lifecycle поддерживаемых сервисов. **Пользователи** — identity/RBAC workflows. **Система** — system status, product/OS maintenance и административные действия.

Наличие пункта в roadmap или навигационном каркасе само по себе не доказывает production-ready функциональность: ориентируйтесь на active release acceptance.

## 7. Системное администрирование

`UI/API → session + CSRF → RBAC → allowlisted request → root-owned helper/systemd agent → result`.

Web-процесс не должен выполнять произвольные root-команды. Подробности — `SYSTEM-ADMIN.md`.

## 8. Обновления Control Center

`main` — production channel, `deployment.json` — active pointer. Deployment transaction: `preflight → safety backup → apply → acceptance → healthcheck`, при ошибке — rollback.

Updater различает check/apply, использует release fingerprint, не применяет release повторно из-за docs-only commit и подавляет бесконечный auto-retry known-failed fingerprint. См. `AUTO-UPDATES.md` и `DEPLOYMENT-RELIABILITY.md`.

## 9. Обновления ОС

OS package maintenance отделён от product update. Major distribution upgrade не выполняется автоматически без отдельного migration plan. Учитывайте backup policy и состояние systemd services/timers.

## 10. Backup и restore

Scheduled backup и `backup_before_update` независимы. Restore — высокорисковая privileged operation с последующими validation/health checks. Domain restore выполняется поддерживаемым Samba workflow, а не простым копированием database files.

## 11. Samba Active Directory

Перед изменениями проверяйте DNS, время, Kerberos, Samba health, NSS/winbind и RBAC. После domain operations проверяйте SID/naming context, DNS/Kerberos и service health. Secrets/keytabs не публикуются. Для доменного SSO особенно критична синхронизация времени.

## 12. Сетевые ресурсы

Для share одновременно важны share name, filesystem path, Samba config, filesystem ownership/ACL и субъекты доступа. Перед reload конфигурация проходит `testparm` или эквивалентную validation. Удаление публикации share и удаление данных должны оставаться различимыми destructive actions.

## 13. Minecraft Bedrock

В 2.1.x Bedrock runtime нормализован в один канонический `srv-control-minecraft-bedrock.service`; Control Center operations маршрутизируются через него, конфликтующий multi-instance updater отключён, мир и настройки сохраняются.

**2.1.2** дополнительно использует канонический systemd `WorkingDirectory` для определения runtime/status даже когда сервер остановлен, возвращает подтверждённые ONLINE/OFFLINE результаты команд и обновляет live-status в интерфейсе примерно каждые 5 секунд. Product update и Minecraft update — разные процессы.

## 14. Диагностика

Сначала зафиксируйте опубликованный `deployment.json`, установленный `release.json/server-state` и результат последней deployment transaction.

Web/UI: `srv-control.service`, nginx/reverse proxy, health, application logs, PostgreSQL. Вход: DNS/network → NSS → PAM/winbind → session cookie → RBAC; SPNEGO отдельно при включённом SSO. Update: updater/timer, fingerprint, preflight/apply/acceptance/healthcheck/rollback. Samba: service, DNS/time/Kerberos, `testparm`, NSS/winbind. Minecraft: canonical service/process/socket, `WorkingDirectory`, world path, updater и acceptance.

Если общий health зелёный, но отдельная страница возвращает 500, проверяйте application traceback, наличие и права template/static файлов и доступ к ним от имени service user: общий health не доказывает успешный render каждого модуля.

Публичная диагностика не содержит passwords, private/session keys, tokens, keytabs или backup contents.

## 15. Безопасность

Least privilege; системный identity source; RBAC authorization; session/CSRF; allowlisted root-owned agents; safety backup; manifest/hash validation; acceptance/rollback; frozen releases; отсутствие secrets в Git/diagnostics.

## 16. Версии и релизы

Используется `MAJOR.MINOR.PATCH`, но фактический смысл версии определяет frozen manifest. Опубликованный release не изменяется задним числом; repair выпускается новой версией. `deployment.json` указывает только на опубликованный target. Documentation-only исправления не должны менять frozen payload или повторно применять ту же product version.

## 17. Roadmap

`ROADMAP.md` — план, а не runtime contract. Если запланированный номер версии использован для stabilization/repair, roadmap перенумеровывается; уже опубликованный frozen release не переписывается под старый план.

## 18. Дополнительная документация

Индекс: `README.md`; установка: `INSTALL.md`; системное администрирование: `SYSTEM-ADMIN.md`; обновления: `AUTO-UPDATES.md`; deployment reliability: `DEPLOYMENT-RELIABILITY.md`; история: `RELEASE-HISTORY.md`; будущий scope: `ROADMAP.md`.
