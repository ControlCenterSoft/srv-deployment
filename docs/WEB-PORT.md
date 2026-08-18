# Web-панель, стандартный порт и SSL — Control Center 1.0.9

## Режимы

В **Настройки → Web-панель** доступны два переключателя и пользовательский порт:

- **Стандартный порт**;
- **Включить SSL / HTTPS**;
- пользовательский порт `1024–65535`.

Логика стандартного режима:

```text
HTTP  -> 80
HTTPS -> 443
```

Если стандартный режим выключен, выбранный пользовательский порт используется и для HTTP, и для HTTPS.

## Runtime

Gunicorn запускается через:

```text
/usr/local/sbin/control-center-web-run
```

Wrapper читает `/etc/control-center/web.env` и добавляет `--certfile/--keyfile` только при включённом SSL.

Для bind на 80/443 Web-служба получает только:

```text
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
```

Control Center по-прежнему работает от пользователя `control-center`, а не root.

## SSL 1.0.9

При первом включении HTTPS root helper создаёт локальный self-signed сертификат:

```text
/etc/control-center/tls/server.crt
/etc/control-center/tls/server.key
```

Ключ: `root:control-center 0640`. Сертификат включает hostname, localhost и доступные IPv4 адреса сервера в SAN.

Поскольку сертификат самоподписанный, браузер может показывать предупреждение доверия. Автоматический ACME/Let's Encrypt и импорт пользовательского сертификата не входят в 1.0.9.

## Применение и rollback

```text
POST /api/settings/web
  -> /var/lib/control-center/web-pending.json
  -> control-center-web-apply.path
  -> control-center-web-apply.service
  -> /usr/local/sbin/control-center-web-apply
```

Helper проверяет запрос и порт, при необходимости генерирует certificate/key, сохраняет env/config/PostgreSQL settings, перезапускает Web service и выполняет HTTP или HTTPS health-check. При любой ошибке возвращаются предыдущие порт, SSL mode и standard-port mode.

## PostgreSQL settings

```text
web.port
web.ssl_enabled
web.standard_port
```

## Диагностика

```bash
sudo cat /etc/control-center/web.env
sudo cat /var/lib/control-center-system/web-config.json 2>/dev/null || true
sudo cat /var/lib/control-center-system/web-status.json 2>/dev/null || true
systemctl cat control-center
systemctl status control-center-web-apply.path --no-pager
journalctl -u control-center-web-apply.service -n 150 --no-pager
ss -ltnp | grep -E ':80 |:443 |gunicorn'
```

При HTTPS:

```bash
openssl x509 -in /etc/control-center/tls/server.crt -noout -subject -issuer -dates -ext subjectAltName
```

Control Center не изменяет внешний firewall/NAT автоматически. Перед удалённым переходом на другой порт убедитесь, что он разрешён сетевой политикой.
