# Обновления Control Center с GitHub

Control Center использует `main` репозитория как единственный production-канал. Updater сравнивает **product release fingerprint**, а не просто SHA последнего commit.

Активный release определяется `deployment.json`. На момент этой редакции production pointer указывает на 1.3.8, но инструкция намеренно не зависит от жёстко зашитого номера версии.

## Настройка

Конфигуратор:

```text
/usr/local/sbin/srvcc-configure-auto-updates
```

Автоматический режим:

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

Интервал проверки — 1–1440 минут. В manual mode timer отключён; значение интервала сохраняется для последующего возврата в automatic mode.

## Проверка и установка — разные операции

```bash
sudo /usr/local/sbin/srvcc-github-agent check --actor root
sudo /usr/local/sbin/srvcc-github-agent apply --actor root
```

`check` выполняет fetch `origin/main`, читает `deployment.json`, вычисляет fingerprint активного release и обновляет `github-update-status.json`. Приложение и system state не изменяются.

`apply` повторяет проверку и запускает deployment только когда активный product release отличается от принятого установленного fingerprint. В automatic mode systemd timer запускает `apply --actor system`.

## Product fingerprint

Fingerprint формируется из release identity и Git-объектов активного product release, включая:

- `release_id`;
- `release_version`;
- blob `deployment.json`;
- Git tree активного `release_path`.

Состояние updater хранится отдельно от application payload, включая:

```text
/var/lib/srvcc-agent/last-deployed-sha
/var/lib/srvcc-agent/last-seen-sha
/var/lib/srvcc-agent/last-release-fingerprint
/var/lib/srv-control/github-update-config.json
/var/lib/srv-control/github-update-status.json
```

Documentation-only commit или другое изменение вне активного release tree не должно вызывать повторный apply неизменившегося product release.

## Adoption существующего release

При установке нового updater поверх уже установленного того же product release допускается adoption: updater сравнивает текущие release ID/version и Git tree с `origin/main`. Только при полном совпадении fingerprint принимается без повторного deployment.

## Защита от бесконечного failed retry

Линия 1.3.x добавила suppression для ранее failed release fingerprint. Automatic updater не должен бесконечно повторять одну и ту же заведомо неуспешную transaction после каждого timer tick.

После устранения причины администратор может выполнить осознанный manual retry. Успешная transaction очищает failed-state и принимает новый fingerprint.

## Backup before update

`backup_before_update` — отдельная safety policy:

```json
{
  "backup_before_update": true
}
```

Если она включена, перед product apply updater обязан успешно создать резервную копию через `/usr/local/libexec/srv-control-backup`. Ошибка backup блокирует deployment.

Эта настройка **не равна** расписанию ежедневных резервных копий. Отключение scheduled backup не должно автоматически отключать safety backup перед update, и наоборот.

## Deployment transaction

Базовая цепочка:

```text
check → backup (если policy включена) → preflight → apply → acceptance → healthcheck
                                                     ↘ failure → rollback
```

Новый fingerprint принимается только после успешного завершения требуемой release transaction.

## Web UI

На странице «Система» администратор может настроить GitHub source, manual/automatic mode и период проверки, выполнить явную проверку и применить доступное обновление.

UI должен различать:

- состояние automatic update schedule;
- **последнюю проверку обновления** (`checked_at`);
- последний результат/успешное применение, если такая информация доступна status model;
- наличие доступного нового product release.

Эти операции выполняются через privileged system action path; web-процесс не запускает Git/systemctl/root-команды напрямую.

## Диагностика

```bash
systemctl status srvcc-github-agent.timer --no-pager -l
systemctl status srvcc-github-agent.service --no-pager -l
cat /var/lib/srv-control/github-update-config.json
cat /var/lib/srv-control/github-update-status.json
tail -n 100 /var/log/srvcc-agent.log
```

При разборе проблемы отдельно фиксируйте:

1. активный release из `deployment.json`;
2. фактически установленный release из `/var/lib/srv-control/release.json`;
3. `checked_at`, `result`, `detail`, `remote_sha`, `release_id`, `release_version`, `update_available` из updater status;
4. состояние timer/service;
5. последний deployment stage и rollback result.

Не публикуйте credentials, tokens, session keys и private key material вместе с диагностикой.
