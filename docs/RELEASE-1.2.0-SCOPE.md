# SRV Control Center 1.2.0 — Dashboard, RBAC and Minecraft Control

1.2.0 продолжает 1.1.0 и возобновляет ранее согласованный roadmap управления домашним сервером.

## Обязательный состав релиза

1. Dashboard:
   - на широком экране четыре карточки в одну строку: CPU, RAM, Сеть, Сервер;
   - на узком экране карточки располагаются вертикально;
   - CPU содержит Top 3 процессов по текущей загрузке CPU;
   - RAM содержит Top 3 процессов по RSS/доле оперативной памяти.
2. RBAC:
   - сохранить персональные и групповые Read/Write назначения;
   - `Write` остаётся правом изменения конкретного выбранного модуля;
   - добавить отдельную глобальную роль `Полный администратор`;
   - полный администратор получает все модульные Write-права и доступ к admin-only API/UI;
   - acceptance обязан отдельно проверять прямое пользовательское Write и Full Administrator.
3. AdGuard VPN:
   - настройки находятся в собственном пункте меню;
   - отображаются текущие состояние, версия, режим, SOCKS адрес/порт;
   - SOCKS address/port редактируются из UI через root-owned system agent;
   - connect/disconnect/update/status остаются управляемыми действиями.
4. Minecraft Bedrock:
   - отдельный пункт `Minecraft` в главном меню;
   - обнаружение существующего systemd unit и `server.properties`;
   - состояние, автозапуск, unit, путь конфигурации и текущий мир;
   - Start / Stop / Restart;
   - редактирование server-name, gamemode, difficulty, max players, ports, view/tick distance, idle timeout, level name, online mode, allow list, cheats;
   - запись выполняется привилегированным агентом атомарно с резервной копией файла;
   - активный Minecraft server перезапускается после изменения server.properties.
5. Deployment:
   - отдельная ветка `release/1.2.0` до завершения проверок;
   - миграция PostgreSQL до `12f0a1200001`;
   - static/syntax/JS checks, migration validation, RBAC tests, collectors tests;
   - production main не переключается до успешного preflight/acceptance.

## Возобновлённый roadmap

После базового 1.2.0 работы продолжаются в ранее согласованном порядке:

1. Minecraft Control — текущий этап: settings/service control; далее players/allowlist, worlds/backups/update/live console.
2. PXE Control — discovery/status, затем ISO library/upload и iPXE workflows.
3. Samba/AD и Storage — пользователи/группы/профили, шары и права, диски/хранилище.
4. Docker / MikoPBX.
5. Deluge / TorrServer / Cockpit.
6. Расширенные журналы, системная диагностика, обновления и обслуживание.

Функция попадает в production UI только после реализации backend + permissions + validation; placeholder-элементы не допускаются.
