# Control Center — каноническое руководство пользователя и администратора

> **Статус:** основное русскоязычное руководство production-линии. Активная версия определяется `../deployment.json`; опубликованные `../releases/<version>` frozen и не редактируются ради документации.

## 1. Назначение продукта

Control Center — единая web-платформа управления серверной инфраструктурой. Production **2.1.0** основан на 2.0 platform baseline и дополнительно нормализует Minecraft Bedrock runtime в один канонический systemd service с сохранением существующего мира/настроек и rollback-контрактом.

Текущая линия включает dashboard/health, PAM/NSS и Samba/winbind identity, RBAC, privileged administration, product/OS updates, backup/restore, Samba AD/shares, Minecraft Bedrock, AdGuard VPN и network/system diagnostics. Roadmap описывает будущее; функция становится production-функцией только после acceptance и публикации через `deployment.json`.

## 2. Источники истины

При расхождении: (1) `deployment.json`; (2) frozen manifest/files активного release; (3) `server-state`/`release.json` конкретного сервера; (4) `RELEASE-HISTORY.md`; (5) это руководство и профильные docs; (6) `ROADMAP.md`; (7) incident/release-specific notes как история.

Не путайте существующий каталог релиза, опубликованный production target и реально установленную на сервере версию.

## 3. Роли, identities и доступ

Control Center не хранит отдельные web-пароли. Локальная Linux identity разрешается NSS и проверяется PAM; доменная — Samba/winbind + NSS/PAM. Kerberos/SPNEGO — дополнительный SSO при корректной настройке. После authentication RBAC определяет Read/Write доступ к модулям/операциям. Критичные действия дополнительно защищены session/CSRF/RBAC и allowlisted privileged path.

## 4. Установка

```bash
curl -fL -o install.sh \
  https://raw.githubusercontent.com/filosoff31/srv-deployment/main/install.sh
chmod +x install.sh
sudo ./install.sh
```

Перед установкой проверьте Linux-среду, сеть/DNS/время, root/sudo и backup при миграции. Installer читает `deployment.json`, валидирует metadata и разворачивает активный self-contained release. Детали — `INSTALL.md`.

## 5. Первый вход

Отдельного bootstrap web-пароля в современной архитектуре нет. Используйте существующую локальную либо доменную учётную запись с необходимыми правами. `admin-bootstrap.txt` — исторический механизм 0.x.

При отказе разделяйте NSS identity, PAM/winbind authentication, web-session и RBAC. Для SSO отдельно проверяются DNS, время, SPN/keytab, reverse proxy и браузер. Успешный PAM login с возвратом на `/login` требует проверки `Set-Cookie`/session cookie, а не автоматической смены пароля.

## 6. Интерфейс и модули

**Dashboard** — health/метрики. **Система** — system status, product/OS maintenance и административные действия. **Права пользователей** — RBAC. **Домен/Samba** — Samba AD. **Сетевые ресурсы** — shares/permissions. **Minecraft Bedrock** — игровой runtime. **AdGuard VPN** — поддерживаемая VPN-интеграция. **Сервисы** — реализованные install/remove/status actions. **Network/diagnostics** — сетевой обзор и диагностика. Наличие будущего модуля в roadmap не означает production-доступность.

## 7. Системное администрирование

```text
UI/API → session + CSRF → RBAC → allowlisted request → root-owned helper/systemd agent → result
```

Web-процесс не должен выполнять произвольный shell от root. Подробности — `SYSTEM-ADMIN.md`.

## 8. Обновления Control Center

`main` — production channel, `deployment.json` — active pointer.

```text
preflight → safety backup → apply → acceptance → healthcheck
                                      ↘ failure → rollback
```

Updater различает check/apply, использует release fingerprint, не применяет release повторно из-за docs-only commit и подавляет бесконечный auto-retry known-failed fingerprint. См. `AUTO-UPDATES.md` и `DEPLOYMENT-RELIABILITY.md`.

## 9. Обновления ОС

OS package maintenance отделён от product update. Major distribution upgrade не выполняется автоматически без отдельного migration plan. Учитывайте backup policy и состояние systemd services/timers.

## 10. Backup и restore

Scheduled backup и `backup_before_update` независимы. Restore — высокорисковая операция с последующими validation/health checks. Domain restore выполняется поддерживаемым Samba workflow, а не простым копированием database files.

## 11. Samba Active Directory

Перед изменениями проверяйте DNS, время, Kerberos, Samba health, NSS/winbind и RBAC. После domain операций проверяйте SID/naming context, DNS/Kerberos и service health. Secrets/keytabs не публикуются.

## 12. Сетевые ресурсы

Для share одновременно важны share name, filesystem path, Samba config, filesystem ownership/ACL и субъекты доступа. Перед reload конфигурация проходит `testparm` или эквивалентную validation. Удаление публикации share и удаление данных должны оставаться различимыми destructive actions.

## 13. Minecraft Bedrock

В **2.1.0** существующий Bedrock runtime нормализован в один канонический `srv-control-minecraft-bedrock.service`; Control Center operations маршрутизируются через него, конфликтующий multi-instance auto-updater отключается, мир и настройки сохраняются. Проверяйте canonical service, process/socket, world/path settings, authoritative update timer/path и acceptance. Product update и Minecraft update — разные процессы.

## 14. Диагностика

Сначала зафиксируйте: опубликованный `deployment.json`, установленный `release.json/server-state`, результат последней deployment transaction.

Web/UI: `srv-control.service`, nginx/reverse proxy, health, application logs, PostgreSQL. Вход: DNS/network → NSS → PAM/winbind → session cookie → RBAC; SPNEGO отдельно при включённом SSO. Update: updater/timer, fingerprint, preflight/apply/acceptance/healthcheck/rollback. Samba: service, DNS/time/Kerberos, `testparm`, NSS/winbind. Minecraft: canonical service/process/socket, world path, updater и acceptance.

Публичная диагностика не содержит passwords, private/session keys, tokens, keytabs или backup contents.

## 15. Безопасность

Least privilege; системный identity source; RBAC authorization; session/CSRF; allowlisted root-owned agents; safety backup; manifest/hash validation; acceptance/rollback; frozen releases; отсутствие secrets в Git/diagnostics.

## 16. Версии и релизы

Используется `MAJOR.MINOR.PATCH`, но фактический смысл версии определяет frozen manifest. Опубликованный release не изменяется задним числом; repair выпускается новой версией. `deployment.json` указывает только на опубликованный target.

## 17. Roadmap

`ROADMAP.md` — план, а не runtime contract. Если запланированный номер версии использован для stabilization/repair, roadmap перенумеровывается; уже опубликованный frozen release не переписывается под старый план.

## 18. Дополнительная документация

Индекс: `README.md`; установка: `INSTALL.md`; системное администрирование: `SYSTEM-ADMIN.md`; обновления: `AUTO-UPDATES.md`; deployment reliability: `DEPLOYMENT-RELIABILITY.md`; история: `RELEASE-HISTORY.md`; будущий scope: `ROADMAP.md`.