# Подготовка Samba AD-DC — Control Center 1.0.9

## Статус

1.0.9 **не устанавливает и не провижинит доменный контроллер**. Релиз подготавливает безопасный data/API foundation для следующего этапа.

В Маркете модуль отображается как:

```text
Samba AD-DC · Подготовлено
```

Кнопка установки намеренно отсутствует.

## PostgreSQL migration 002

Созданы таблицы:

```text
control_center.ad_dc_profiles
control_center.ad_dc_nodes
control_center.ad_dc_preflight_runs
```

`ad_dc_profiles` предназначена для realm, NetBIOS domain, DNS backend, functional level, site и будущей конфигурации домена. Секреты/пароли в этой таблице не предусмотрены.

`ad_dc_nodes` связывает будущие DC с профилем домена и хранит только operational metadata.

`ad_dc_preflight_runs` сохраняет результаты проверок готовности.

## Preflight API

```text
GET/POST /api/samba/preflight
```

Проверяются:

- FQDN сервера;
- наличие статического LAN IPv4;
- синхронизация времени;
- слушатели на TCP/UDP 53;
- наличие Samba package;
- network source и перечень интерфейсов.

Отсутствие Samba package в 1.0.9 не считается ошибкой: пакет будет устанавливаться только после реализации отдельного lifecycle worker.

## Что будет следующим этапом

Архитектура подготовлена для дальнейшего добавления:

1. установки пакетов Samba/Kerberos/DNS;
2. мастера создания/присоединения realm;
3. безопасного хранения/ввода Administrator secret без записи plaintext в PostgreSQL;
4. `samba-tool domain provision` через отдельный root helper;
5. контроля DNS cutover и конфликта порта 53;
6. backup/restore AD database и sysvol;
7. пользователей, групп, OU, GPO/RBAC integration;
8. вторичного DC и будущего Professional Cluster.

## Почему provisioning пока отключён

Ошибочная автоматическая настройка AD-DC может изменить DNS, Kerberos, hostname/FQDN и сетевой доступ всего домена. Поэтому 1.0.9 только собирает prerequisites и создаёт versioned data model; destructive provisioning будет добавлен отдельным релизом с rollback/backup/acceptance.

## Диагностика

```bash
PORT=$(sed -n 's/^CONTROL_CENTER_PORT=//p' /etc/control-center/web.env)
curl -fsS "http://127.0.0.1:${PORT}/api/samba/preflight" | python3 -m json.tool
sudo -u control-center psql -d control_center -c \
  'select id,created_at,hostname,fqdn,ready,checks from control_center.ad_dc_preflight_runs order by id desc limit 10;'
```

При включённом SSL используйте `https://` и `curl -k` для self-signed сертификата.
