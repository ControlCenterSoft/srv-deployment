# Control Center 2.1.4

## Назначение

2.1.4 — production patch линии 2.1.x, исправляющий чистую установку Control Center после перехода на delta patch releases.

## Инцидент

На реальной чистой системе после запуска clean installer браузер по IP сервера показывал стандартную страницу `Welcome to nginx!` вместо Control Center.

Подтверждены две причины:

1. clean installer читал `deployment.json` и требовал, чтобы payload активного релиза был самодостаточным. Опубликованные 2.1.1 и 2.1.2 являются дельтами, поэтому при активном 2.1.2 установка завершалась ошибкой после установки системных пакетов и до развёртывания приложения/nginx-конфигурации;
2. nginx устанавливался и автоматически запускался до проверки занятости порта 80. Старый код мог принять собственный package-default nginx за внешнюю службу и выбрать 8080.

## Исправление

- добавлен `installer/install-profile.json` с явной frozen install lineage;
- полный clean-install payload реконструируется во временном каталоге из `2.1.0 payload + 2.1.1 delta + 2.1.2 delta`;
- post-assembly применяются только зафиксированные детерминированные Minecraft patches 2.1.1/2.1.2;
- общие system helpers устанавливаются из declared consolidated baseline, а текущий Minecraft privilege agent — из frozen 2.1.1;
- package-default nginx останавливается до port probe;
- стандартный `/etc/nginx/sites-enabled/default` удаляется;
- acceptance проверяет backend health и тот же health endpoint через реально опубликованный nginx port;
- stock nginx welcome page после `INSTALL PASS` теперь считается acceptance failure.

## Совместимость

Runtime существующих серверов не меняется относительно принятого 2.1.2, кроме release marker при штатном product update. Миры Minecraft, настройки, Samba/AD данные и пользовательские backup не заменяются этим патчем.

2.1.4 поддерживает upgrade sources 1.3.8, 2.0.0, 2.1.0, 2.1.1 и 2.1.2; при необходимости используются frozen base transitions.

## Проверки

Обязательны:

- SHA-locked release manifest;
- сборка полного install payload из frozen layers;
- отсутствие старого Minecraft `sudo` path в собранном приложении;
- наличие 2.1.2 live status layer;
- синтаксис installer/release scripts;
- nginx ordering guard: stop package nginx → probe ports → remove default site → install reverse proxy;
- backend health;
- public reverse-proxy health;
- повторная реальная установка на чистую Ubuntu после публикации кандидата.

Релиз нельзя считать окончательно принятым только по CI: реальная clean-host проверка обязательна.

## Нумерация

Номер 2.1.3 ранее был занят неопубликованным draft HTTPS/Kerberos/Chrony. Его код сохранён в отдельной feature-ветке и не публиковался. Из-за запрета force-push защищённой release-ветки clean-install correction выпущен как 2.1.4. Неопубликованный 2.1.3 не является production release.
