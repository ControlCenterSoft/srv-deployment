# Документация Control Center 1.0.8

## Правовые и продуктовые документы

- [EULA-RU.md](EULA-RU.md) — лицензионное соглашение Home / Professional.
- [PRODUCT-EDITIONS.md](PRODUCT-EDITIONS.md) — редакции и licensing.
- [UPDATE-LIFECYCLE-POLICY-RU.md](UPDATE-LIFECYCLE-POLICY-RU.md) — правила версионирования и жизненного цикла.
- [RELEASE-HISTORY.md](RELEASE-HISTORY.md) — история production-релизов.

## Эксплуатационная документация

- [INSTALL.md](INSTALL.md) — установка, обновление и удаление.
- [MARKET.md](MARKET.md) — постоянные статусы сервисов, protected event history и lifecycle.
- [POSTGRESQL.md](POSTGRESQL.md) — PostgreSQL application data layer, migrations и подготовка к Professional Cluster.
- [WEB-PORT.md](WEB-PORT.md) — изменение TCP-порта Web UI, apply/rollback и диагностика.
- [UPDATE.md](UPDATE.md) — автоматическая и ручная установка обновлений Control Center.
- [OS_UPDATES.md](OS_UPDATES.md) — обновление Ubuntu/Debian пакетов.
- [LICENSING.md](LICENSING.md) — Home/Professional и активация.
- [NETWORK.md](NETWORK.md) — WAN/LAN и live network inventory.
- [DHCP.md](DHCP.md) — DHCP Server, установка, recovery, дополнительные options и config check.
- [NOTIFICATIONS.md](NOTIFICATIONS.md) — центр уведомлений и PostgreSQL read/unread.
- [UI.md](UI.md) — интерфейс и мобильная верстка.
- [SECURITY.md](SECURITY.md) — модель привилегий и ограничения.
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) — диагностика.
- [../releases/1.0.8/README.md](../releases/1.0.8/README.md) — release notes текущего релиза.

## Архитектура данных

PostgreSQL хранит application state, историю, настройки и события. Netplan/systemd/dnsmasq остаются фактическими источниками системной конфигурации.

## Быстрая проверка 1.0.8

```bash
cat /opt/control-center/VERSION
cat /opt/control-center/BUILD
PORT=$(sed -n 's/^CONTROL_CENTER_PORT=//p' /etc/control-center/web.env)
curl -fsS "http://127.0.0.1:${PORT}/api/health" | python3 -m json.tool
curl -fsS "http://127.0.0.1:${PORT}/api/market" | python3 -m json.tool
curl -fsS "http://127.0.0.1:${PORT}/api/settings/update/check" | python3 -m json.tool
sudo bash scripts/acceptance-1.0.8.sh
```

## Ограничение

Встроенная Web-аутентификация ещё не реализована. Административный порт должен быть ограничен доверенной LAN/VPN/firewall.
