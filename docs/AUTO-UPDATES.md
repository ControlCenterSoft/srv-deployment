# Автоматические обновления SRV Control Center

Поддерживаемая миграция: **0.8.0 и новее**.

## Установка/ремонт updater

```bash
curl -fL -o /tmp/srvcc-configure-auto-updates.sh \
  https://raw.githubusercontent.com/filosoff31/srv-deployment/main/bootstrap/configure-auto-updates.sh

sudo bash /tmp/srvcc-configure-auto-updates.sh \
  --mode automatic \
  --interval-minutes 5 \
  --check-now
```

Скрипт:

- проверяет установленную версию Control Center;
- не работает с версиями ниже 0.8.0;
- создаёт/ремонтирует `srvcc-github-agent.service` и `srvcc-github-agent.timer`;
- сохраняет источник, режим и интервал;
- разделяет `last-seen-sha` и `last-deployed-sha`;
- хранит fingerprint активного product-релиза;
- не переустанавливает приложение при изменении только README/документации/deployment helper;
- сохраняет совместимость с существующим `server-state` publisher, если он установлен.

## Режимы

Автоматический:

```bash
sudo /usr/local/sbin/srvcc-configure-auto-updates \
  --mode automatic \
  --interval-minutes 10
```

Ручной:

```bash
sudo /usr/local/sbin/srvcc-configure-auto-updates \
  --mode manual
sudo systemctl start srvcc-github-agent.service
```

Интервал автоматической проверки — от 1 до 1440 минут.

## Диагностика

```bash
systemctl status srvcc-github-agent.timer
systemctl status srvcc-github-agent.service
cat /var/lib/srv-control/github-update-config.json
cat /var/lib/srv-control/github-update-status.json
tail -n 100 /var/log/srvcc-agent.log
```

## Алгоритм принятия решения

Updater получает `origin/main`, читает активный `deployment.json` и вычисляет fingerprint из:

- `release_id`;
- `release_version`;
- blob `deployment.json`;
- Git tree активного `release_path`.

Если fingerprint не изменился, новый commit только отмечается как просмотренный и product deployment не запускается.

Если fingerprint изменился, запускается стандартная цепочка:

```text
preflight → apply → acceptance → healthcheck
```

При ошибке release orchestrator выполняет rollback и новый fingerprint не принимается.
