# Web-панель, стандартный порт и SSL — Control Center 1.0.10

## Режимы

В **Настройки → Web-панель**:

- **Стандартный порт**;
- **Включить SSL / HTTPS**;
- пользовательский порт `1024–65535`.

Стандартный режим:

```text
HTTP  -> 80
HTTPS -> 443
```

При выключенном стандартном режиме пользовательский порт применяется к HTTP или HTTPS.

## Исправление 1.0.10

В 1.0.9 применение порта/SSL зависело от PostgreSQL. Если БД была недоступна, POST `/api/settings/web` мог вернуть 503, а privileged helper откатывал runtime после ошибки DB sync.

В 1.0.10 эта зависимость удалена.

Источники фактического Web runtime:

```text
/etc/control-center/web.env
/var/lib/control-center-system/web-config.json
```

PostgreSQL хранит синхронизированную копию настроек, но **не блокирует изменение Web runtime**.

Алгоритм 1.0.10:

1. Web API валидирует режим и целевой порт;
2. создаёт `/var/lib/control-center/web-pending.json`;
3. root helper проверяет занятость порта;
4. при HTTPS создаёт/проверяет certificate/key;
5. пишет `web.env` и защищённый `web-config.json`;
6. best-effort синхронизирует PostgreSQL;
7. перезапускает Gunicorn;
8. выполняет HTTP/HTTPS health-check;
9. при runtime failure возвращает предыдущие параметры;
10. при недоступной PostgreSQL runtime остаётся применённым, а в колокольчик попадает предупреждение.

## Gunicorn и привилегированные порты

Web-служба работает от пользователя `control-center`.

Для bind на 80/443 systemd выдаёт только:

```text
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
```

Root-права Flask/Gunicorn не получает.

Gunicorn запускается через:

```text
/usr/local/sbin/control-center-web-run
```

Неиспользуемый Gunicorn control socket отключён, чтобы hardened service не пытался писать в read-only `/opt/control-center`.

## SSL

При первом включении HTTPS root helper создаёт self-signed сертификат:

```text
/etc/control-center/tls/server.crt
/etc/control-center/tls/server.key
```

Private key:

```text
root:control-center 0640
```

Сертификат содержит:

- короткое hostname в CN;
- полный FQDN в SAN;
- `localhost`;
- `127.0.0.1`;
- обнаруженные IPv4 сервера.

Это устраняет ограничение длины X.509 Common Name для длинных cloud FQDN.

Браузер может показывать предупреждение доверия для self-signed сертификата. ACME/Let's Encrypt и импорт пользовательского сертификата остаются отдельным этапом.

## API

```text
GET  /api/settings/web
POST /api/settings/web
```

GET возвращает одновременно:

- requested/file config;
- фактический runtime port/SSL;
- standard mode;
- certificate mode;
- состояние helper;
- признак `database_synced`;
- DB error при degraded PostgreSQL.

## Диагностика

```bash
sudo cat /etc/control-center/web.env
sudo cat /var/lib/control-center-system/web-config.json 2>/dev/null || true
sudo cat /var/lib/control-center-system/web-status.json 2>/dev/null || true
systemctl cat control-center
systemctl status control-center-web-apply.path --no-pager
journalctl -u control-center-web-apply.service -n 150 --no-pager
journalctl -u control-center -n 150 --no-pager
ss -ltnp | grep -E ':80 |:443 |:8080 |:8443 |gunicorn'
```

Проверка сертификата:

```bash
openssl x509 -in /etc/control-center/tls/server.crt -noout \
  -subject -issuer -dates -ext subjectAltName
```

Control Center не изменяет внешний firewall/NAT. После смены порта браузер нужно открыть по новому адресу.
