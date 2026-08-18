# Документация Control Center 1.0.5

- [INSTALL.md](INSTALL.md) — установка, повторная установка и удаление.
- [UPDATE.md](UPDATE.md) — обновление самого Control Center.
- [OS_UPDATES.md](OS_UPDATES.md) — обновление Ubuntu/Debian пакетов.
- [LICENSING.md](LICENSING.md) — Home, Professional, выпуск и активация лицензии.
- [NETWORK.md](NETWORK.md) — WAN/LAN, DHCP/Static и Netplan.
- [DHCP.md](DHCP.md) — DHCP Server из Маркета.
- [SECURITY.md](SECURITY.md) — модель привилегий и известные ограничения.
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) — диагностика.

## Быстрая проверка

```bash
cat /opt/control-center/VERSION
curl -fsS http://127.0.0.1:8080/api/health | python3 -m json.tool
systemctl status control-center --no-pager
```

## Важное ограничение 1.0.5

Web UI пока не имеет полноценной встроенной аутентификации. TCP/8080 должен быть ограничен доверенной LAN/VPN/firewall.
