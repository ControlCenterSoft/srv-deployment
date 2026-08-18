# Установка Control Center 1.0.0

## Требования

- Ubuntu Server 26.04 LTS или совместимая Debian-подобная система с systemd.
- root/sudo.
- Доступ к пакетным репозиториям на этапе установки.
- Свободный TCP-порт 8080.

## Установка

```bash
git clone https://github.com/filosoff31/srv-deployment.git
cd srv-deployment
sudo bash install/install.sh
```

Проверка:

```bash
systemctl status control-center --no-pager
curl http://127.0.0.1:8080/api/health
```

Web-интерфейс: `http://IP_СЕРВЕРА:8080`.

## Что устанавливается

- `/opt/control-center/app` — приложение.
- `/opt/control-center/venv` — изолированное Python-окружение.
- `control-center.service` — systemd-служба.
- отдельная системная УЗ `control-center` без интерактивного shell.

## Удаление

```bash
sudo bash install/uninstall.sh
```

## Диагностика

```bash
journalctl -u control-center -n 200 --no-pager
ss -ltnp | grep 8080
curl -v http://127.0.0.1:8080/api/health
```
