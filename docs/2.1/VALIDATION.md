# Control Center 2.1.x — validation and production acceptance

## CI gate

Каждый кандидат 2.1.x обязан пройти отдельный workflow `Control Center 2.1 Minecraft stabilization validation`.

Минимальный CI-контракт:

- production pointer не переключён преждевременно;
- manifest соответствует конкретной версии и SHA-256 release scripts;
- shell/Python syntax проходит;
- прямые пути обновления с 1.3.8 и 2.0.0 явно поддержаны;
- world/settings safety backup выполняется до смены service ownership;
- неоднозначные несколько runtime/process блокируют автоматическое изменение;
- SIGKILL отсутствует в автоматическом нормализаторе;
- canonical service и Control Center dispatcher присутствуют;
- конфликтующий multi-instance update timer отключается;
- acceptance требует ровно один Bedrock process, canonical cgroup/service, UDP listening и существующий active world.

## Real-server acceptance

До переключения `main/deployment.json` на 2.1.0 необходимо подтвердить на реальном сервере:

1. Исходная версия точно зафиксирована из свежего `server-state`.
2. Перед обновлением `bedrock_server` и текущий UDP-порт зафиксированы.
3. Обновление завершилось `result=success`, `stage=acceptance`.
4. `/var/lib/srv-control/release.json` содержит `version=2.1.0`, `release_id=2.1.0` и ожидаемый git SHA.
5. `srv-control-minecraft-bedrock.service` enabled + active.
6. Ровно один процесс `bedrock_server` принадлежит `srv-control-minecraft-bedrock.service`.
7. UDP-порт из `server.properties` слушается после обновления.
8. Активный `level-name` совпадает с существующим каталогом в `worlds/`.
9. Control Center status возвращает `healthy=true` и имя канонического service.
10. Проверяются безопасные start → status → restart → status операции.
11. Проверяются чтение properties, список миров, allowlist/permissions, backup list и logs.
12. Выполняется отдельный Minecraft backup; исходный мир остаётся тем же.
13. Проверяется ручная проверка обновления Minecraft без принудительной замены мира.
14. Конфликтующий `srv-control-minecraft-auto-update.timer` остаётся disabled.
15. Если присутствует `minecraft-update.timer`, он enabled + active и обращается к каноническому dispatcher.
16. Control Center, Samba, DHCP/PXE, сеть и системные страницы проходят smoke test после Minecraft-нормализации.
17. Публикуется новый `server-state`; состояние подтверждается повторно по GitHub, а не только по интерактивной shell-сессии.

## Failure policy

Если 2.1.0 не проходит real-server acceptance, опубликованный 2.1.0 не редактируется. Причина фиксируется по свежей диагностике, создаётся 2.1.1 с regression test, затем цикл повторяется. Аналогично для 2.1.2 и следующих patch releases.

Если обнаружено повреждение Bedrock runtime, patch release должен переустанавливать runtime отдельно от `worlds` и конфигурации. Если обнаружено повреждение активного мира, его замена разрешена только после успешной safety-копии и подтверждённой невозможности штатного восстановления.