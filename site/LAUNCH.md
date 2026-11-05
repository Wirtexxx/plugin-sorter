# Запуск сайта Plugin Sorter

Сайт собран и протестирован, но не опубликован. Публикация включается переменной репозитория `SITE_LIVE=true`: пока она не равна `true`, job `deploy` в `.github/workflows/site.yml` не запускается. Ниже шаги автора по порядку.

1. **Купить домен** `pluginsorter.com`.

2. **Скриншот «до».** Положить `docs/screenshot-fl-picker-before.png` и выполнить в `site/`: `npm run assets`. Размер и кадрирование должны совпадать с `docs/screenshot-fl-picker.png`, иначе сравнение «до/после» на странице будет выглядеть криво.

3. **Проверить Ko-fi.** Ko-fi уже создан, ссылки лежат в `site/site.config.json`. Собрать страницу (`npm run build`, затем `npm run preview`) и открыть в браузере настоящую форму Ko-fi: она должна отображаться и вести в платёжный сценарий. Подтвердить выплаты в Польшу и комиссии.

4. **Сверить тексты.**
   - Ячейки «Нет» и «Вручную» в таблице сравнения проверить на своей версии FL Studio.
   - Текст от первого лица в блоке поддержки перечитать и поправить под себя.

5. **Домен и DNS.** Подтвердить домен в настройках GitHub (Settings, Pages, Verified domains), затем у регистратора создать записи.
   - `A` для апекса: `185.199.108.153`, `185.199.109.153`, `185.199.110.153`, `185.199.111.153`
   - `AAAA` для апекса: `2606:50c0:8000::153`, `2606:50c0:8001::153`, `2606:50c0:8002::153`, `2606:50c0:8003::153`
   - `CNAME` для `www`: `wirtexxx.github.io` (сам домен, без имени репозитория)

   Значения сверены с текущей документацией GitHub Pages (2026-11-05). Перед использованием проверить их ещё раз: https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site

6. **Включить публикацию.** Settings, Pages, Source: GitHub Actions. Затем Settings, Secrets and variables, Actions, Variables: `SITE_LIVE=true`. Указать custom domain и включить Enforce HTTPS (после выпуска сертификата).

7. **Search Console.** Подключить `pluginsorter.com` через DNS-запись TXT и отправить `sitemap.xml`.

8. **Обновить ссылки.** `homepage` репозитория, ссылки в обоих README и `.github/FUNDING.yml` (`ko_fi` там уже записан).

## Проверка сборки для публикации

```
cd site && node build.mjs --release
```

Пока нет скриншота «до», команда падает с `Missing picker-before.webp`. Это правильное поведение; после шага 2 сборка должна пройти.
