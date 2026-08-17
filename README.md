# SRV Control Center

`filosoff31/srv-deployment` — production-репозиторий SRV Control Center.

## Стабильный baseline 1.0.0

Начиная с 1.0.0 ранее накопленные инкрементальные сборки 0.x объединены в самодостаточный baseline. Активный product-релиз определяется `deployment.json`, а каждый каталог `releases/<version>` содержит полный payload, системные helper/unit-файлы и собственные preflight/apply/acceptance/rollback.

В 1.0.0 входят уже доведённые до production возможности: FastAPI/PostgreSQL Control Center, dashboard/health, системный обзор, сетевой overview/diagnostics и dry-run WAN/LAN planner, GitHub deployment metadata, защищённые системные действия, обновления ОС, AdGuard VPN CLI, graceful rotation Uvicorn workers, clean installer и GitHub updater.

## Release 1.1.0 — переработка администрирования

1.1.0 содержит только изменения, утверждённые владельцем проекта в `docs/RELEASE-1.1.0-SCOPE.md`:

- обязательная авторизация через локальные Linux/PAM или доменные учётные записи без собственной базы пользователей/паролей Control Center;
- Kerberos/SPNEGO SSO для доменной среды;
- полный доступ root и серверных администраторов;
- групповой RBAC Read/Write для «Домен / Samba», PXE Server, Minecraft, Docker, «Сеть» и «Торренты»;
- отдельный раздел «Права пользователей» с каталогом локальных/доменных пользователей и групп;
- настройки GitHub source/mode/period, отдельные операции «Проверить обновления» и «Обновить»;
- ручной/автоматический режим обновления ОС с периодом 1–24 часа;
- резервные копии БД, state/config и управляемых системных параметров с расписанием, backup-before-update, скачиванием, удалением и восстановлением;
- «Загрузки» переименованы в «Торренты»;
- отдельные пункты «AdGuard VPN» и «Сервисы»;
- каталог сервисов содержит AdGuard VPN и PXE Server с фактическим состоянием и install/remove действиями согласно RBAC;
- компактная кнопка перезагрузки находится рядом со статусом «Данные актуальны»;
- временные UI-заглушки для неготовых функций не отображаются.

## Структура релизов

```text
deployment.json
releases/
├── 1.0.0/
│   ├── manifest.json
│   ├── preflight.sh
│   ├── apply.sh
│   ├── acceptance.sh
│   ├── rollback.sh
│   ├── payload/
│   └── system/
└── 1.1.0/
    ├── manifest.json
    ├── preflight.sh
    ├── apply.sh
    ├── acceptance.sh
    ├── rollback.sh
    ├── payload/
    └── system/
```

`main` является единственным production update channel. `server-state` публикует фактическое состояние SRV. Ветки `release/*` используются только для подготовки и проверки нового product-релиза и production updater их не читает.

## Чистая установка

```bash
curl -fL -o install.sh \
  https://raw.githubusercontent.com/filosoff31/srv-deployment/main/install.sh
chmod +x install.sh
sudo ./install.sh
```

`installer/install.sh` читает текущий `deployment.json` и устанавливает полный payload активного релиза. Для 1.1.0 clean install дополнительно устанавливает PAM/NSS authentication, Kerberos/SPNEGO integration, RBAC migration, backup worker и системные update timers.

## GitHub updater

Настройка выполняется через:

```text
/usr/local/sbin/srvcc-configure-auto-updates
```

Updater хранит отдельно последний просмотренный commit, последний успешно применённый product commit и fingerprint активного релиза. Поэтому документационный commit не приводит к повторному apply неизменившегося product release.

В 1.1.0 операции разделены:

```bash
sudo /usr/local/sbin/srvcc-github-agent check
sudo /usr/local/sbin/srvcc-github-agent apply
```

`check` только обновляет сведения о доступном product-релизе. `apply` выполняет product deployment; если включено резервное копирование перед обновлением, отсутствие успешного backup блокирует apply.

Полное описание: `docs/AUTO-UPDATES.md`.

## Безопасность deployment

Product release проходит:

```text
preflight → backup → apply → acceptance → healthcheck
```

При ошибке orchestrator выполняет rollback. Кодовые обновления используют graceful worker rotation, когда это совместимо. Секреты, пользовательские пароли и содержимое резервных копий не публикуются в Git.

## Документация

- `docs/INSTALL.md` — установка на чистую машину;
- `docs/AUTO-UPDATES.md` — GitHub updater;
- `docs/DEPLOYMENT-RELIABILITY.md` — надёжность deployment-канала;
- `docs/SYSTEM-ADMIN.md` — системные административные функции;
- `docs/RELEASE-1.1.0-SCOPE.md` — обязательный scope и acceptance 1.1.0.
