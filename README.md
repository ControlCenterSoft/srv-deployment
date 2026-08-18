# Control Center

`filosoff31/srv-deployment` — production-репозиторий **Control Center**, web-платформы централизованного управления домашней/серверной инфраструктурой. Репозиторий содержит production pointer, frozen product-релизы, installer/updater, эксплуатационную документацию и исторические материалы.

## Production сейчас

Единственный источник опубликованного production target — [`deployment.json`](deployment.json). После публикации этого изменения он указывает на **Control Center 2.1.4** (`releases/2.1.4`). Конкретный сервер может временно иметь другую версию после failed deployment/rollback; фактическое состояние такого сервера определяется его `server-state`/`release.json`.

Опубликованные `releases/<version>` **frozen**: исправления выпускаются новой версией, старый payload не редактируется. Номер 2.1.3 не публиковался и не является production release.

## Возможности текущей линии

Control Center объединяет FastAPI/PostgreSQL web-интерфейс и health/dashboard, системную PAM/NSS-аутентификацию с Samba/winbind для доменных identities, RBAC, защищённые privileged actions, product/OS updates, backup/restore, Samba AD и shares, Minecraft Bedrock, AdGuard VPN, network/system diagnostics и перенесённые DHCP/PXE contracts там, где они реализованы frozen release.

В 2.1.x Minecraft runtime нормализован в один канонический systemd service, исправлен web privilege path при `NoNewPrivileges=true`, добавлен надёжный ONLINE/OFFLINE status contract. 2.1.4 дополнительно исправляет clean installation после перехода на delta patch releases.

## Установка

```bash
curl -fL -o install.sh \
  https://raw.githubusercontent.com/filosoff31/srv-deployment/main/install.sh
chmod +x install.sh
sudo ./install.sh
```

Installer читает активный `deployment.json`. Patch-релизы 2.1.x могут быть дельтами, поэтому чистая установка собирает полный application payload по `installer/install-profile.json` из frozen consolidated baseline и последовательных delta-слоёв; она не предполагает, что каталог активного patch release самодостаточен.

Успешная установка проверяет и backend health, и доступ к тому же health endpoint через фактический nginx reverse proxy. Стандартная страница `Welcome to nginx!` после `INSTALL PASS` считается ошибкой установки. Перед установкой используйте [`docs/INSTALL.md`](docs/INSTALL.md).

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
- [`docs/INSTALL.md`](docs/INSTALL.md) — clean installation и acceptance;
- [`docs/SYSTEM-ADMIN.md`](docs/SYSTEM-ADMIN.md) — authentication/RBAC и privileged administration;
- [`docs/AUTO-UPDATES.md`](docs/AUTO-UPDATES.md) — product updater;
- [`docs/DEPLOYMENT-RELIABILITY.md`](docs/DEPLOYMENT-RELIABILITY.md) — deployment/rollback;
- [`docs/RELEASE-HISTORY.md`](docs/RELEASE-HISTORY.md) — опубликованная история;
- [`docs/ROADMAP.md`](docs/ROADMAP.md) — будущий scope, не описание production;
- [`docs/2.1/RELEASE-2.1.4.md`](docs/2.1/RELEASE-2.1.4.md) — исправление clean-install/nginx regression.

Release-specific incident/scope документы сохраняются как **исторические**. Если они противоречат `deployment.json`, frozen active release или каноническому руководству, они не являются текущей эксплуатационной инструкцией.

## Безопасность и release discipline

Web-процесс не должен выполнять произвольные root-команды: привилегированные действия проходят session/CSRF, RBAC и allowlisted root-owned helpers/system services. Пароли, session keys, Kerberos key material, API tokens и backup contents не публикуются в Git/diagnostics.

Документация обновляется вместе с каждым релизом, но frozen release payload не переписывается ради исправления текста.
