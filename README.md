# Control Center 1.0.11

Control Center — web-панель управления Linux-сервером. Release candidate: **1.0.11**, build **20260819.5**.

## Главное в 1.0.11

### Маркет и зависимости

В Маркете активированы:

- **Домен** — Samba Active Directory Domain Controller;
- **DNS** — standalone Unbound либо Samba Internal DNS внутри Домена;
- **Сетевое хранилище** — standalone Samba либо доменный SMB-ресурс;
- существующий DHCP дополнен клиентами и IP-бронированиями.

Зависимости Домена строгие:

```text
Домен → DNS      (обязательно)
Домен → Storage  (обязательно)
```

DNS и Сетевое хранилище можно устанавливать отдельно. Если их нет, мастер Домена активирует их автоматически. Если они уже работают standalone, их состояние сохраняется и они переводятся в доменный режим; после удаления Домена прежнее standalone-состояние восстанавливается.

Пункты DNS / Сетевое хранилище / Домен появляются в меню только после установки соответствующей службы и скрываются после штатного удаления.

## Авторизация Control Center

Портал 1.0.11 требует авторизацию:

- **Локальная** — Linux/PAM;
- **Доменная** — после активации Домена.

Root через Web запрещён. Локальная bootstrap-группа администраторов: `control-center-admins`. Если при чистой установке не найден локальный администратор с паролем, installer создаёт отдельного `controladmin` без SSH-shell и показывает случайный пароль один раз.

Проверка паролей выполняется отдельным root-процессом `control-center-authd` через Unix socket. Web-процесс `control-center` не получает доступ к `/etc/shadow` или привилегированному Winbind socket.

Текущий authorization bootstrap:

- `admin` — чтение и изменения;
- `viewer` — чтение;
- доменная группа `Control Center Admins` → `admin`.

PostgreSQL migration `005` уже содержит `rbac_roles` и `rbac_bindings` для следующего полноценного RBAC lifecycle.

## Первоначальная настройка Домена

Мастер проводит по шагам:

1. readiness и выбор Static LAN/WAN;
2. DNS Realm и NetBIOS domain;
3. DNS forwarder и обязательные зависимости DNS/Storage;
4. пароль Domain Administrator и локальный one-time approval;
5. итоговая проверка и создание.

Перед созданием:

```bash
sudo control-center-samba-approve
```

Код действует 10 минут и используется один раз. Administrator password находится только в `/run` до чтения root worker, не сохраняется в PostgreSQL/persistent state и не передаётся через `--adminpass`.

Создаются Samba Internal DNS, Kerberos, LDAP, SYSVOL/NETLOGON, signed NTP/chrony и доменное SMB-хранилище.

## Защита активного контроллера

После активации Домена обычными настройками запрещено:

- переименовывать DC;
- выключать его WAN/LAN роль;
- переводить интерфейс на DHCP;
- менять interface/IP/prefix;
- удалять DNS;
- удалять Сетевое хранилище;
- выдавать доменным DHCP-клиентам внешний DNS вместо AD DNS.

Автоматический takeover внешнего, ранее не управляемого Samba AD-DC запрещён.

## DNS

Standalone DNS использует Unbound и Static IPv4. В доменном режиме provider автоматически меняется на Samba Internal DNS. Внешнее разрешение выполняется через DNS forwarder.

Удалить DNS при активном Домене нельзя.

## Сетевое хранилище

Standalone Storage использует Samba и сохраняет пользовательские данные в `/srv/control-center/storage/public`. При создании Домена ресурс переводится в доменный SMB с доступом Domain Users/Domain Admins.

Удаление самой службы не удаляет пользовательские файлы.

## DHCP

Раздел DHCP показывает leases + reservations, состояние ONLINE/OFFLINE, MAC, hostname, текущий и забронированный IP. Можно:

- забронировать текущий IP;
- изменить забронированный IP;
- снять бронь.

Backend проверяет подсеть, gateway/network/broadcast, дубли, активную аренду другого MAC и IP контроллера домена. Изменение вступает в силу после DHCP renew клиента.

## Удаление Домена и cleanup-audit

Удаление Домена — отдельная защищённая операция. Требуется:

```bash
sudo control-center-samba-approve --remove
```

и подтверждение в UI. Автоматическое удаление разрешается только если локально доказано, что DC единственный.

Перед destruction создаётся root-only recovery bundle. После удаления Control Center:

- восстанавливает состояние до Domain provisioning;
- возвращает standalone DNS/Storage, если они существовали;
- сравнивает детерминированные pre-state fingerprints;
- проверяет удаление generated `sam.ldb` и SYSVOL;
- сохраняет cleanup-audit и recovery backup.

DNS и Storage также выполняют cleanup-audit при собственном удалении.

## Установка

```bash
git clone --depth 1 --branch release/1.0.11 https://github.com/filosoff31/srv-deployment.git
cd srv-deployment
sudo bash install/install.sh
```

Чистая установка стартует на `http://SERVER_IP:8080`, если ранее не настроены другой порт/HTTPS.

## Проверка

```bash
sudo bash scripts/acceptance-1.0.11.sh
```

Ожидаемо:

```text
1.0.11
20260819.5
PostgreSQL migration 005
ACCEPTANCE 1.0.11: PASSED
```

Для disposable integration runner используется `scripts/runtime-acceptance-1.0.11.sh`: он выполняет полный цикл standalone DNS/Storage → Domain → domain auth/DHCP → Domain removal → восстановление → DNS/Storage removal.

## Uninstall панели

Полный uninstall с удалением application state блокируется, пока установлены управляемые Domain/DNS/Storage. Сначала службы нужно удалить штатно через Маркет, чтобы выполнились cleanup-audits.

`--keep-data` позволяет удалить сам портал/runtime, сохранив роли и метаданные.
