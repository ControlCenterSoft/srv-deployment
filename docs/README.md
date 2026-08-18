# Документация Control Center 1.0.6

## Правовые и продуктовые документы

- [EULA-RU.md](EULA-RU.md) — лицензионное соглашение Home / Professional.
- [PRODUCT-EDITIONS.md](PRODUCT-EDITIONS.md) — каноническое описание редакций и licensing.
- [UPDATE-LIFECYCLE-POLICY-RU.md](UPDATE-LIFECYCLE-POLICY-RU.md) — правила версионирования и жизненного цикла.
- [RELEASE-HISTORY.md](RELEASE-HISTORY.md) — история production-релизов.

## Эксплуатационная документация

- [INSTALL.md](INSTALL.md) — установка, обновление существующей установки и удаление.
- [UPDATE.md](UPDATE.md) — обновление самого Control Center.
- [OS_UPDATES.md](OS_UPDATES.md) — обновление Ubuntu/Debian пакетов.
- [LICENSING.md](LICENSING.md) — техническая модель Home/Professional и активации.
- [NETWORK.md](NETWORK.md) — WAN/LAN, перечень интерфейсов и источники live-данных.
- [DHCP.md](DHCP.md) — DHCP Server, дополнительные параметры, статус и проверка конфигурации.
- [NOTIFICATIONS.md](NOTIFICATIONS.md) — общий центр уведомлений и логика цвета колокольчика.
- [UI.md](UI.md) — типографика, SVG-ярлычки меню и мобильная верстка.
- [SECURITY.md](SECURITY.md) — модель привилегий и известные ограничения.
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) — диагностика.
- [AUDIT-1.0.5.md](AUDIT-1.0.5.md) — базовый security-аудит архитектуры protected state.
- [../releases/1.0.6/README.md](../releases/1.0.6/README.md) — изменения текущего релиза.

## Версионирование

Control Center использует проектную схему `X.Y.Z`, но не заявляет строгую совместимость с Semantic Versioning. `X` обозначает major-поколение, `Y` — крупную функциональную линию, `Z` — последовательный production-релиз внутри неё. Фактический состав релиза определяется release notes и manifest.

## Быстрая проверка 1.0.6

```bash
cat /opt/control-center/VERSION
curl -fsS http://127.0.0.1:8080/api/health | python3 -m json.tool
sudo bash scripts/acceptance-1.0.6.sh
```

## Ограничение

Встроенная Web-аутентификация ещё не реализована. TCP/8080 должен быть ограничен доверенной административной LAN/VPN/firewall.
