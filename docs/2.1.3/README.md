# Control Center 2.1.3

Ветка 2.1.3 создаётся от опубликованного production 2.1.2 и не изменяет frozen `releases/2.1.2`.

Цели релиза:

- вернуть HTTPS как канонический способ доступа; HTTP используется только для редиректа на 443;
- безопасно сохранять подходящую PKI или выпускать внутренний CA/сертификат с SAN для canonical host;
- исправить Kerberos/SPNEGO handoff nginx → backend, не принимая клиентский `X-SRVCC-Remote-User`;
- сохранить PAM/winbind вход как fallback;
- подготовить централизованное доверие Root CA и Chrome/Edge `AuthServerAllowlist` для доменных Windows-клиентов;
- исключить Docker bridge A-records из canonical host DNS;
- добавить Chrony как устанавливаемый/удаляемый сервис в меню «Сервисы»;
- добавить «Настройки системы → Время / Chrony»: timezone, sync state, tracking/source/stratum/offset, upstream NTP, LAN allow networks, Samba AD DC `ntpsigndsocket`, restart/step/diagnostics;
- применять Chrony-конфигурацию только после валидации, с rollback при ошибке;
- доказать всё перечисленное в preflight/apply/acceptance/rollback.

Текущий статус: создан каркас release contract, первичный HTTPS/SPNEGO helper и Chrony service helper. UI/API, GPO/Root-CA distribution, DNS hardening и расширенная acceptance ещё находятся в разработке.
