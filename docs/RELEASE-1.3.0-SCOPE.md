# SRV Control Center 1.3.0 — Samba AD, сетевой доступ и Minecraft Multi-Server

## Цель релиза

1.3.0 превращает уже работающий Samba AD DC и файловый сервер в полноценно управляемые модули Control Center и расширяет Minecraft до нескольких управляемых Bedrock-инстансов.

Production 1.2.0 не изменяется до завершения preflight, CI и server-side acceptance 1.3.0.

---

## 1. Меню «Домен Samba»

### 1.1. Состояние домена

Интерфейс показывает реальные данные текущего DC:

- NetBIOS domain;
- DNS realm;
- имя DC;
- domain SID;
- forest/domain functional level;
- состояние Samba AD DC;
- DNS/Kerberos/LDAP health;
- SYSVOL/NETLOGON;
- replication summary, если в домене больше одного DC;
- версию Samba.

Обновление 1.3.0 не выполняет повторный `domain provision` существующего домена.

### 1.2. Парольная политика

Управляются доменные параметры:

- complexity on/off;
- password history length;
- minimum password length;
- minimum password age;
- maximum password age;
- account lockout threshold;
- account lockout duration;
- reset account lockout after.

Control Center сначала читает текущие значения, затем применяет только изменённые поля через привилегированный agent. После записи выполняется повторное чтение и сравнение desired/actual.

Fine-Grained Password Policies (PSO) в базовый 1.3.0 не смешиваются с глобальной политикой: архитектура API должна позволять добавить PSO отдельным экраном позже.

### 1.3. Пользователи домена

Список пользователей не загружается огромной таблицей целиком. Используются поиск/фильтр, карточка выбранного пользователя и пагинация.

Для пользователя доступны:

- ФИО: givenName / surname / displayName;
- логин (sAMAccountName);
- email;
- телефон;
- включён/заблокирован;
- разблокировка учётной записи;
- смена/сброс пароля;
- «сменить пароль при следующем входе»;
- срок действия учётной записи;
- членство в группах домена;
- primary group;
- homeDrive;
- homeDirectory;
- profilePath;
- scriptPath;
- описание.

Пароль никогда не передаётся как аргумент процесса и не попадает в журнал действий. Для privileged operation используется закрытый stdin/FD или временный root-only secret file с немедленным удалением.

### 1.4. Группы домена

Доступны:

- поиск и список групп;
- создание;
- переименование;
- удаление пользовательских групп;
- описание;
- просмотр состава;
- добавление/удаление пользователей и групп;
- назначение группы пользователю из карточки пользователя.

Builtin/system groups защищены от удаления и опасного переименования.

### 1.5. Domain backup / migration backup

Кнопка **«Создать резервную копию»** создаёт переносимый backup domain identity, а не копию одного `smb.conf`.

В контейнер миграционной копии входят:

1. официальный Samba domain backup (`samba-tool domain backup online` для работающего DC);
2. metadata Control Center;
3. managed share definitions;
4. ACL/owner metadata управляемых share roots;
5. quota metadata;
6. дополнительные managed Samba configuration fragments;
7. manifest с версиями Samba, Control Center, domain SID, realm, NetBIOS domain, hostname и checksum каждого компонента.

Доступны два режима:

- **Домен + конфигурация шар** — AD/SYSVOL/DNS/domain identity + определения/ACL/квоты шар без пользовательских файлов;
- **Полная миграционная копия** — дополнительно данные управляемых сетевых шар.

Архив скачивается из Control Center после завершения и проверки checksum.

### 1.6. Восстановление домена

Кнопка **«Восстановить из резервной копии»** открывает upload-dialog.

Восстановление предназначено прежде всего для нового сервера, где Samba packages установлены, но новый домен ещё не provisioned.

Перед restore выполняется:

- проверка формата archive и manifest;
- checksum validation;
- проверка Samba compatibility;
- проверка свободного места;
- запрет случайного overwrite работающего другого домена;
- создание rollback snapshot текущей Control Center/Samba configuration, если она существует.

Restore восстанавливает domain identity через Samba domain backup restore, затем share definitions/ACL/quota metadata и, для полной копии, share data.

Ключевое acceptance-требование: после восстановления сохраняются domain SID/realm и существующие Windows domain clients не требуют повторного ввода в домен, при условии корректного DNS/IP/hostname migration сценария.

Если новая машина получает другое имя DC, restore выполняется в поддерживаемом Samba backup/restore сценарии и не подменяется ручным копированием `sam.ldb`.

---

## 2. Меню «Общий/сетевой доступ»

### 2.1. Share management

Для управляемой шары хранятся:

- `name` — только ASCII: `A-Z a-z 0-9 _ -`, фактическое SMB-имя;
- `comment` — Unicode, включая русский;
- path;
- browse mode;
- read/write subjects;
- quota policy;
- created/managed metadata.

Создание и удаление выполняются через root-owned system agent.

Удаление имеет два варианта:

- удалить только SMB-публикацию, оставив каталог и данные;
- удалить публикацию и каталог — отдельное destructive подтверждение, по умолчанию выключено.

### 2.2. Права доступа

Можно назначать:

- доменного пользователя;
- доменную группу;
- `Everyone`.

Для каждого субъекта:

- Нет доступа;
- Чтение;
- Запись.

Share-level access формируется детерминированно (`valid users`, `read list`, `write list`) и дополняется ACL underlying directory. После применения Control Center проверяет effective configuration через `testparm` и фактическую доступность share definition.

### 2.3. Видимость

- **Открытая** — участвует в browse enumeration;
- **Скрытая** — `browseable = no`, но остаётся доступна при прямом `\\server\share` для пользователей с правами.

Это не заменяет ACL: скрытая шара без прав всё равно недоступна.

### 2.4. Квоты

Квота задаётся в GiB или как unlimited.

Backend определяет filesystem capability:

- XFS project quota;
- ext4 project quota, если filesystem/mount реально поддерживает её;
- Btrfs qgroup/subvolume quota;
- ZFS dataset quota.

Если backing filesystem не поддерживает безопасную directory/project quota, Control Center показывает `Квоты не поддерживаются на этом томе` и не имитирует ограничение только цифрой в UI.

Изменение квоты проверяется чтением actual filesystem quota после применения.

---

## 3. «Сервисы» — Samba AD DC

В каталог сервисов добавляется **Samba AD DC**.

### Установка

Установка ставит согласованный набор packages и prerequisites, но не уничтожает существующую конфигурацию.

После установки доступны два дальнейших сценария:

- создать новый домен;
- восстановить существующий домен из migration backup.

### Удаление

Удаление Samba AD DC — high-risk operation:

- перед удалением предлагается/по умолчанию создаётся domain migration backup;
- package removal отделён от удаления domain database/share data;
- domain data никогда не удаляются молча;
- purge domain identity требует отдельного подтверждения и не используется обычной кнопкой «Удалить сервис».

На уже работающем сервере 1.3.0 только обнаруживает текущую установку и не выполняет reinstall/provision автоматически.

---

## 4. Minecraft Multi-Server

### 4.1. Реестр инстансов

Minecraft перестаёт быть одиночным auto-discovered unit.

Control Center ведёт managed registry инстансов:

- id;
- display name;
- working directory;
- systemd unit;
- Bedrock version;
- ports;
- world;
- running state;
- published state;
- update mode;
- update channel/version metadata.

Существующий Bedrock server автоматически импортируется как legacy/default instance без изменения мира.

### 4.2. Несколько серверов

Доступны:

- создание нового инстанса;
- импорт существующего;
- запуск/остановка/restart;
- клонирование конфигурации;
- удаление публикации без удаления world data;
- отдельное удаление instance data с подтверждением.

Каждый одновременно работающий instance обязан иметь уникальные Bedrock ports.

### 4.3. Активный / пассивный

`published=true` означает, что instance разрешён политикой firewall/LAN publication и показывается как активный опубликованный сервер.

`published=false` означает, что instance не публикуется клиентам. Published state отделён от running state, чтобы можно было тестировать сервер локально/служебно.

### 4.4. Обновления Bedrock

Для каждого instance:

- Manual;
- Automatic.

Перед заменой Bedrock binary:

1. сохраняется instance/world backup;
2. проверяется новая версия;
3. сервер корректно останавливается;
4. меняется binary/runtime без удаления worlds/config;
5. выполняется startup healthcheck;
6. при ошибке выполняется rollback на предыдущую версию.

Нельзя автоматически понижать version.

### 4.5. Игроки

В интерфейсе:

- online/offline-known players;
- allowlist;
- add/remove allowlist;
- permission level (visitor/member/operator, где поддерживается Bedrock metadata);
- kick для online player, если instance поддерживает command channel;
- last seen / first seen;
- XUID, если он известен серверу;
- ban/deny policy Control Center с audit trail.

Для legacy-сервера функции, требующие управляющего command channel, включаются только после безопасного импорта в managed instance runtime.

---

## RBAC 1.3.0

Модули Control Center:

- `samba` — Домен Samba;
- `shares` — Общий/сетевой доступ;
- `minecraft` — Minecraft;
- остальные модули 1.2.0 без изменения.

Read позволяет просматривать состояние/объекты. Write позволяет изменять только соответствующий модуль. Full Administrator сохраняет все Write + admin-only операции.

Domain backup download разрешён `samba/write`; domain restore, Samba purge и destructive share-data delete требуют Full Administrator.

---

## Security contract

- никакого shell interpolation пользовательских значений;
- команды собираются только списками argv;
- пароли/секреты не пишутся в action JSON, stdout/stderr и audit log;
- destructive actions требуют отдельного action type и явного подтверждения;
- перед изменением Samba config выполняется backup + `testparm`;
- invalid config не активируется;
- restore archive распаковывается только после защиты от path traversal/symlink escape;
- upload имеет size limits и checksum validation;
- backup archives хранятся root-only, download идёт через авторизованный API;
- все изменения пишутся в audit trail: actor, object, action, result, timestamp без секретов.

---

## Acceptance 1.3.0

Релиз не переводится в `main`, пока автоматически не проверены:

1. upgrade 1.2.0 -> 1.3.0 без изменения существующего domain SID;
2. Samba discovery и password-policy read/write/readback;
3. domain user CRUD на тестовом объекте;
4. group CRUD и membership;
5. share create/read-write permissions/hide/unhide/remove-definition;
6. `testparm` после каждого изменения конфигурации;
7. quota backend capability detection и readback там, где quota поддерживается;
8. migration backup manifest/checksums;
9. restore в изолированный временный Samba target и совпадение domain SID/realm;
10. отсутствие секретов в logs/action queue;
11. Samba service install detection;
12. прямой user RBAC Write для `samba` и `shares`;
13. Full Administrator;
14. импорт существующего Minecraft instance;
15. создание второго instance с проверкой port collision;
16. published/unpublished state;
17. manual/automatic update configuration;
18. allowlist/player metadata operations;
19. полный syntax/static/JS/Python check;
20. preflight -> apply -> acceptance -> rollback.
