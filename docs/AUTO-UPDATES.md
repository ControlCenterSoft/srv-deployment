# Обновления SRV Control Center с GitHub

SRV Control Center использует `main` репозитория как единственный production-канал. Updater сравнивает product release, а не просто SHA последнего commit.

## Настройка

Конфигуратор:

```text
/usr/local/sbin/srvcc-configure-auto-updates
```

Пример автоматического режима:

```bash
sudo /usr/local/sbin/srvcc-configure-auto-updates \
  --repo https://github.com/filosoff31/srv-deployment.git \
  --mode automatic \
  --interval-minutes 10
```

Ручной режим:

```bash
sudo /usr/local/sbin/srvcc-configure-auto-updates \
  --repo https://github.com/filosoff31/srv-deployment.git \
  --mode manual \
  --interval-minutes 10
```

Интервал проверки — 1–1440 минут. В ручном режиме timer отключён; значение интервала сохраняется и используется после переключения обратно в автоматический режим.

## Проверка и установка — разные операции

Начиная с 1.1.0 updater имеет две явные команды:

```bash
sudo /usr/local/sbin/srvcc-github-agent check --actor root
sudo /usr/local/sbin/srvcc-github-agent apply --actor root
```

`check` выполняет fetch `origin/main`, читает `deployment.json`, вычисляет fingerprint активного product release и записывает `github-update-status.json`. Никакие файлы Control Center и системные параметры при этом не применяются.

`apply` повторяет проверку и, только если fingerprint активного product release отличается от установленного, запускает deployment. В автоматическом режиме systemd timer вызывает именно `apply --actor system`.

## Backup before update

Если в `/var/lib/srv-control/backup-config.json` включено:

```json
{
  "backup_before_update": true
}
```

то перед `apply` updater обязан успешно создать резервную копию через `/usr/local/libexec/srv-control-backup`. Ошибка резервного копирования блокирует обновление; product release не применяется.

Резервная копия содержит БД Control Center, его state/config и allowlist системных файлов, изменяемых Control Center. Метаданные сохраняют actor, release, дату, размер и SHA-256 архива.

## Fingerprint и защита от повторного apply

Fingerprint строится из:

- `release_id`;
- `release_version`;
- blob `deployment.json`;
- Git tree активного `release_path`.

Updater отдельно хранит:

```text
/var/lib/srvcc-agent/last-deployed-sha
/var/lib/srvcc-agent/last-seen-sha
/var/lib/srvcc-agent/last-release-fingerprint
/var/lib/srv-control/github-update-config.json
/var/lib/srv-control/github-update-status.json
```

Если изменились только README, документация или другие файлы вне активного product release, application apply не запускается.

При установке самого нового updater поверх уже установленного того же product release используется adoption-проверка: текущий release ID/version и Git tree должны совпасть с `origin/main`. Только после этого новый fingerprint принимается без повторного развёртывания.

## Web UI 1.1.0

На странице «Система» администратор сервера может изменить GitHub source, выбрать ручной или автоматический режим и период проверки. В ручном режиме доступна кнопка «Проверить обновления». Кнопка «Обновить» становится активной только когда последняя проверка сообщает о новом product release.

Эти операции выполняются root-owned system agent; web-процесс не запускает Git/apt/systemctl с root-правами напрямую.

## Диагностика

```bash
systemctl status srvcc-github-agent.timer --no-pager -l
systemctl status srvcc-github-agent.service --no-pager -l
cat /var/lib/srv-control/github-update-config.json
cat /var/lib/srv-control/github-update-status.json
tail -n 100 /var/log/srvcc-agent.log
```

Стандартная цепочка применения:

```text
check → backup (если включён) → preflight → apply → acceptance → healthcheck
```

При ошибке release orchestrator запускает rollback, а новый fingerprint не принимается как успешно установленный.
