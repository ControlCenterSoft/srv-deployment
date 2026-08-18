# Control Center 1.0.8

Control Center — web-панель управления Linux-сервером. Текущая release-ветка: **1.0.8**, build **20260819.2**.

## Главное в 1.0.8

- постоянные статусы сервисов в **Маркете**: `Установка…`, `Работает`, `Ошибка`, `Не установлен`, `Запланировано`;
- статус не сбрасывается при обновлении страницы или переходе между разделами;
- при `Ошибка` diagnostic detail показывается tooltip при наведении мыши;
- начало, успех и ошибка установки/удаления сервиса сохраняются как отдельные события и отображаются в колокольчике с датой/временем;
- переработана и реально проверяется установка **DHCP Server / dnsmasq**;
- recovery незавершённой предыдущей установки DHCP без автоматического захвата внешней DHCP-конфигурации;
- **Настройки → Обновления Control Center**: кнопка установки активируется только при наличии нового Production release/build;
- ручная установка обновления запускает root updater через `control-center-update-now.path`;
- build `20260819.2` добавляет прямую совместимость со старым updater 1.0.6 и предварительное восстановление half-configured `dpkg/apt`;
- PostgreSQL, Web-port, licensing, network/DHCP configuration и protected state архитектура 1.0.7 сохранены.

## Восстановление проблемного обновления 1.0.6

Если сервер остаётся на 1.0.6, в уведомлениях есть `код 100`, ошибка обновления ОС/пакетов и `dnsmasq, установленный вне Control Center`, используйте:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/filosoff31/srv-deployment/release/1.0.8/scripts/repair-upgrade-1.0.6-to-1.0.8.sh \
  | sudo bash
```

Скрипт сначала сохраняет диагностику и конфигурацию в `/var/lib/control-center-root/manual-repair-<timestamp>/`, затем запускает существующий production updater 1.0.6. Его штатный rollback остаётся активным.

Активная внешняя конфигурация `dnsmasq` не удаляется и не захватывается. Автоматическое восстановление DHCP выполняется только для legacy-состояния без пользовательской конфигурации.

## PostgreSQL

PostgreSQL остаётся базовым application data layer. Локальная роль `control-center` подключается через Unix socket/peer authentication. Пароль PostgreSQL в приложении не хранится, внешний PostgreSQL listener автоматически не открывается.

Системные источники состояния Linux не заменяются БД: Netplan, systemd и dnsmasq остаются фактической конфигурацией ОС.

## DHCP install lifecycle

Market worker:

```text
/api/market/dhcp
  -> /var/lib/control-center/market-pending.json
  -> control-center-market-apply.path
  -> control-center-market-apply.service
  -> /usr/local/sbin/control-center-market-apply
```

Защищённые результаты:

```text
/var/lib/control-center-system/market-status.json
/var/lib/control-center-system/market-events.jsonl
/var/lib/control-center-system/market-last.log
/var/lib/control-center-system/modules/dhcp.json
```

Fresh install использует временный `policy-rc.d`, выполняет package check и `dnsmasq --test`. Build 20260819.2 дополнительно умеет восстановить конкретный legacy failure 1.0.6 через явный root-owned recovery marker.

## Установка

```bash
git clone --depth 1 --branch release/1.0.8 https://github.com/filosoff31/srv-deployment.git
cd srv-deployment
sudo bash install/install.sh
```

Web UI по умолчанию:

```text
http://SERVER_IP:8080
```

Если порт ранее изменён в настройках Control Center, installer сохраняет его.

## Acceptance

```bash
sudo bash scripts/acceptance-1.0.8.sh
```

Ожидаемый build:

```text
20260819.2
```

GitHub Actions проверяет legacy updater payload check, PostgreSQL, fresh DHCP install/remove и отдельный legacy DHCP recovery scenario.

## Home / Professional

- **Home** — домашнее некоммерческое использование;
- **Professional** — коммерческое использование и расширенные возможности по лицензии.

## Безопасность

Встроенная Web-аутентификация административной панели пока не реализована. Web-порт Control Center необходимо ограничивать доверенной LAN/VPN/firewall и не публиковать напрямую в Интернет.

Подробности релиза: `releases/1.0.8/README.md`.
