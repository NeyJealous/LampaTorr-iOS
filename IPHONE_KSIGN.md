# Быстрая инструкция: iPhone + GitHub Actions + Ksign

1. Открой **Actions** → **Build LampaTorr IPA** → **Run workflow**.
2. Укажи Bundle ID, который разрешён твоим provisioning profile. Если профиль wildcard — можно оставить `dev.lampatorr.ios`.
3. После успешной сборки скачай artifact **LampaTorr-unsigned-ipa**.
4. В приложении **Файлы** распакуй скачанный ZIP.
5. Открой `LampaTorr-unsigned.ipa` в **Ksign**.
6. Выбери свой сертификат + provisioning profile → **Sign** → установи подписанный IPA.
7. При первом запуске LampaTorr автоматически поднимет TorrServer на `http://127.0.0.1:8090` и передаст этот адрес Lampa.

Сертификат, `.p12`, пароль и `.mobileprovision` в GitHub загружать не нужно.
