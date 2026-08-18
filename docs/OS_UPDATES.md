# Обновление ОС и пакетов

Control Center 1.0.5 имеет отдельный механизм обновления системных пакетов Ubuntu/Debian. Он не связан с обновлением самого Control Center.

## Web UI

Раздел **Настройки → Обновления ОС и пакетов** позволяет:

- включить/выключить автоматические обновления;
- задать интервал от 60 до 10080 минут;
- выполнить ручной запуск кнопкой **Обновить сейчас**.

По умолчанию автоматическое обновление ОС выключено, интервал — 1440 минут.

## Файлы

```text
/var/lib/control-center/os-update-settings.json
/var/lib/control-center/os-update-status.json
/var/lib/control-center/os-update-now
```

## Systemd

```text
control-center-os-update.timer
control-center-os-update.service
/usr/local/sbin/control-center-os-update
```

Timer просыпается раз в минуту. Реальное обновление выполняется только по истечении заданного интервала либо после ручного запроса.

## Пакетная операция

Worker выполняет:

```bash
apt-get update
apt-get -y upgrade --with-new-pkgs
```

Это обновляет установленные пакеты и позволяет установить новые зависимости, необходимые обновлениям. Механизм **не выполняет переход Ubuntu на новый релиз** (например, 26.04 → следующий выпуск) и не запускает автоматическую перезагрузку.

Если после обновления существует `/var/run/reboot-required`, Web UI показывает, что серверу требуется перезагрузка.

## Защита от конфликтов APT

Все пакетные операции Control Center используют общий lock:

```text
/run/control-center-apt.lock
```

Это предотвращает одновременный запуск APT при обновлении ОС, установке Control Center и установке/удалении пакетов из Маркета.

## Ручная диагностика

```bash
systemctl status control-center-os-update.timer --no-pager
systemctl status control-center-os-update.service --no-pager
journalctl -u control-center-os-update.service -n 200 --no-pager
cat /var/lib/control-center/os-update-settings.json
cat /var/lib/control-center/os-update-status.json
```

Ручной запуск worker:

```bash
sudo systemctl start control-center-os-update.service
```

Если автоматический режим выключен и маркер ручного запуска отсутствует, прямой запуск service корректно завершится без обновления.
