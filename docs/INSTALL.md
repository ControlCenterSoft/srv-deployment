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

## Web runtime

Production Web UI запускается через **Gunicorn** (`wsgi:app`), а не встроенный Flask development server. WSGI entrypoint добавляет security headers, ограничение размера запроса, same-origin проверку браузерных изменяющих запросов и collision-safe atomic JSON writes для нескольких workers.

## Разделение состояния

```text
/var/lib/control-center
```
Web-writable: настройки и pending requests.

```text
/var/lib/control-center-system
```
`root:control-center 0750`: применённые конфигурации, статусы и ownership модулей. Web UI может читать через compatibility links, но root helpers используют только защищённые оригиналы.

```text
/var/lib/control-center-root
```
`root:root 0700`: rollback-копии. Web service получает `InaccessiblePaths`.

```text
/var/lib/control-center-license
```
`root:control-center 0750`: подтверждённая Professional-лицензия; файл лицензии имеет режим `0640`.

## Устанавливаемые компоненты

- `/opt/control-center/app` — Web-приложение и WSGI entrypoint;
- `/opt/control-center/venv` — Python virtualenv с Flask/Gunicorn;
- `/etc/control-center/license-public.pem` — публичный ключ Professional;
- `/usr/local/sbin/control-center-*` — привилегированные helpers;
- systemd services/path/timers.

Основной Web-процесс работает от системной УЗ `control-center` без интерактивного shell и без root-прав. Network и DHCP root helpers повторно валидируют pending requests перед применением.

## Основные службы

```text
control-center.service
control-center-update.timer
control-center-os-update.timer
control-center-network-apply.path
control-center-market-apply.path
control-center-dhcp-server.service   # только если DHCP установлен и настроен
control-center-dhcp-apply.path
control-center-license-apply.path
```

Управляемый DHCP использует отдельную службу `control-center-dhcp-server.service`; дистрибутивный `dnsmasq.service` не используется как runtime Control Center.

## Проверка после установки

```bash
cat /opt/control-center/VERSION
curl -fsS http://127.0.0.1:8080/api/health && echo
systemctl status control-center --no-pager
systemctl list-timers --all | grep control-center
systemctl list-units --type=path | grep control-center
ls -ld /var/lib/control-center /var/lib/control-center-system /var/lib/control-center-root /var/lib/control-center-license
```

Ожидаемая версия: `1.0.5`. До активации редакция: `Home`.

Web UI:

```text
http://IP_СЕРВЕРА:8080
```

## Полный acceptance

Из checkout ветки `release/1.0.5`:

```bash
sudo bash scripts/acceptance-1.0.5.sh
```

Скрипт не меняет конфигурацию и проверяет version/API, HTTP headers, Gunicorn, systemd units, protected state, лицензионный ключ, Netplan и — если модуль DHCP настроен — выделенную DHCP-службу и `dnsmasq --test`.

## Пакетные операции

Установщик, OS/package updater и Маркет используют общий lock:

```text
/run/control-center-apt.lock
```

Это предотвращает параллельные внутренние APT/dpkg операции.

## Обновление существующей установки

Повторный запуск установщика сохраняет Web-state, protected system-state, root rollback-state и подтверждённую Professional-лицензию.

Legacy ownership DHCP из старого Web-writable state не считается доверенным. Если старый Control Center DHCP можно подтвердить установленным пакетом и валидным конфигом, он мигрируется как `package_owned=false`: Control Center сможет им управлять, но не удалит сам пакет только на основании старых метаданных.

Важно: ранняя pre-audit сборка 1.0.5 сохраняла лицензию в Web-writable каталоге. Исправленный установщик не доверяет такому файлу; Professional потребуется активировать повторно корректно подписанной лицензией.

## Удаление

Полное удаление:

```bash
sudo bash install/uninstall.sh
```

Удалить приложение, но оставить все state-каталоги, лицензию и служебную УЗ/группу для последующей переустановки:

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
