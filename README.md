# SRV Control Center — Release 1.0.0

`filosoff31/srv-deployment` — production-репозиторий SRV Control Center.

С версии **1.0.0** ранее накопленные инкрементальные сборки `0001`–`0010` объединены в один самодостаточный baseline-релиз. Старые каталоги релизов удаляются из актуального дерева `main`; их история при этом остаётся доступна в Git history.

## Что входит в 1.0.0

Release 1.0.0 объединяет все функции, которые были фактически доведены до production до консолидации:

- базовый FastAPI Control Center и PostgreSQL;
- dashboard и health API;
- отображение версии релиза и времени GitHub-синхронизации;
- раздел «Система» с CPU, RAM, дисками, службами и deployment status;
- сетевой обзор и диагностика;
- безопасный read-only планировщик WAN/LAN;
- административная сессия, CSRF-защита и журнал системных действий;
- перезагрузка сервера через отдельный privileged system agent;
- ручное и автоматическое обновление ОС/пакетов;
- установка/удаление AdGuard VPN CLI и безопасный мониторинг его состояния;
- graceful rotation двух Uvicorn workers без остановки listener;
- preflight / apply / acceptance / rollback для product update;
- clean-install bootstrap для новой Debian/Ubuntu-машины;
- GitHub → SRV deployment и SRV → GitHub `server-state`.

Релиз 1.0.0 **не включает ещё не реализованные функции из последующего плана**. Они будут развиваться уже поверх стабильной ветки 1.x.

## Новая структура релизов

Активный production-релиз определяется только `deployment.json`.

```text
deployment.json
releases/
└── 1.0.0/
    ├── manifest.json
    ├── preflight.sh
    ├── apply.sh
    ├── acceptance.sh
    ├── rollback.sh
    ├── payload/
    └── system/
```

`releases/1.0.0/payload` содержит полный снимок приложения, а `releases/1.0.0/system` — системные helper/unit-файлы. Это устраняет зависимость от последовательного применения старых релизов.

Production-сервер читает **только `main`**. Ветка `server-state` предназначена только для публикации фактического состояния SRV.

## Автоматическое обновление для 0.8.0 и новее

Для уже установленного SRV Control Center версии **0.8.0 или новее** используется:

```bash
curl -fL -o /tmp/srvcc-configure-auto-updates.sh \
  https://raw.githubusercontent.com/filosoff31/srv-deployment/main/bootstrap/configure-auto-updates.sh

sudo bash /tmp/srvcc-configure-auto-updates.sh \
  --mode automatic \
  --interval-minutes 5 \
  --check-now
```

Ручной режим:

```bash
sudo /usr/local/sbin/srvcc-configure-auto-updates \
  --mode manual \
  --no-check-now

sudo systemctl start srvcc-github-agent.service
```

Изменить период проверки:

```bash
sudo /usr/local/sbin/srvcc-configure-auto-updates \
  --mode automatic \
  --interval-minutes 15
```

Допустимый интервал: **1–1440 минут**.

### Как работает новый updater

Старый updater считал любой новый commit в `main` новым product-релизом. Поэтому изменение README или deployment helper могло повторно применить уже установленный релиз.

Начиная с 1.0.0 updater разделяет:

- последний увиденный commit репозитория;
- commit последнего реально применённого product-релиза;
- fingerprint активного релиза.

Fingerprint строится из `deployment.json`, `release_id`, `release_version` и Git tree активного каталога релиза. Если изменился только README, документация или deployment-инфраструктура, но активный release tree не изменился, приложение **не переустанавливается и не перезапускается**.

Для установок 0.8.0–0.10.x предусмотрена миграция: если установленный релиз и active release tree в GitHub совпадают, новый updater принимает текущее состояние без повторного apply.

Состояние updater хранится в:

```text
/var/lib/srvcc-agent/last-deployed-sha
/var/lib/srvcc-agent/last-seen-sha
/var/lib/srvcc-agent/last-release-fingerprint
/var/lib/srv-control/github-update-config.json
/var/lib/srv-control/github-update-status.json
```

## Чистая установка

```bash
curl -fL -o install.sh \
  https://raw.githubusercontent.com/filosoff31/srv-deployment/main/install.sh
chmod +x install.sh
sudo ./install.sh
```

После clean install bootstrap дополнительно устанавливает актуальный release-fingerprint updater.

## Правила для следующих релизов

Начиная с 1.0.0:

1. новый product-релиз получает самостоятельный каталог `releases/<version>`;
2. каталог должен содержать полный payload, необходимый для установки текущей версии;
3. `deployment.json` меняется только при активации нового product-релиза;
4. документационные и инфраструктурные commit'ы не должны приводить к повторному apply неизменившегося product-релиза;
5. все product-релизы проходят `preflight → apply → acceptance`, а при ошибке — rollback;
6. production update не считается успешным, пока healthcheck не подтверждён.

## Дополнительная документация

- `docs/INSTALL.md` — установка на чистую машину;
- `docs/DEPLOYMENT-RELIABILITY.md` — защита deployment-канала;
- `docs/SYSTEM-ADMIN.md` — системные административные функции;
- `docs/AUTO-UPDATES.md` — updater для 0.8.0 и новее.
