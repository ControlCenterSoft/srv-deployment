# Документация Control Center

## Правовые и продуктовые документы

- [EULA-RU.md](EULA-RU.md) — лицензионное соглашение с конечным пользователем Control Center Home / Professional.
- [UPDATE-LIFECYCLE-POLICY-RU.md](UPDATE-LIFECYCLE-POLICY-RU.md) — правила `X.Y.Z`, функциональных/patch-релизов и жизненного цикла 24 + 12 месяцев.
- [PRODUCT-EDITIONS.md](PRODUCT-EDITIONS.md) — каноническая архитектура Home / Professional и licensing.

## Эксплуатационная документация

- [INSTALL.md](INSTALL.md) — установка, повторная установка и удаление.
- [UPDATE.md](UPDATE.md) — обновление самого Control Center.
- [OS_UPDATES.md](OS_UPDATES.md) — обновление Ubuntu/Debian пакетов.
- [LICENSING.md](LICENSING.md) — Home, Professional и техническая модель лицензирования.
- [NETWORK.md](NETWORK.md) — WAN/LAN и сетевые настройки.
- [DHCP.md](DHCP.md) — DHCP Server.
- [SECURITY.md](SECURITY.md) — модель привилегий и ограничения безопасности.
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) — диагностика.

## Версионирование

- `X.N.x` — функциональный релиз: допускаются новые возможности и изменения существующих функций.
- `X.x.N` — patch-релиз: исправление текущей функции без добавления новых пользовательских возможностей.
- major-линия `X.x.x` — 24 месяца полных обновлений, затем 12 месяцев только security-обновлений; после 36 месяцев — EOL, если для конкретной линии не объявлен более длительный срок.

Production-состояние и конкретная текущая версия определяются `../deployment.json` и frozen manifest опубликованного релиза.
