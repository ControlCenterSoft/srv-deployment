# Аудит Control Center 1.0.5

Дата аудита: 2026-08-18.

## Область проверки

Проверены release/main, Web API/UI, Python/Bash/JSON, installer/uninstaller, systemd units, обновление Control Center, OS/package update, WAN/LAN, Netplan, DHCP Market/runtime/configuration, Home/Professional licensing, trust boundaries state-файлов, документация, public website/bootstrap и защита от регрессий.

## Критичные исправления

- **Professional license trust:** подтверждённая лицензия вынесена из Web-writable state в `/var/lib/control-center-license` (`root:control-center 0750`, license `0640`).
- **Module ownership trust:** DHCP ownership больше не хранится в Web-writable каталоге. Защищённый state находится в `/var/lib/control-center-system/modules/dhcp.json`.
- **State separation:** добавлен `/var/lib/control-center-system` для applied state/status и `/var/lib/control-center-root` (`0700`) для rollback. Web service получает system/license read-only и полностью лишён доступа к root rollback state.
- **Root revalidation:** network/DHCP helpers повторно валидируют pending requests перед привилегированным применением; Web API validation не считается границей доверия.
- **DHCP ownership/runtime:** Control Center не захватывает внешний `dnsmasq`; managed DHCP работает отдельным `control-center-dhcp-server.service`. Пакет удаляется только при защищённом `package_owned=true`.
- **Professional key chain:** сформирована рабочая RSA-пара издателя, в GitHub хранится только public key. Приватный issuing key не входит в продукт.
- **Updater parser:** исправлена несовместимость проверки `APP_VERSION`; 1.0.5 остаётся читаемой старым updater 1.0.4.
- **DHCP rollback:** неудачный `dnsmasq --test`/restart больше не оставляет повреждённую active configuration.
- **dnsmasq IPv4 netmask:** CIDR из Web/API преобразуется в dotted IPv4 netmask перед формированием `dhcp-range`.

## Web/runtime исправления

- Flask development server заменён на **Gunicorn production WSGI** (`wsgi:app`).
- Добавлены CSP, nosniff, frame denial, Referrer/Permissions/COOP headers и `Cache-Control: no-store` для API/HTML.
- Добавлены same-origin проверки браузерных write requests и request body limit 64 KiB.
- JSON writes в production переведены на уникальные atomic temp files, устраняя collision между Gunicorn workers.
- Динамические строки перед `innerHTML` экранируются; устранён XSS-класс через локальные имена процессов/пользователей/системные строки.
- WAN chart теперь одновременно показывает RX и TX.
- WAN/LAN форма снова восстанавливает сохранённые параметры.
- Декоративный `admin` убран: sidebar показывает реальную редакцию. Поиск (`Ctrl+K`) и сворачивание sidebar стали функциональными.

## Пакеты и lifecycle

- Installer, OS updater и Market используют общий `/run/control-center-apt.lock`.
- OS updater использует `apt-get -y upgrade --with-new-pkgs`, не выполняет release-upgrade и не делает automatic reboot; статус показывает `reboot_required`.
- `uninstall.sh` удаляет все services/path/timers/helpers; `--keep-data` сохраняет четыре state-каталога и служебную identity `control-center`.
- Stale privileged pending requests удаляются при install/update и не воспроизводятся после переустановки.

## Документация и сайт

- `docs/INSTALL.md` ранее был зафиксирован на 1.0.0, `docs/UPDATE.md` — на 1.0.1 и старой hour/day/week модели. Они полностью переписаны для 1.0.5.
- Добавлены `LICENSING`, `OS_UPDATES`, `NETWORK`, `DHCP`, `SECURITY`, `TROUBLESHOOTING`, индекс docs и этот audit report.
- Публичные страницы сайта были статически на 1.0.1; главная, Возможности, Релизы, Документация и Скачать синхронизированы с 1.0.5, добавлена страница Home/Professional.
- Public bootstrap указывает на `release/1.0.5`.
- Для `/install.sh` на сайте задан `Cache-Control: no-store`; HTML/app.js требуют revalidation, чтобы не повторялась выдача старого bootstrap из cache.
- Усилены security headers публичного сайта.

## Автоматическая защита от регрессий

`.github/workflows/validate-release.yml` проверяет Python/Bash syntax, JSON, version/deployment/manifest consistency, Gunicorn/WSGI, protected state, DHCP isolation/netmask, public RSA key, отсутствие private signing material и обязательную документацию.

`.github/workflows/validate-site.yml` проверяет bootstrap syntax/version, fallback release, обязательные страницы, локальные HTML links, security/cache headers.

`scripts/acceptance-1.0.5.sh` выполняет non-destructive server acceptance: API/version/headers, service user, Gunicorn, timers/path units, state permissions, public key, Netplan и managed DHCP runtime/config.

## Известное ограничение

В 1.0.5 ещё **нет полноценной встроенной аутентификации Web UI**. TCP/8080 нельзя публиковать напрямую в Интернет или недоверенную сеть. CSP/same-origin/systemd hardening не заменяют authentication/authorization. До следующего этапа доступ должен ограничиваться доверенной административной LAN/VPN/firewall или reverse proxy с аутентификацией.

## Что этим аудитом не подтверждено

Статический/code audit не заменяет end-to-end acceptance на реальном Ubuntu 26.04 с systemd/Netplan/dnsmasq. Полная реальная переустановка, изменение активной сети и DHCP lease выдача в текущем инструментальном окружении не выполнялись.

Фактический Cloudflare deployment public URL после последнего website commit также не был независимо подтверждён браузерным инструментом; GitHub source и deployment inputs обновлены.

RSA issuing pair отдельно проверена локальной OpenSSL sign/verify операцией.

## Acceptance на сервере

Из checkout `release/1.0.5`:

```bash
sudo bash scripts/acceptance-1.0.5.sh
```

Дополнительно:

```bash
journalctl -p warning..alert --since '1 hour ago' --no-pager
```

После автоматического acceptance отдельно следует функционально проверить изменение WAN/LAN с доступом по резервному каналу, установку/настройку/удаление DHCP, получение lease тестовым клиентом, manual OS update и тестовую Professional activation.
