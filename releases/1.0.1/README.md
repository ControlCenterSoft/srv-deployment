# Control Center 1.0.1

Control Center — web-панель управления Linux-сервером.

## Текущий релиз

**1.0.1**

### Что нового

- интерфейс переведен на визуальный стиль предыдущего проекта Control Center;
- добавлен раздел **Настройки**;
- добавлен механизм автоматического обновления production-релизов;
- настройки автообновления вынесены в Web UI;
- добавлен автоматический rollback при ошибке обновления.

## Главное меню

- **Система** — сведения об ОС, CPU, RAM, дисках и мониторинг;
- **Сети** — интерфейсы, IPv4, MAC и статистика RX/TX;
- **Маркет** — каталог серверных сервисов;
- **RBAC** — локальные Linux УЗ и группы;
- **Настройки** — параметры Control Center и автоматического обновления.

## Автоматические обновления

После установки создаются:

- `control-center-update.service`;
- `control-center-update.timer`;
- `/usr/local/sbin/control-center-update`;
- `/var/lib/control-center/update-settings.json`;
- `/var/lib/control-center/update-status.json`.

По умолчанию:

- автоматические обновления включены;
- канал — `production`;
- проверка — каждый час.

Systemd timer запускает легкую проверку каждые 15 минут, а фактическая частота определяется настройкой `hourly`, `daily` или `weekly`.

Перед обновлением сохраняется rollback-копия текущего приложения. При неуспешной установке предыдущая версия автоматически восстанавливается.

## Установка

```bash
sudo bash install/install.sh
```

После установки:

```text
http://SERVER_IP:8080
```

Проверка:

```bash
systemctl status control-center --no-pager
systemctl status control-center-update.timer --no-pager
curl http://127.0.0.1:8080/api/health
```

## Структура

```text
app/                  web-приложение
install/              установка и удаление
update/               механизм автообновления
docs/                 документация
releases/1.0.1/       паспорт релиза
deployment.json       текущий production-релиз
```

## Безопасность

Web-процесс работает от отдельной УЗ `control-center` без root-доступа. Настройки обновления сохраняются в `/var/lib/control-center`, а привилегированная установка выполняется только отдельным root systemd-сервисом.
