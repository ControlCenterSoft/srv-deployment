# Control Center 1.0.5

Статус: `production`.

## Основные изменения

1. Две редакции: Home и Professional.
2. Professional activation через RSA/SHA-256 подписанную лицензию, привязанную к device ID.
3. Отображение текущей редакции и версии в Web UI.
4. Отдельные настройки обновления ОС и пакетов: manual/automatic + интервал.
5. Сохранены функции 1.0.4: новый интерфейс, DHCP в Маркете, динамическое меню DHCP.

## Исправления после полного аудита

- подтверждённая лицензия перенесена из Web-writable состояния в `/var/lib/control-center-license` (`root:root`);
- root rollback state перенесён в `/var/lib/control-center-root` (`root:root`, `0700`) и закрыт от Web service;
- network/DHCP root helpers повторно валидируют pending requests, не доверяя Web-writable JSON;
- публичный ключ заменён на ключ от реальной RSA-пары издателя, приватный ключ не хранится в GitHub;
- updater больше не зависит от точного количества пробелов в строке `APP_VERSION`;
- `APP_VERSION` в 1.0.5 совместим со старым updater 1.0.4;
- DHCP helper получил атомарное применение и rollback предыдущей конфигурации;
- DHCP gateway запрещён внутри выдаваемого диапазона;
- WAN-график одновременно рисует RX и TX;
- раздел Сети снова заполняет форму сохранёнными WAN/LAN параметрами;
- APT-операции сериализованы общим `/run/control-center-apt.lock`;
- `uninstall.sh` удаляет все services/path/timers/helpers 1.0.5;
- системное обновление использует `upgrade --with-new-pkgs`;
- документация и сайт синхронизированы с 1.0.5;
- public `/install.sh` получил `Cache-Control: no-store` для защиты от устаревшего bootstrap;
- добавлены GitHub Actions проверки release и сайта.

Полный отчёт: `docs/AUDIT-1.0.5.md`.

## Известное ограничение

В 1.0.5 отсутствует полноценная встроенная аутентификация Web UI. TCP/8080 должен быть доступен только из доверенной административной сети/VPN.
