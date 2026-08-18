# Документация Control Center 1.0.7

## Правовые и продуктовые документы

- [EULA-RU.md](EULA-RU.md) — лицензионное соглашение Home / Professional.
- [PRODUCT-EDITIONS.md](PRODUCT-EDITIONS.md) — каноническое описание редакций и licensing.
- [UPDATE-LIFECYCLE-POLICY-RU.md](UPDATE-LIFECYCLE-POLICY-RU.md) — правила версионирования и жизненного цикла.
- [RELEASE-HISTORY.md](RELEASE-HISTORY.md) — история production-релизов.

## Эксплуатационная документация

- [INSTALL.md](INSTALL.md) — установка, обновление существующей установки и удаление.
- [POSTGRESQL.md](POSTGRESQL.md) — PostgreSQL application data layer, migrations и подготовка к Professional Cluster.
- [WEB-PORT.md](WEB-PORT.md) — изменение TCP-порта Web UI, apply/rollback и диагностика.
- [UPDATE.md](UPDATE.md) — обновление самого Control Center.
- [OS_UPDATES.md](OS_UPDATES.md) — обновление Ubuntu/Debian пакетов.
- [LICENSING.md](LICENSING.md) — техническая модель Home/Professional и активации.
- [NETWORK.md](NETWORK.md) — WAN/LAN, перечень интерфейсов и источники live-данных.
- [DHCP.md](DHCP.md) — DHCP Server, дополнительные параметры, статус и проверка конфигурации.
- [NOTIFICATIONS.md](NOTIFICATIONS.md) — общий центр уведомлений; начиная с 1.0.7 read/unread хранится в PostgreSQL.
- [UI.md](UI.md) — типографика, SVG-ярлычки меню и мобильная верстка.
- [SECURITY.md](SECURITY.md) — модель привилегий и известные ограничения.
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) — диагностика.
- [AUDIT-1.0.5.md](AUDIT-1.0.5.md) — базовый security-аудит архитектуры protected state.
- [../releases/1.0.7/README.md](../releases/1.0.7/README.md) — изменения текущего релиза.

## Архитектура данных 1.0.7

PostgreSQL хранит application-level данные, историю и настройки. Netplan/systemd/dnsmasq остаются фактическими источниками системной конфигурации.

Локальная БД `control_center` подключается по Unix socket от Linux-пользователя `control-center`; приложение не содержит пароля PostgreSQL и не включает сетевой PostgreSQL listener.

## Версионирование

Control Center использует проектную схему `X.Y.Z`, но не заявляет строгую совместимость с Semantic Versioning. `X` обозначает major-поколение, `Y` — крупную функциональную линию, `Z` — последовательный production-релиз внутри неё. Фактический состав релиза определяется release notes и manifest.

## Быстрая проверка 1.0.7

```bash
cat /opt/control-center/VERSION
cat /opt/control-center/BUILD
PORT=$(sed -n 's/^CONTROL_CENTER_PORT=//p' /etc/control-center/web.env)
curl -fsS "http://127.0.0.1:${PORT}/api/health" | python3 -m json.tool
curl -fsS "http://127.0.0.1:${PORT}/api/database/status" | python3 -m json.tool
sudo bash scripts/acceptance-1.0.7.sh
```

## Ограничение

Встроенная Web-аутентификация ещё не реализована. Настраиваемый административный порт должен быть ограничен доверенной LAN/VPN/firewall.
