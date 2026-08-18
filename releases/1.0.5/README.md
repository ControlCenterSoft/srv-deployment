# Control Center 1.0.5

Статус: `production`.

## Основные изменения

1. Две редакции: Home и Professional.
2. Professional activation через RSA/SHA-256 подписанную лицензию, привязанную к device ID.
3. Отображение текущей редакции и версии в Web UI.
4. Отдельные настройки обновления ОС и пакетов: manual/automatic + интервал.
5. Сохранены функции 1.0.4: новый интерфейс, DHCP в Маркете, динамическое меню DHCP.

## Исправления полного аудита

- state разделён на Web-writable, protected system, root-only rollback и protected license;
- подтверждённая лицензия: `/var/lib/control-center-license`, `root:control-center`, каталог `0750`, файл `0640`;
- DHCP ownership и applied/status state вынесены в `/var/lib/control-center-system`;
- network/DHCP root helpers повторно валидируют pending requests;
- рабочая RSA signing pair сформирована; в GitHub хранится только public key;
- updater исправлен для разных форматов строки `APP_VERSION`, rollback защищён root-only;
- DHCP получил dotted IPv4 netmask, atomic apply/rollback и отдельный `control-center-dhcp-server.service`;
- внешний существующий `dnsmasq` не захватывается и не удаляется Control Center;
- WAN chart одновременно отображает RX/TX, форма WAN/LAN восстанавливает saved state;
- Web UI переведён с Flask development server на Gunicorn `wsgi:app`;
- добавлены CSP/nosniff/frame protection, same-origin browser writes и request-size limit;
- динамический HTML экранируется, JSON writes атомарны для нескольких workers;
- APT-операции сериализованы общим `/run/control-center-apt.lock`;
- OS updater использует `upgrade --with-new-pkgs` и сообщает `reboot_required`;
- `uninstall.sh` покрывает все компоненты и корректно сохраняет service identity при `--keep-data`;
- публичный сайт и документация синхронизированы с 1.0.5;
- public `/install.sh` получил `Cache-Control: no-store`;
- добавлены GitHub Actions validation workflows и `scripts/acceptance-1.0.5.sh`.

Полный отчёт: `docs/AUDIT-1.0.5.md`.

## Известное ограничение

В 1.0.5 отсутствует полноценная встроенная аутентификация Web UI. TCP/8080 должен быть доступен только из доверенной административной сети/VPN/firewall. Same-origin и CSP не заменяют authentication/authorization.
