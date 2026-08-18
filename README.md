# Control Center 1.0.8

Control Center — web-панель управления Linux-сервером. Текущая release-ветка: **1.0.8**, build **20260819.1**.

## Главное в 1.0.8

- постоянные статусы сервисов в **Маркете**: `Установка…`, `Работает`, `Ошибка`, `Не установлен`, `Запланировано`;
- статус не сбрасывается при обновлении страницы или переходе между разделами;
- при `Ошибка` diagnostic detail показывается tooltip при наведении мыши;
- начало, успех и ошибка установки/удаления сервиса сохраняются как отдельные события и отображаются в колокольчике с датой/временем;
- переработана и реально проверяется установка **DHCP Server / dnsmasq**;
- recovery незавершённой предыдущей установки DHCP без автоматического захвата внешней DHCP-конфигурации;
- **Настройки → Обновления Control Center**: кнопка установки активируется только при наличии нового Production release/build;
- ручная установка обновления запускает root updater через `control-center-update-now.path` и не зависит от включённости автоматических обновлений;
- PostgreSQL, Web-port, licensing, network/DHCP configuration и protected state архитектура 1.0.7 сохранены.

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

При установке `dnsmasq` используется временный `policy-rc.d`, чтобы пакет не пытался запустить обычный DNS/DHCP daemon до того, как Control Center подготовит конфигурацию. После установки выполняются package check и `dnsmasq --test`.

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

GitHub Actions дополнительно выполняет реальную установку и удаление `dnsmasq` тем же Market helper, которым пользуется сервер.

## Home / Professional

- **Home** — домашнее некоммерческое использование;
- **Professional** — коммерческое использование и расширенные возможности по лицензии.

Существующая Home-редакция продолжает работать без остановки сервисов из-за лицензионного состояния.

## Безопасность

Встроенная Web-аутентификация административной панели пока не реализована. Web-порт Control Center необходимо ограничивать доверенной LAN/VPN/firewall и не публиковать напрямую в Интернет.

Подробности релиза: `releases/1.0.8/README.md`.
