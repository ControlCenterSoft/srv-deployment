# Control Center — редакции Home и Professional

Этот документ описывает продуктовую модель редакций. Юридические условия использования определяются [EULA-RU.md](EULA-RU.md); технический механизм активации — [LICENSING.md](LICENSING.md).

## Home

Home — редакция по умолчанию, не требующая активации.

В соответствии с EULA Home предназначена для личного, домашнего и некоммерческого использования и имеет следующие лицензионные пределы:

- одна установка на одном сервере;
- один управляемый домен;
- до 10 доменных пользователей;
- до 10 сетевых общих ресурсов.

Коммерческое использование или выход за эти пределы требует Professional.

## Professional

Professional — активируемая редакция для коммерческого использования и конфигураций, выходящих за пределы Home. Стоимость и индивидуальные entitlements определяются предложением/договором; запрос стоимости: **8 (910) 220-00-02**.

Professional подтверждается RSA/SHA-256 подписанной лицензией, привязанной к `device_id` сервера.

## Единая кодовая база

Home и Professional используют одну кодовую базу Control Center. Текущая редакция определяется валидной подтверждённой лицензией.

```text
Home          — лицензия Professional отсутствует или недействительна
Professional  — валидная подписанная лицензия для текущего device_id
```

## Состояние 1.0.7

В 1.0.7 реализованы:

- отображение текущей редакции и device ID;
- выпуск и проверка Professional-лицензии;
- защищённое хранение лицензии;
- PostgreSQL как базовый application data layer;
- audit/jobs/notifications/settings/module/service data в PostgreSQL;
- `cluster_nodes` и заменяемый runtime DSN как **архитектурная подготовка** к будущему Professional Cluster.

## Professional Cluster — следующий этап

Кластерный функционал **ещё не является доступной функцией 1.0.7**. В текущем релизе локальный сервер регистрируется как `standalone` node, а PostgreSQL работает локально через Unix socket.

Будущий Professional Cluster предполагается развивать поверх подготовленной модели данных с отдельными механизмами:

- cluster enrollment;
- node identity и роли;
- безопасный межузловой transport/TLS;
- topology/quorum;
- replication/failover;
- cluster-wide tasks/audit;
- backup/restore и split-brain protection.

Нельзя считать ручное направление `CONTROL_CENTER_DB_DSN` на удалённый PostgreSQL поддерживаемым кластерным режимом до выпуска соответствующей Professional-функции.

## Безопасность Web UI

Наличие Professional или PostgreSQL не отменяет ограничения административного Web UI. Встроенная Web-аутентификация пока отсутствует; административный порт должен оставаться доступным только из доверенной сети/VPN/firewall.

## Связанные документы

- [EULA-RU.md](EULA-RU.md)
- [LICENSING.md](LICENSING.md)
- [POSTGRESQL.md](POSTGRESQL.md)
- [UPDATE-LIFECYCLE-POLICY-RU.md](UPDATE-LIFECYCLE-POLICY-RU.md)
