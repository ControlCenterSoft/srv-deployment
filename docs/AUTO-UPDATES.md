# Обновления Control Center с GitHub

> **Статус:** текущая эксплуатационная инструкция для production-линии. Активная версия всегда определяется `../deployment.json`; на момент этой редакции production target — **2.0.0**.

Control Center использует `main` как production-канал. Updater принимает решение по **product release fingerprint**, а не по факту появления любого нового Git commit.

## 1. Что является обновлением продукта

Product update — это переход между версиями Control Center, опубликованными через `deployment.json`. Он не равен обновлению пакетов ОС и не должен запускаться из-за documentation-only изменений.

Основные источники:

- `../deployment.json` — опубликованный target;
- `../releases/<version>/manifest.json` — frozen manifest;
- `/var/lib/srv-control/release.json` — установленная версия;
- `/var/lib/srv-control/github-update-config.json` — режим updater;
- `/var/lib/srv-control/github-update-status.json` — status текущего updater.

## 2. Режимы

Конфигуратор:

```text
/usr/local/sbin/srvcc-configure-auto-updates
```

Автоматический режим:

```bash
sudo /usr/local/sbin/srvcc-configure-auto-updates \
  --repo https://github.com/filosoff31/srv-deployment.git \
  --mode automatic \
  --interval-minutes 5
```

Ручной режим:

```bash
sudo /usr/local/sbin/srvcc-configure-auto-updates \
  --repo https://github.com/filosoff31/srv-deployment.git \
  --mode manual \
  --interval-minutes 5
```

В manual mode автоматический timer выключается, но выбранный интервал сохраняется для последующего возврата в automatic mode.

## 3. Check и apply — разные операции

```bash
sudo /usr/local/sbin/srvcc-github-agent check --actor root
sudo /usr/local/sbin/srvcc-github-agent apply --actor root
```

`check` обновляет checkout `origin/main`, читает production descriptor, вычисляет release fingerprint и обновляет status. Он не должен менять application payload.

`apply` выполняет deployment только если опубликованный product fingerprint требует перехода и не запрещён текущей failed/blocked policy.

## 4. Product fingerprint и принятие release

Fingerprint связывает release identity с Git-объектами активного product release. Это позволяет отделить изменение продукта от изменений README, roadmap, CI или другой документации.

Updater state хранится вне release payload. В 2.0.x используются, в зависимости от состояния/миграции сервера, в том числе:

```text
/var/lib/srvcc-agent/last-deployed-sha
/var/lib/srvcc-agent/last-seen-sha
/var/lib/srvcc-agent/last-release-fingerprint
/var/lib/srvcc-agent/accepted-release-fingerprint
/var/lib/srvcc-agent/blocked-release.json
/var/lib/srv-control/github-update-config.json
/var/lib/srv-control/github-update-status.json
```

Существующий уже установленный release может быть **adopted** без повторного apply только после подтверждения совпадения release identity/fingerprint.

## 5. Защита от бесконечного retry

Automatic updater не должен бесконечно повторять один и тот же известный неуспешный release fingerprint на каждом timer tick.

После failed transaction сохраняется диагностическое/blocked состояние. Повтор допускается после изменения release fingerprint либо как осознанный manual retry в предусмотренном workflow. Успешное применение принимает fingerprint и очищает соответствующее failed/blocked состояние.

## 6. Backup before update

`backup_before_update` — самостоятельная policy и не равна scheduled backup.

Если policy включена, обязательный пользовательский safety backup должен завершиться успешно до product apply. Ошибка backup блокирует update.

Если `backup_before_update=false`, updater не должен создавать пользовательский pre-update backup вопреки настройке. Внутренний transactional rollback snapshot, создаваемый конкретным release apply для возможности отката, является отдельным механизмом и не должен отображаться как пользовательский backup.

Изменение scheduled backup не должно самопроизвольно менять `backup_before_update`, и наоборот.

## 7. Deployment transaction

Для production 2.0.x базовая модель:

```text
check → policy-controlled backup → preflight → apply → acceptance → healthcheck
                                                     ↘ failure → rollback
```

Новый release считается успешно принятым только после требуемого acceptance/health contract.

## 8. Timestamps и UI

Update Center должен различать как минимум:

- последнюю проверку (`last_check_at`/эквивалент текущей schema);
- результат последней проверки;
- последнюю попытку применения (`last_update_attempt_at`), если она была;
- последнее успешное обновление (`last_successful_update_at`);
- доступность новой product version;
- manual/automatic mode и timer state.

«Последняя проверка» не должна подменяться временем последнего успешного update.

## 9. Восстановление automatic updater

Release apply/rollback не должен оставлять ранее выбранный automatic mode постоянно выключенным. После transaction проверяйте конфигурацию и systemd timer/service. Failed legacy state должен быть reset только предусмотренным configurator/controller path, а не ручным удалением произвольных state-файлов без диагностики.

## 10. Диагностика

```bash
systemctl status srvcc-github-agent.timer --no-pager -l
systemctl status srvcc-github-agent.service --no-pager -l
cat /var/lib/srv-control/github-update-config.json
cat /var/lib/srv-control/github-update-status.json
cat /var/lib/srv-control/release.json
tail -n 100 /var/log/srvcc-agent.log
```

Сверяйте отдельно:

1. production target в `deployment.json`;
2. установленный release;
3. accepted/blocked fingerprint state;
4. last check / last attempt / last success;
5. timer/service state;
6. последний preflight/apply/acceptance/rollback result.

Не публикуйте credentials, Git write tokens, session keys, private keys, Kerberos key material или содержимое backup archives.

См. также `PRODUCT-MANUAL-RU.md`, `DEPLOYMENT-RELIABILITY.md` и `2.0/UPGRADE-1.x-TO-2.0.md`.