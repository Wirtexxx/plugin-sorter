<p align="center">
  <img src="docs/icon.png" width="140" alt="Plugin Sorter icon">
</p>

<h1 align="center">Plugin Sorter</h1>

<p align="center">
  <b>Sort your VST3 and VST plugins into developer folders — in one click.</b>
</p>

<p align="center">
  <a href="https://github.com/Wirtexxx/plugin-sorter/actions/workflows/build.yml"><img src="https://github.com/Wirtexxx/plugin-sorter/actions/workflows/build.yml/badge.svg?branch=develop" alt="Build"></a>
  <img src="https://img.shields.io/badge/macOS-11%2B-7b33f7?logo=apple&logoColor=white" alt="macOS 11+">
  <img src="https://img.shields.io/badge/Apple%20Silicon%20%2B%20Intel-universal-cc4dff" alt="Universal">
  <img src="https://img.shields.io/badge/SwiftUI-orange?logo=swift&logoColor=white" alt="SwiftUI">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-73c7ff" alt="MIT"></a>
</p>

<p align="center">
  English · <a href="README.ru.md">Русский</a>
</p>

<p align="center">
  <img src="docs/screenshot.png" width="760" alt="Plugin Sorter window">
</p>

---

## Why

After a few years of production `/Library/Audio/Plug-Ins/VST3` turns into a flat wall of
hundreds of bundles. Plugin Sorter reads who actually made each plugin and tidies everything up:

```
VST3/                                VST3/
├── FabFilter Pro-Q 4.vst3           ├── FabFilter/
├── OTT.vst3                         │   └── FabFilter Pro-Q 4.vst3
├── Serum2.vst3              ──►     ├── Xfer Records/
├── soothe2.vst3                     │   ├── OTT.vst3
└── ValhallaSupermassive.vst3        │   └── Serum2.vst3
                                     ├── oeksound/
                                     │   └── soothe2.vst3
                                     └── Valhalla DSP/
                                         └── ValhallaSupermassive.vst3
```

## Features

- 🔭 **Knows the real developer.** The vendor comes from the bundle identifier, not the file
  name, so `OTT` lands in *Xfer Records* and `soothe2` in *oeksound*.
- 👀 **Preview first.** You see every move grouped by developer before anything happens.
- ↩️ **One-click undo.** Every run writes a move log, and *Undo* puts everything back.
- 📁 **Respects your folders.** Existing vendor folders are reused, whatever their letter case.
- 🌊 **Leaves Waves alone.** WaveShells are managed by Waves Central and are skipped.
- 🧩 **Keeps Audio Units working.** AU stay in `Components`, and AU moved by 1.0 can be
  restored with one click.
- 🎛️ **Plugin-style UI.** Graphite panels, format knobs and a waveform of your developers,
  in English, Русский, Українська and Deutsch.
- ⌨️ **CLI included** for people who live in the terminal.

## Install

### Download

1. Download **[PluginSorter.dmg](https://github.com/Wirtexxx/plugin-sorter/releases/latest/download/PluginSorter.dmg)**
   from the latest release.
2. Open it and drag **Plugin Sorter** onto the **Applications** folder.
3. The app is not notarized, so on first launch right-click it → **Open**, or run:

   ```bash
   xattr -dr com.apple.quarantine "/Applications/Plugin Sorter.app"
   ```

### Build from source

Needs only the Xcode Command Line Tools (`xcode-select --install`):

```bash
git clone https://github.com/Wirtexxx/plugin-sorter.git
cd plugin-sorter
./build.sh --install
```

## Usage

### App

1. Open **Plugin Sorter**. It scans your plugin folders right away.
2. Toggle **VST3 / VST** to pick which folders to process.
3. Review the list and press **Sort**. macOS asks for an administrator password
   because `/Library/Audio/Plug-Ins` belongs to the system.
4. Changed your mind? Press **Undo**.

### Command line

```bash
./scripts/sort-plugins.sh                      # dry run: show what would move
sudo ./scripts/sort-plugins.sh --apply         # move plugins, write ~/plugin-sort-<time>.log
sudo ./scripts/sort-plugins.sh --undo ~/plugin-sort-20261102-193000.log
sudo ./scripts/sort-plugins.sh --restore-au    # put AU sorted by 1.0 back into Components
```

| Variable              | Default                 | Purpose                         |
| --------------------- | ----------------------- | ------------------------------- |
| `PLUGIN_SORT_FORMATS` | `VST3 VST`              | Folders to process              |
| `PLUGIN_SORT_LOG_DIR` | invoking user's home    | Where the move log is written   |
| `PLUGIN_SORT_OWNER`   | `$SUDO_USER`            | Owner of the move log           |

## How it works

Each plugin bundle has a reverse-DNS identifier in `Contents/Info.plist`. Plugin Sorter skips
the domain parts and takes the first meaningful word as the developer:

| Bundle identifier                  | Folder         |
| ---------------------------------- | -------------- |
| `com.fabfilter.Pro-Q.4`            | `FabFilter`    |
| `com.xfer.OTT`                     | `Xfer Records` |
| `co.uk.gvst.GClip`                 | `GVST`         |
| `app.cradle.GodParticle`           | `Cradle`       |

Pretty names for well-known developers live in `pretty_name()` in
[`scripts/sort-plugins.sh`](scripts/sort-plugins.sh). Anything else keeps the name from its
identifier. Missing your favourite developer? Pull requests are welcome.

## Good to know

- DAWs scan VST and VST3 folders recursively, and hosts identify plugins by their IDs rather
  than file paths, so existing projects keep loading them.
- **Audio Units are not sorted.** macOS only registers components that sit directly in
  `/Library/Audio/Plug-Ins/Components`, so an AU in a subfolder disappears from every host.
  Version 1.0 did sort them: if your AU vanished, open the app and press **Restore AU**
  (or run `--restore-au`), then restart your DAW.
- Plugin installers usually drop updates back into the root folder. Just run Plugin Sorter again.

## Project structure

```
App/            SwiftUI app: model, window, theme, translations
scripts/        sort-plugins.sh: the engine, usable on its own
tools/          icon and README screenshot renderers
build.sh        builds a universal Plugin Sorter.app without Xcode
```

## License

[MIT](LICENSE) © Wirtex
