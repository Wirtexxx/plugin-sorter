<p align="center">
  <img src="docs/icon.png" width="140" alt="Иконка Plugin Sorter">
</p>

<h1 align="center">Plugin Sorter</h1>

<p align="center">
  <b>Раскладывает VST3, VST и Audio Unit плагины по папкам разработчиков — в один клик.</b>
</p>

<p align="center">
  <a href="https://github.com/Wirtexxx/plugin-sorter/actions/workflows/build.yml"><img src="https://github.com/Wirtexxx/plugin-sorter/actions/workflows/build.yml/badge.svg?branch=develop" alt="Build"></a>
  <img src="https://img.shields.io/badge/macOS-11%2B-7b33f7?logo=apple&logoColor=white" alt="macOS 11+">
  <img src="https://img.shields.io/badge/Apple%20Silicon%20%2B%20Intel-universal-cc4dff" alt="Universal">
  <img src="https://img.shields.io/badge/SwiftUI-orange?logo=swift&logoColor=white" alt="SwiftUI">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-73c7ff" alt="MIT"></a>
</p>

<p align="center">
  <a href="README.md">English</a> · Русский
</p>

<p align="center">
  <img src="docs/screenshot.png" width="760" alt="Окно Plugin Sorter">
</p>

---

## Зачем

За пару лет продакшена `/Library/Audio/Plug-Ins/Components` превращается в сплошную стену
из сотен бандлов. Plugin Sorter определяет, кто на самом деле сделал каждый плагин, и наводит порядок:

```
Components/                          Components/
├── FabFilter Pro-Q 4.component      ├── FabFilter/
├── OTT.component                    │   └── FabFilter Pro-Q 4.component
├── Serum2.component         ──►     ├── Xfer Records/
├── soothe2.component                │   ├── OTT.component
└── ValhallaSupermassive.component   │   └── Serum2.component
                                     ├── oeksound/
                                     │   └── soothe2.component
                                     └── Valhalla DSP/
                                         └── ValhallaSupermassive.component
```

## Возможности

- 🔭 **Знает настоящего разработчика.** Он берётся из идентификатора бандла, а не из имени
  файла, поэтому `OTT` попадает в *Xfer Records*, а `soothe2` в *oeksound*.
- 👀 **Сначала предпросмотр.** Все перемещения видны заранее, сгруппированные по разработчикам.
- ↩️ **Откат в один клик.** Каждый запуск пишет лог, и кнопка *Откатить* возвращает всё назад.
- 📁 **Уважает ваши папки.** Существующие папки разработчиков используются повторно, независимо от регистра.
- 🌊 **Не трогает Waves.** WaveShell управляется Waves Central и пропускается.
- 🎛️ **Интерфейс в стиле плагинов.** Графитовые панели, ручки форматов и «волна» разработчиков,
  на English, Русском, Українській и Deutsch.
- ⌨️ **Есть CLI** для тех, кто живёт в терминале.

## Установка

### Скачать

1. Скачайте **[PluginSorter.dmg](https://github.com/Wirtexxx/plugin-sorter/releases/latest/download/PluginSorter.dmg)**
   из последнего релиза.
2. Откройте его и перетащите **Plugin Sorter** на папку **Applications**.
3. Приложение не нотаризовано, поэтому при первом запуске нажмите по нему правой кнопкой → **Открыть**
   или выполните:

   ```bash
   xattr -dr com.apple.quarantine "/Applications/Plugin Sorter.app"
   ```

### Собрать из исходников

Нужны только Command Line Tools (`xcode-select --install`):

```bash
git clone https://github.com/Wirtexxx/plugin-sorter.git
cd plugin-sorter
./build.sh --install
```

## Использование

### Приложение

1. Откройте **Plugin Sorter**: оно сразу просканирует папки с плагинами.
2. Переключателями **VST3 / VST / AU** выберите, какие папки обрабатывать.
3. Проверьте список и нажмите **Сортировать**. macOS попросит пароль администратора,
   потому что `/Library/Audio/Plug-Ins` принадлежит системе.
4. Передумали? Нажмите **Откатить**.

### Командная строка

```bash
./scripts/sort-plugins.sh                      # пробный запуск: что будет перемещено
sudo ./scripts/sort-plugins.sh --apply         # переместить, лог в ~/plugin-sort-<время>.log
sudo ./scripts/sort-plugins.sh --undo ~/plugin-sort-20261102-193000.log
```

| Переменная            | По умолчанию            | Назначение                      |
| --------------------- | ----------------------- | ------------------------------- |
| `PLUGIN_SORT_FORMATS` | `VST3 VST Components`   | Какие папки обрабатывать        |
| `PLUGIN_SORT_LOG_DIR` | домашняя папка          | Куда писать лог перемещений     |
| `PLUGIN_SORT_OWNER`   | `$SUDO_USER`            | Владелец файла лога             |

## Как это работает

У каждого бандла плагина в `Contents/Info.plist` есть идентификатор в формате обратного DNS.
Plugin Sorter пропускает доменные части и берёт первое осмысленное слово как имя разработчика:

| Идентификатор бандла               | Папка          |
| ---------------------------------- | -------------- |
| `com.fabfilter.Pro-Q.4`            | `FabFilter`    |
| `com.xfer.OTT`                     | `Xfer Records` |
| `co.uk.gvst.GClip`                 | `GVST`         |
| `app.cradle.GodParticle`           | `Cradle`       |

Красивые имена известных разработчиков задаются в `pretty_name()` в
[`scripts/sort-plugins.sh`](scripts/sort-plugins.sh). Остальные получают имя из идентификатора.
Нет вашего любимого разработчика? Присылайте pull request.

## Полезно знать

- DAW сканируют папки с плагинами рекурсивно и находят плагины по их ID, а не по пути к файлу,
  поэтому существующие проекты продолжают их загружать.
- Если после сортировки хост не видит какой-то Audio Unit, сравните `auval -a | wc -l` до и после
  и нажмите **Откатить**, если числа отличаются.
- Установщики плагинов обычно кладут обновления обратно в корень папки. Просто запустите Plugin Sorter ещё раз.

## Структура проекта

```
App/            SwiftUI-приложение: модель, окно, тема, переводы
scripts/        sort-plugins.sh — движок, работает и сам по себе
tools/          генераторы иконки и скриншота для README
build.sh        собирает универсальный Plugin Sorter.app без Xcode
```

## Лицензия

[MIT](LICENSE) © Wirtex
