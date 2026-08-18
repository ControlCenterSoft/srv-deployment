# Control Center 1.0.3

Control Center — web-панель управления Linux-сервером.

## Что нового в 1.0.3

- в разделе **Система** CPU и RAM получили отдельные live-графики;
- в карточке CPU отображается **Top-3 процессов** по загрузке CPU с долей RAM;
- **Хранилище** показывает файловые системы отдельными полосами заполнения, проценты и объемы;
- **WAN** получил отдельный live-график входящей и исходящей скорости RX/TX;
- WAN для dashboard определяется из сохраненной роли WAN раздела **Сети**;
- данные dashboard обновляются каждые 3 секунды;
- в **Настройки → Автоматические обновления** период теперь задается вручную в минутах;
- допустимый интервал: от **5** до **10080** минут;
- старые значения `hourly`, `daily`, `weekly` автоматически мигрируют в 60, 1440 и 10080 минут.

## Dashboard «Система»

Карточки:

- CPU — текущая загрузка, live-график, количество логических CPU и Top-3 процессов;
- RAM — текущая загрузка, live-график, использовано/всего;
- Хранилище — заполнение доступных постоянных файловых систем;
- WAN — интерфейс, его состояние, live RX/TX и текущая скорость в байтах/с.

## Автоматические обновления

Настройка хранится в:

`/var/lib/control-center/update-settings.json`

Формат 1.0.3:

```json
{
  "automatic_updates": true,
  "interval_minutes": 60,
  "channel": "production"
}
```

Systemd timer запускает легкий updater раз в минуту, но обращение к GitHub выполняется только по истечении заданного `interval_minutes`.

## Сетевое управление

Функции 1.0.2 сохранены: WAN/LAN, DHCP/Static, проверка IPv4/маски/шлюза/DNS, Netplan apply и rollback.

## Установка

```bash
sudo bash install/install.sh
```

Web UI:

```text
http://SERVER_IP:8080
```

Проверка:

```bash
cat /opt/control-center/VERSION
systemctl status control-center --no-pager
systemctl status control-center-update.timer --no-pager
curl -fsS http://127.0.0.1:8080/api/health
cat /var/lib/control-center/update-settings.json
```
