# Deployment reliability

## Обнаруженная проблема

Во время релиза 0.3.0 сервер Control Center начал перезапускаться повторно с интервалом, совпадающим с циклом GitHub agent.

Фактическая последовательность была следующей:

1. `deploy/orchestrator.sh` успешно выполнял preflight/apply/acceptance;
2. `apply.sh` выполнял `systemctl restart srv-control.service`;
3. после успешного acceptance агент запускал общий `deploy/healthcheck.sh`;
4. общий healthcheck оставался от раннего тестового `channel-probe` и требовал:
   - `/opt/srv-control/DEPLOYMENT_STATUS.txt`;
   - `stage=channel-probe`;
   - SHA текущего main в старом marker;
5. healthcheck завершался ошибкой;
6. агент не обновлял `/var/lib/srvcc-agent/last-deployed-sha`;
7. следующий timer-cycle снова считал тот же main commit новым и повторял весь apply, включая restart.

Таким образом, проблема была не падением FastAPI/Uvicorn из-за нового кода. Это был deployment retry loop после ложного отрицательного healthcheck.

## Исправления

### Новый общий healthcheck

`deploy/healthcheck.sh` теперь проверяет:

- `srv-control.service` active;
- `/var/lib/srv-deployment/last-result.env`;
- `result=success`;
- `stage=acceptance`;
- соответствие `remote_sha`;
- `/api/v1/health`;
- release metadata и SHA.

После успеха он атомарно пишет `/var/lib/srv-control/deployment-status.json`, который безопасно отображается в UI.

### Защита orchestrator от restart-loop

Если exact `release_id + remote_sha` уже имеет успешный acceptance, повторный запуск orchestrator **не выполняет apply**. Он только повторяет acceptance. Это предотвращает повторный restart даже в случае сбоя следующего внешнего шага.

### Graceful worker rotation

С 0.4.0 `srv-control.service` запускает Uvicorn с двумя workers.

Для последующих code-only релизов `deploy/reload-srv-control.sh` отправляет `SIGHUP` main-процессу Uvicorn. Uvicorn process manager graceful-restarts workers по одному, и новый worker загружает обновлённый код. Жёсткий restart остаётся fallback для legacy single-process service или изменений самого unit-файла.

Официальная документация Uvicorn:
https://www.uvicorn.org/deployment/

## Release checklist

Перед переключением `deployment.json` на новый релиз:

1. payload syntax/compile check;
2. SHA256 manifest verification;
3. preflight без изменения сервера;
4. backup всех изменяемых путей;
5. apply;
6. local application acceptance;
7. общий healthcheck;
8. только затем запись `last-deployed-sha`.

Если acceptance не проходит — release rollback должен вернуть предыдущие project files/metadata и service definition.
