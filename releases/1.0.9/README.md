# Control Center 1.0.9

Статус: `production candidate` до финального GitHub Actions validation.

## 1. Пагинация

Единый компонент страниц применяется ко всем длинным перечням текущего Web UI:

- сетевые интерфейсы;
- DHCP additional options;
- RBAC users;
- RBAC groups;
- уведомления;
- Маркет сервисов.

Пагинация скрывается автоматически, если весь список помещается на одну страницу.

## 2. Обзор системы

Dashboard переработан по макету 1.0.9:

- CPU: live chart + отдельный Top CPU;
- RAM: live chart + отдельный Top RAM;
- общий нижний блок «Топ процессов» удалён;
- хранилище: круговая диаграмма + список filesystem/mount usage;
- сетевая карточка обзора теперь показывает LAN RX/TX;
- системные сведения вынесены в отдельный нижний блок.

## 3. Стандартный порт и SSL

В **Настройки → Web-панель** добавлены:

- `Стандартный порт`;
- `Включить SSL / HTTPS`;
- пользовательский порт.

Логика:

| Режим | Порт |
|---|---:|
| HTTP + стандартный | 80 |
| HTTPS + стандартный | 443 |
| HTTP/HTTPS + пользовательский | 1024–65535 |

Для привилегированных портов 80/443 systemd выдаёт только `CAP_NET_BIND_SERVICE` Web-службе. Root-права приложению не выдаются.

HTTPS в 1.0.9 использует локальный self-signed сертификат `/etc/control-center/tls/server.crt` и ключ `/etc/control-center/tls/server.key`. Сертификат создаётся root helper только при первом включении SSL. Браузер может показывать предупреждение доверия. ACME/Let's Encrypt и загрузка пользовательского сертификата запланированы отдельно.

Изменение протокола/порта выполняется через `control-center-web-apply`: проверка порта → генерация сертификата при необходимости → PostgreSQL settings → restart → HTTP/HTTPS health-check → rollback при ошибке.

## 4. Подготовка Samba AD-DC

В PostgreSQL migration `002` добавлены:

- `ad_dc_profiles`;
- `ad_dc_nodes`;
- `ad_dc_preflight_runs`.

Добавлен `/api/samba/preflight`, который проверяет FQDN, статический LAN, синхронизацию времени, использование TCP/UDP 53 и наличие Samba package. Результаты preflight сохраняются в PostgreSQL.

В Маркете Samba отображается как **Samba AD-DC · Подготовлено**. Реальная установка, `samba-tool domain provision`, DNS cutover, создание realm/domain и ввод Administrator password в 1.0.9 **не выполняются**.

## Acceptance

```bash
sudo bash scripts/acceptance-1.0.9.sh
```

Проверяются version/build, dashboard API, pagination assets, PostgreSQL migration 002, AD-DC schema/preflight, Web runtime wrapper и поля Standard Port/SSL.
