# Обновление ОС и пакетов

Control Center 1.0.6 имеет отдельный механизм обновления системных пакетов Ubuntu/Debian. Он не связан с обновлением самого Control Center.

## Web UI

Раздел **Настройки → Обновления ОС и пакетов** позволяет:

- включить/выключить автоматические обновления;
- задать интервал 60–10080 минут;
- выполнить ручной запуск кнопкой **Обновить сейчас**;
- увидеть последний protected status, который также попадает в общий центр уведомлений.

По умолчанию автоматический режим выключен, интервал — 1440 минут.

## State

Web-writable настройки и ручной trigger:

```text
/var/lib/control-center/os-update-settings.json
/var/lib/control-center/os-update-now
```

Защищённый результат root worker:

```text
/var/lib/control-center-system/os-update-status.json
```

Этот результат используется одновременно разделом Настройки и колокольчиком уведомлений.

## Systemd

```text
control-center-os-update.timer
control-center-os-update.service
/usr/local/sbin/control-center-os-update
```

Timer просыпается раз в минуту. Реальное обновление выполняется только после заданного интервала либо manual trigger.

## Пакетная операция

```bash
apt-get update
apt-get -y upgrade --with-new-pkgs
```

Механизм не выполняет переход Ubuntu на следующий релиз и не перезагружает сервер автоматически. Наличие `/var/run/reboot-required` отображается в Web UI.

## Защита от конфликтов APT

```text
/run/control-center-apt.lock
```

Этот lock сериализует installer, OS/package updater и пакетные операции Маркета.

## Диагностика

```bash
systemctl status control-center-os-update.timer --no-pager
systemctl status control-center-os-update.service --no-pager
journalctl -u control-center-os-update.service -n 200 --no-pager
cat /var/lib/control-center/os-update-settings.json
sudo cat /var/lib/control-center-system/os-update-status.json
curl -fsS http://127.0.0.1:8080/api/notifications | python3 -m json.tool
```
