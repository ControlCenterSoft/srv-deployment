# Control Center 1.0.10

Статус: `production candidate` до завершения финального CI.

## 1. Samba AD-DC — подготовка к Production

1.0.10 не выполняет `samba-tool domain provision` и не меняет DNS/Kerberos домена. Релиз доводит подготовительный слой до состояния, пригодного для production-реализации в следующем релизе.

Добавлены:

- PostgreSQL migration `003_samba_ad_dc_readiness.sql`;
- расширенный readiness API `/api/samba/readiness`;
- dry-run change plan `/api/samba/plan`;
- блокеры и предупреждения по hostname/FQDN, статическому IPv4, времени, APT-пакетам, свободному месту, портам 53/88/389/445 и существующей Samba-конфигурации;
- модель backup/cutover/rollback/acceptance для будущего provisioning;
- сохранение readiness runs и change plans в PostgreSQL;
- статус Samba в Маркете без кнопки установки.

Целевой production-релиз provisioning: **1.0.11**.

## 2. Переименование компьютера

В Настройки добавлено изменение hostname. Web UI создаёт запрос, а отдельный root-helper:

1. валидирует DNS-совместимое single-label имя;
2. сохраняет резервные копии `/etc/hostname` и `/etc/hosts`;
3. вызывает `hostnamectl set-hostname`;
4. безопасно обновляет `127.0.1.1` в `/etc/hosts`;
5. проверяет результат;
6. выполняет rollback при ошибке.

## 3. Web-порт и SSL

Исправлена зависимость Web runtime от PostgreSQL.

Теперь:

- стандартный HTTP → `80`;
- стандартный HTTPS → `443`;
- пользовательский HTTP/HTTPS → `1024–65535`;
- Web runtime и `/etc/control-center/web.env` являются источником фактической конфигурации;
- PostgreSQL синхронизируется best-effort и не блокирует смену порта/SSL;
- при недоступной БД Web runtime всё равно меняется и проходит HTTP/HTTPS health-check;
- self-signed сертификат создаётся root-helper и назначается Gunicorn;
- при runtime failure выполняется rollback.

## 4. Центр уведомлений

Проведена ревизия источников событий. В колокольчик включаются:

- сеть;
- Market lifecycle;
- DHCP;
- лицензия;
- обновление Control Center;
- обновление ОС;
- Web runtime и SSL;
- PostgreSQL unavailable/degraded;
- переименование компьютера;
- Samba AD-DC readiness.

Постоянные operational alerts больше не должны дублироваться длинными сообщениями внутри карточек интерфейса. В карточках остаётся только состояние и краткий feedback текущего действия.

## 5. Одна или две сетевые роли

В WAN и LAN появился вариант **«Выключен»**.

Поддерживаются:

- WAN + LAN;
- только WAN;
- только LAN.

Обе роли одновременно выключить нельзя. При включённом WAN LAN не может создавать второй default route. Если WAN выключен, единственный LAN может использовать собственный gateway/default route.

Dashboard автоматически показывает:

- два графика, если включены WAN и LAN;
- только WAN, если LAN выключен;
- только LAN, если WAN выключен.

## Acceptance

```bash
sudo bash scripts/acceptance-1.0.10.sh
```

Production будет опубликован только после успешных static, PostgreSQL migration, Flask API, installer/runtime, HTTP/HTTPS 80/443 и regression checks.
