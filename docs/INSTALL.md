# Установка Control Center 1.0.11

Build: **20260819.5**.

## Установка / обновление

```bash
git clone --depth 1 --branch release/1.0.11 https://github.com/filosoff31/srv-deployment.git
cd srv-deployment
sudo bash install/install.sh
```

Installer:

1. обновляет Control Center payload;
2. применяет PostgreSQL migrations до **005**;
3. сохраняет Web port/SSL settings;
4. включает Local/Domain auth architecture и `control-center-authd`;
5. устанавливает lifecycle workers Domain/DNS/Storage/DHCP reservations;
6. создаёт runtime directories `/run/control-center`, `/run/control-center-root`, `/run/control-center-auth`;
7. включает systemd path watchers;
8. выполняет health и migration checks.

## Первый локальный вход

Installer формирует группу:

```text
control-center-admins
```

Существующие обычные пользователи с `sudo`/`wheel` добавляются в неё. Root Web login запрещён.

Если подходящего пользователя с паролем нет, installer создаёт `controladmin` с shell `/usr/sbin/nologin` и выводит случайный пароль **один раз**. Сменить его:

```bash
sudo passwd controladmin
```

## Проверка установки

```bash
cat /opt/control-center/VERSION
cat /opt/control-center/BUILD
sudo -u control-center psql -d control_center -Atqc \
  "select version from control_center.schema_migrations order by version desc limit 1"
sudo bash scripts/acceptance-1.0.11.sh
```

Ожидаемо:

```text
1.0.11
20260819.5
005
ACCEPTANCE 1.0.11: PASSED
```

## Первоначальная настройка Домена

1. В **Сети** настройте Static IPv4 для LAN или WAN. LAN предпочтителен.
2. При необходимости заранее установите DNS и/или Сетевое хранилище из Маркета. Это необязательно: Домен установит зависимости сам.
3. В Маркете выберите **Домен → Установить**.
4. Пройдите мастер Realm / NetBIOS / network role / DNS forwarder / dependencies.
5. На сервере получите one-time code:

```bash
sudo control-center-samba-approve
```

6. Введите пароль Domain Administrator, повтор пароля и код.
7. Дождитесь итогового события в колокольчике.

Если standalone DNS/Storage существовали, они сохраняются и переводятся в domain mode.

## Доменная авторизация

После успешного provisioning на странице входа становится доступен режим **Доменная**. Bootstrap administrative group:

```text
Control Center Admins
```

Domain Administrator добавляется в неё автоматически. Остальные доменные пользователи по умолчанию имеют viewer-доступ до развития RBAC.

## Удаление Домена

Удаление выполняется из раздела Домена/Маркета, а не uninstall-скриптом.

Перед удалением:

```bash
sudo control-center-samba-approve --remove
```

В UI требуется отдельная фраза подтверждения. Операция разрешена только для единственного DC.

Перед destruction создаётся recovery backup, затем восстанавливается pre-domain state и выполняется fingerprint cleanup-audit.

## DNS / Storage removal

DNS и Storage нельзя удалять при активном Домене. После удаления Домена они могут быть удалены отдельно из Маркета; каждая операция выполняет cleanup-audit.

Storage service removal сохраняет пользовательские данные.

## Systemd

Основные units:

```text
control-center.service
control-center-authd.service
control-center-samba-apply.path/service
control-center-domain-destroy.path/service
control-center-dns-apply.path/service
control-center-storage-apply.path/service
control-center-dhcp-reservations-apply.path/service
```

## Uninstall панели

Если Domain/DNS/Storage установлены, обычный uninstall с удалением application state блокируется. Сначала удалите роли штатно через Маркет.

Сохранить роли/данные и удалить только панель/runtime:

```bash
sudo bash install/uninstall.sh --keep-data
```
