# Установка Control Center 1.0.5

## Поддерживаемая платформа

Основная целевая платформа релиза 1.0.5 — Ubuntu Server 26.04 LTS с systemd и Netplan. Требуются root/sudo, доступ к APT-репозиториям и TCP-порт 8080 для Web UI.

## Рекомендуемая установка

```bash
curl -fL -o control-center-install.sh https://control-center-website.sazonovpg.workers.dev/install.sh
chmod +x control-center-install.sh
sudo ./control-center-install.sh
```

Bootstrap получает ветку `release/1.0.5` и запускает `install/install.sh`.

Прямая установка из GitHub:

```bash
git clone --depth 1 --branch release/1.0.5 https://github.com/filosoff31/srv-deployment.git
cd srv-deployment
sudo bash install/install.sh
```

## Что устанавливается

- `/opt/control-center/app` — Web-приложение;
- `/opt/control-center/venv` — Python virtualenv;
- `/var/lib/control-center` — Web-writable состояние, настройки, pending requests и статусы;
- `/var/lib/control-center-root` — root-only rollback state (`0700`), недоступный Web service;
- `/var/lib/control-center-license` — подтверждённая Professional-лицензия, каталог принадлежит root;
- `/etc/control-center/license-public.pem` — публичный ключ проверки лицензий;
- `/usr/local/sbin/control-center-*` — привилегированные helpers;
- systemd service/path/timer units Control Center.

Web-процесс работает от системной УЗ `control-center` без интерактивного shell и без root-прав. Root helpers повторно валидируют сетевые и DHCP pending-запросы перед применением и не доверяют одной только Web/API-проверке.

## Службы

```text
control-center.service
control-center-update.timer
control-center-os-update.timer
control-center-network-apply.path
control-center-market-apply.path
control-center-dhcp-apply.path
control-center-license-apply.path
```

## Проверка после установки

```bash
cat /opt/control-center/VERSION
curl -fsS http://127.0.0.1:8080/api/health && echo
systemctl status control-center --no-pager
systemctl list-timers --all | grep control-center
systemctl list-units --type=path | grep control-center
ls -ld /var/lib/control-center /var/lib/control-center-root /var/lib/control-center-license
```

Ожидаемая версия: `1.0.5`. До активации редакция: `Home`.

Web UI:

```text
http://IP_СЕРВЕРА:8080
```

## Пакетные операции

Control Center использует общий lock `/run/control-center-apt.lock`, поэтому установка продукта, обновление ОС/пакетов и установка DHCP через Маркет не должны одновременно выполнять APT/dpkg.

## Обновление существующей установки

Повторный запуск установщика сохраняет Web-state, root rollback-state и подтверждённую Professional-лицензию. Приложение и helpers обновляются до содержимого release-ветки.

Важно: ранняя pre-audit сборка 1.0.5 сохраняла лицензию в Web-writable каталоге. Установщик исправленной 1.0.5 намеренно удаляет и не доверяет такому старому файлу; Professional потребуется активировать повторно корректно подписанной лицензией.

## Удаление

Полное удаление:

```bash
sudo bash install/uninstall.sh
```

Удалить приложение, но оставить Web-state, root rollback-state и лицензию:

```bash
sudo bash install/uninstall.sh --keep-data
```

## Базовая диагностика

```bash
journalctl -u control-center -n 200 --no-pager
ss -ltnp | grep ':8080'
curl -v http://127.0.0.1:8080/api/health
```

См. также `docs/TROUBLESHOOTING.md` и `docs/AUDIT-1.0.5.md`.
