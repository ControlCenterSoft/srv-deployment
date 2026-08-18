# Обновления Control Center с GitHub

Control Center использует `main` как production-канал. Активный production release определяется `deployment.json`; сейчас это **2.0.0**.

Updater 2.0.0 сравнивает **product/release fingerprint**, а не просто SHA последнего commit, и разделяет проверку обновления и применение release.

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

`check` получает `origin/main`, читает `deployment.json`, вычисляет fingerprint active release и обновляет updater status без изменения application state.

`apply` запускает deployment только когда active product release отличается от принятого установленного fingerprint. В automatic mode systemd timer запускает apply через managed updater runtime.

## Product fingerprint и состояние 2.0

Fingerprint привязан к release identity и Git-объектам активного product release. Documentation-only commit вне active release tree не должен вызывать повторный apply.

2.0.0 хранит отдельное состояние принятого/неуспешного release, включая файлы класса:

```text
/var/lib/srvcc-agent/accepted-release-fingerprint
/var/lib/srvcc-agent/last-release-fingerprint
/var/lib/srvcc-agent/blocked-release.json
/var/lib/srv-control/github-update-config.json
/var/lib/srv-control/github-update-status.json
```

Конкретный набор state files определяется active frozen release; не создавайте и не редактируйте их вручную без диагностической необходимости.

## Защита от бесконечного failed retry

Если automatic apply конкретного release fingerprint завершился неуспешно, updater не должен повторять тот же destructive apply на каждом timer tick. Failed release фиксируется как blocked/suppressed до изменения release или осознанного manual retry.

Manual retry допустим после устранения причины. Успешная transaction принимает fingerprint и очищает соответствующее failed-state.

## Устойчивость automatic timer

Одна из целей 2.0.0 — исключить дефект 1.3.x, при котором после неуспешной update transaction automatic schedule мог остаться выключенным.

После release apply updater/configurator восстанавливает выбранный режим и systemd timer. Для automatic mode timer должен оставаться enabled/active после успешной установки и после recoverable failed attempt.

## Timestamps

UI и status model разделяют как минимум:

- **Последняя проверка обновления**;
- timestamp последней попытки apply — диагностическое состояние;
- **Последнее успешное обновление**.

Не интерпретируйте `checked_at` как доказательство успешной установки: обычная проверка может обновить время проверки без product apply.

## Backup before update

`backup_before_update` — отдельная safety policy и не равна расписанию ежедневных backup.

В 2.0.0 отключение `backup_before_update` должно реально запрещать **пользовательский pre-update backup** и для product update, и для OS update. При этом внутренний rollback snapshot release transaction может создаваться независимо: это механизм rollback, а не пользовательская резервная копия.

Если policy включена, ошибка обязательного pre-update backup блокирует deployment.

## Deployment transaction

Базовая цепочка:

```text
check → policy gate/backup → preflight → apply → acceptance → healthcheck
                                           ↘ failure → rollback
```

Новый fingerprint принимается только после успешного завершения требуемой release transaction.

## Web UI

На странице «Система» администратор может настроить GitHub source, manual/automatic mode и период проверки, выполнить явную проверку и применить доступное обновление.

UI должен показывать отдельно schedule state, последнюю проверку, последний успешный update, наличие update и диагностический failed/blocked state при необходимости.

Эти операции выполняются через privileged system action path; web-процесс не запускает Git/systemctl/root-команды напрямую.

## Диагностика

```bash
systemctl status srvcc-github-agent.timer --no-pager -l
systemctl status srvcc-github-agent.service --no-pager -l
cat /var/lib/srv-control/github-update-config.json
cat /var/lib/srv-control/github-update-status.json
cat /var/lib/srvcc-agent/blocked-release.json 2>/dev/null || true
tail -n 100 /var/log/srvcc-agent.log
```

При разборе проблемы отдельно фиксируйте:

1. active release из `deployment.json`;
2. installed release из `/var/lib/srv-control/release.json`;
3. last check / last attempt / last success и `result/detail` updater status;
4. состояние timer/service;
5. accepted/blocked fingerprint state;
6. последний deployment stage и rollback result;
7. значение `backup_before_update`.

Не публикуйте credentials, tokens, session keys, private keys или содержимое backup вместе с диагностикой.
