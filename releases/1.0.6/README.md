# Control Center 1.0.6

Статус: `production`.

Проверка GitHub Actions `Validate Control Center release` завершена успешно. Релиз прошёл автоматические проверки Python, JavaScript, Bash, JSON/metadata consistency, обязательных компонентов UI/API, DHCP validation, CSP, public RSA key и документации.

## Изменения

1. В разделе **Сети** возвращён полный перечень интерфейсов с ролью, типом, link state, IPv4, шлюзом, DNS, MAC, MTU и скоростью.
2. Формы WAN/LAN и DHCP загружают уже применённое защищённое состояние и, где возможно, сверяются с фактическими Netplan/dnsmasq конфигурационными файлами.
3. Базовая типографика увеличена: основной текст 15 px, навигация 14 px, заголовки страниц 23–28 px, формы 12–13 px.
4. Меню получило отдельные семантические SVG-ярлычки для Системы, Сетей, DHCP, Маркета, RBAC и Настроек.
5. Мобильная верстка переработана: off-canvas sidebar, backdrop, отдельная раскладка topbar, одноколоночные формы и горизонтальный scroll таблиц.
6. DHCP поддерживает дополнительные numeric options: код + значение, просмотр текущих options, добавление и удаление перед сохранением. Базовые options 1/3/6/51 защищены от дублирования.
7. В DHCP отображается фактический статус `control-center-dhcp-server.service`.
8. Добавлена кнопка **Проверить конфигурацию**, выполняющая `dnsmasq --test --conf-file=/etc/dnsmasq.d/control-center-dhcp.conf` без изменения конфигурации.
9. Добавлен общий колокольчик уведомлений. Он агрегирует последние статусы сети, Маркета, DHCP, лицензии, обновления Control Center и обновления ОС/пакетов. Непрочитанная ошибка — красный, непрочитанные успешные/рабочие события — зелёный, всё прочитано — нейтральный серый.
10. JavaScript вынесен из HTML в `/static/app.js`; CSP больше не требует `unsafe-inline`.
11. Исправлен background polling DHCP: он больше не перезаписывает несохранённые изменения формы.
12. Правовые и продуктовые документы включены в обязательную release-validation: EULA, Home/Professional, lifecycle и история релизов.

## Источники отображаемых данных

- System — `/proc`, `df`, `ps`, `ip`;
- Network interface inventory — `/sys/class/net`, `ip`, `resolvectl`;
- WAN/LAN — `/var/lib/control-center-system/network-config.json` + `/etc/netplan/90-control-center.yaml` + live interface state;
- DHCP — `/var/lib/control-center-system/dhcp-config.json` + `/etc/dnsmasq.d/control-center-dhcp.conf` + systemd service state;
- Market/tasks — protected status files в `/var/lib/control-center-system`;
- Home/Professional — `/var/lib/control-center-license/license.json`;
- update settings — Web-writable settings files, update results — protected system-state.

## Acceptance

После установки на целевой сервер выполните:

```bash
sudo bash scripts/acceptance-1.0.6.sh
```

Этот acceptance является non-destructive. Фактическую выдачу DHCP lease и изменение активного WAN/LAN рекомендуется дополнительно проверять на реальном сервере с резервным административным каналом.

## Ограничение

Встроенная Web-аутентификация ещё не реализована. TCP/8080 должен оставаться доступным только из доверенной административной LAN/VPN/firewall.
