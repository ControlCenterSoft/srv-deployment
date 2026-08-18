# История релизов Control Center

Авторитетное production-состояние определяется `../deployment.json`; подробности каждого релиза — каталогом `../releases/<version>/`.

## 1.0.7 — 18.08.2026

- PostgreSQL стал базовым application data layer;
- локальная БД `control_center`, непривилегированная роль `control-center`, Unix socket + peer authentication;
- versioned SQL migrations с checksum-контролем;
- settings, notifications/read state, audit, jobs, module inventory и service configs в PostgreSQL;
- `cluster_nodes` как архитектурный задел будущего Professional Cluster без заявления о готовом HA/replication runtime;
- настройка TCP-порта Web UI из панели;
- privileged Web-port apply с restart/health-check/rollback;
- серверная прочитанность уведомлений;
- version/build-aware updater.

## 1.0.6 — 18.08.2026

- возвращён полный перечень сетевых интерфейсов;
- WAN/LAN и DHCP загружают фактически применённые параметры;
- увеличена типографика и добавлены семантические SVG-иконки меню;
- полностью переработана мобильная верстка;
- DHCP: дополнительные numeric options, service status и config check;
- общий центр уведомлений;
- CSP без `unsafe-inline`.

## 1.0.5 — 18.08.2026

- Home / Professional;
- RSA/SHA-256 активация Professional;
- обновление ОС и пакетов;
- protected state, root-only rollback и усиление security-модели;
- Gunicorn WSGI и release validation.

## 1.0.4

- обновлённый дизайн;
- DHCP Server в Маркете;
- динамический раздел DHCP после установки модуля.

## 1.0.3

- dashboard CPU/RAM/Top-3 процессов;
- заполнение хранилищ;
- WAN RX/TX;
- настройка интервала обновлений в минутах.

## 1.0.2

- WAN/LAN;
- DHCP/Static;
- проверка сетевых параметров и Netplan apply/rollback.

## 1.0.1

- настройки Control Center;
- базовый автоматический production updater.

## 1.0.0

- старт новой линии Control Center;
- Web UI, installer, документация;
- базовые разделы Система, Сети, Маркет и RBAC.
