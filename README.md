# Control Center

`filosoff31/srv-deployment` — production-репозиторий **Control Center**, web-платформы централизованного управления домашней/серверной инфраструктурой. Репозиторий содержит production pointer, frozen product-релизы, installer/updater, эксплуатационную документацию и исторические материалы.

## Production сейчас

Единственный источник опубликованного production target — [`deployment.json`](deployment.json). Сейчас он указывает на **Control Center 2.1.0** (`releases/2.1.0`). Конкретный сервер может временно иметь другую версию после failed deployment/rollback; фактическое состояние такого сервера определяется его `server-state`/`release.json`.

Опубликованные `releases/<version>` **frozen**: исправления выпускаются новой версией, старый payload не редактируется.

## Возможности текущей линии

Control Center объединяет FastAPI/PostgreSQL web-интерфейс и health/dashboard, системную PAM/NSS-аутентификацию с Samba/winbind для доменных identities, RBAC, защищённые privileged actions, product/OS updates, backup/restore, Samba AD и shares, Minecraft Bedrock, AdGuard VPN, network/system diagnostics и перенесённые DHCP/PXE contracts там, где они реализованы frozen release.

В 2.1.0 Minecraft runtime нормализован в один канонический systemd service с сохранением мира/настроек и транзакционным rollback. Точный scope версии определяется её manifest/acceptance, а не roadmap.

## Установка

```bash
curl -fL -o install.sh \
  https://raw.githubusercontent.com/filosoff31/srv-deployment/main/install.sh
chmod +x install.sh
sudo ./install.sh
```

Installer читает активный `deployment.json` и разворачивает опубликованный self-contained release. Перед установкой используйте [`docs/INSTALL.md`](docs/INSTALL.md).

## Первый вход и доступ

Современная production-линия **не использует отдельный bootstrap web-пароль Control Center**. Интерактивный вход выполняется существующей локальной Linux либо доменной Samba/winbind учётной записью через NSS/PAM. После успешной authentication применяется RBAC Control Center.

Kerberos/SPNEGO — дополнительный SSO-механизм и должен считаться активным только при корректно настроенных сервере, DNS/времени, keytab и клиенте. Отказ SSO не меняет основной PAM/NSS login contract. Инструкции ранних 0.x про `admin-bootstrap.txt` — исторические.

## Обновления

`main` — production update channel. Product deployment использует транзакцию:

```text
preflight → safety backup → apply → acceptance → healthcheck
                                      ↘ failure → rollback
```

Updater ориентируется на release metadata/fingerprint; documentation-only commit не должен повторно применять неизменившийся product release. Обслуживание пакетов ОС — отдельный механизм.

## Документация

Начинайте с:

- [`docs/PRODUCT-MANUAL-RU.md`](docs/PRODUCT-MANUAL-RU.md) — каноническое русскоязычное руководство пользователя и администратора;
- [`docs/README.md`](docs/README.md) — индекс и правила актуальности;
- [`docs/SYSTEM-ADMIN.md`](docs/SYSTEM-ADMIN.md) — authentication/RBAC и privileged administration;
- [`docs/AUTO-UPDATES.md`](docs/AUTO-UPDATES.md) — product updater;
- [`docs/DEPLOYMENT-RELIABILITY.md`](docs/DEPLOYMENT-RELIABILITY.md) — deployment/rollback;
- [`docs/RELEASE-HISTORY.md`](docs/RELEASE-HISTORY.md) — опубликованная история;
- [`docs/ROADMAP.md`](docs/ROADMAP.md) — будущий scope, не описание production.

Release-specific incident/scope документы сохраняются как **исторические**. Если они противоречат `deployment.json`, frozen active release или каноническому руководству, они не являются текущей эксплуатационной инструкцией.

## Безопасность и release discipline

Web-процесс не должен выполнять произвольные root-команды: привилегированные действия проходят session/CSRF, RBAC и allowlisted root-owned helpers/system services. Пароли, session keys, Kerberos key material, API tokens и backup contents не публикуются в Git/diagnostics.

Документация обновляется вместе с каждым релизом, но frozen release payload не переписывается ради исправления текста.