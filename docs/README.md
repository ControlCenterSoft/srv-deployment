# Документация Control Center 1.0.9

## Правовые и продуктовые документы

- [EULA-RU.md](EULA-RU.md) — лицензионное соглашение Home / Professional.
- [PRODUCT-EDITIONS.md](PRODUCT-EDITIONS.md) — редакции и licensing.
- [UPDATE-LIFECYCLE-POLICY-RU.md](UPDATE-LIFECYCLE-POLICY-RU.md) — правила версионирования и жизненного цикла.
- [RELEASE-HISTORY.md](RELEASE-HISTORY.md) — история production-релизов.

## Эксплуатационная документация

- [INSTALL.md](INSTALL.md) — установка, обновление и удаление.
- [MARKET.md](MARKET.md) — статусы сервисов и lifecycle.
- [POSTGRESQL.md](POSTGRESQL.md) — PostgreSQL application data layer и migrations.
- [WEB-PORT.md](WEB-PORT.md) — стандартные порты 80/443, пользовательский порт, SSL и rollback.
- [SAMBA-AD-DC.md](SAMBA-AD-DC.md) — схема и preflight будущего Samba AD-DC.
- [UPDATE.md](UPDATE.md) — обновления Control Center.
- [OS_UPDATES.md](OS_UPDATES.md) — обновление Ubuntu/Debian пакетов.
- [LICENSING.md](LICENSING.md) — Home/Professional и активация.
- [NETWORK.md](NETWORK.md) — WAN/LAN и live network inventory.
- [DHCP.md](DHCP.md) — DHCP Server, options и config check.
- [NOTIFICATIONS.md](NOTIFICATIONS.md) — центр уведомлений.
- [UI.md](UI.md) — dashboard, пагинация и mobile UI.
- [SECURITY.md](SECURITY.md) — модель привилегий и ограничения.
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) — диагностика.
- [../releases/1.0.9/README.md](../releases/1.0.9/README.md) — release notes текущего релиза.

## Быстрая проверка

```bash
cat /opt/control-center/VERSION
cat /opt/control-center/BUILD
sudo bash scripts/acceptance-1.0.9.sh
```

PostgreSQL хранит application state. Netplan/systemd/dnsmasq остаются фактическими источниками системной конфигурации.

Встроенная Web-аутентификация ещё не реализована; административный Web-порт должен быть ограничен доверенной LAN/VPN/firewall.
