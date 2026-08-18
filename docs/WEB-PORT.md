# Порт Web-панели Control Center 1.0.7

## Настройка

В **Настройки → Web-панель** можно изменить TCP-порт административного интерфейса.

Допустимый диапазон:

```text
1024–65535
```

Значение по умолчанию: `8080`.

## Применение

Web API не редактирует systemd от root. Он проверяет запрос и создаёт:

```text
/var/lib/control-center/web-pending.json
```

Далее:

```text
control-center-web-apply.path
  -> control-center-web-apply.service
  -> /usr/local/sbin/control-center-web-apply
```

Привилегированный helper:

1. повторно проверяет диапазон порта;
2. проверяет, что новый порт можно bind на `0.0.0.0`;
3. сохраняет `/etc/control-center/web.env`;
4. синхронизирует `web.port` в PostgreSQL;
5. перезапускает `control-center.service`;
6. выполняет `/api/health` на новом порту;
7. при ошибке возвращает предыдущий env/DB port и перезапускает старую конфигурацию.

Applied status:

```text
/var/lib/control-center-system/web-status.json
/var/lib/control-center-system/web-config.json
```

Application setting:

```text
control_center.settings -> key = web.port
```

## Важно

После успешного изменения текущее соединение браузера обычно прерывается. Если адрес сервера `192.168.10.1` и порт изменён на `8443`, новый URL при текущем HTTP runtime будет:

```text
http://192.168.10.1:8443
```

Смена порта **не включает HTTPS** и не является средством аутентификации. В 1.0.7 Web UI по-прежнему должен быть ограничен административной LAN/VPN/firewall.

Если на сервере используется внешний firewall, reverse proxy или ACL, их правила Control Center 1.0.7 автоматически не переписывает. Убедитесь, что новый порт разрешён до удалённой смены, иначе Web UI может стать недоступен с вашей рабочей станции, даже если локальный health-check проходит.

## Хранение при обновлении

Установщик сначала читает существующий `/etc/control-center/web.env`. Поэтому update/reinstall сохраняет уже выбранный порт. Если env отсутствует, используется PostgreSQL `web.port`, затем fallback `8080`.

Updater также делает backup `web.env` для rollback приложения.

## Диагностика

```bash
sudo cat /etc/control-center/web.env
sudo cat /var/lib/control-center-system/web-config.json 2>/dev/null || true
sudo cat /var/lib/control-center-system/web-status.json 2>/dev/null || true
systemctl status control-center-web-apply.path --no-pager
journalctl -u control-center-web-apply.service -n 100 --no-pager
systemctl cat control-center
ss -ltnp | grep gunicorn
```

Текущие настройки через API:

```bash
PORT=$(sed -n 's/^CONTROL_CENTER_PORT=//p' /etc/control-center/web.env)
curl -fsS "http://127.0.0.1:${PORT}/api/settings/web" | python3 -m json.tool
```
