#!/bin/bash
# plugin-sorter — moves audio plugins in /Library/Audio/Plug-Ins/{VST3,VST}
# into developer folders. The developer is taken from the bundle's CFBundleIdentifier
# (com.fabfilter.Pro-Q.3 -> FabFilter).
#
# Audio Units are never sorted: macOS only registers components that sit directly
# in Components, so an AU inside a subfolder disappears from every host.

# PLUGIN_SORT_ROOT points the script at another tree (used by the tests); no root needed there
ROOT="${PLUGIN_SORT_ROOT:-/Library/Audio/Plug-Ins}"
needs_root() { [ -z "$PLUGIN_SORT_ROOT" ] && [ "$EUID" -ne 0 ]; }
FORMATS="${PLUGIN_SORT_FORMATS:-VST3 VST}"
COMPONENTS="$ROOT/Components"

usage() {
  cat <<EOF
Usage:
  $0                    dry run: show what would be moved
  sudo $0 --apply       move plugins, write a move log to \$HOME
  sudo $0 --undo LOG    move everything from LOG back
  sudo $0 --restore-au  move Audio Units sorted by older versions back to Components
  sudo $0 --trash PATH… move plugin bundles to the user's Trash

Environment:
  PLUGIN_SORT_FORMATS  folders to process (default: "VST3 VST", Components is ignored)
  PLUGIN_SORT_LOG_DIR  where to write the move log (default: invoking user's home)
  PLUGIN_SORT_OWNER    user that should own the log (default: \$SUDO_USER)
  PLUGIN_SORT_ROOT     plugin tree to work on (default: /Library/Audio/Plug-Ins)
  PLUGIN_SORT_TRASH    where --trash moves bundles (default: the owner's ~/.Trash)
EOF
}

lower() { echo "$1" | tr '[:upper:]' '[:lower:]'; }

# Display names for vendor ids (bash 3.2 on macOS has no associative arrays)
pretty_name() {
  case "$(lower "$1")" in
    fabfilter)       echo "FabFilter" ;;
    izotope)         echo "iZotope" ;;
    kilohearts)      echo "Kilohearts" ;;
    valhalladsp)     echo "Valhalla DSP" ;;
    xfer)            echo "Xfer Records" ;;
    cableguys)       echo "Cableguys" ;;
    output)          echo "Output" ;;
    deviousmachines) echo "Devious Machines" ;;
    xlnaudio)        echo "XLN Audio" ;;
    image-line)      echo "Image-Line" ;;
    camelaudio)      echo "Camel Audio" ;;
    cradle)          echo "Cradle" ;;
    antares)         echo "Antares" ;;
    soniccharge)     echo "Sonic Charge" ;;
    nativeinstruments|native-instruments) echo "Native Instruments" ;;
    u-he)            echo "u-he" ;;
    arturia)         echo "Arturia" ;;
    gvst)            echo "GVST" ;;
    roland)          echo "Roland" ;;
    *)               echo "$1" ;;
  esac
}

# com.fabfilter.X -> fabfilter, co.uk.gvst.X -> gvst, app.cradle.X -> cradle, audio.output.X -> output
vendor_from_id() {
  local IFS=. part
  for part in $1; do
    case "$(lower "$part")" in
      com|co|uk|net|org|io|app|audio|de|fr|nl|se|dk|ch|at|it|jp|au|ca|us) continue ;;
      *) echo "$part"; return ;;
    esac
  done
}

# Reuse an existing vendor folder even if its case differs (Kilohearts vs kiloHearts)
existing_dir() {
  local dir="$1" name="$2" d
  shopt -s nocasematch
  for d in "$dir"/*/; do
    d="${d%/}"; d="${d##*/}"
    case "$d" in *.vst3|*.vst|*.component) continue ;; esac
    if [[ "$d" == "$name" ]]; then shopt -u nocasematch; echo "$d"; return; fi
  done
  shopt -u nocasematch
  echo "$name"
}

undo() {
  [ -f "$1" ] || { echo "No such log: $1"; exit 1; }
  tail -r "$1" | while IFS=$'\t' read -r src dst; do
    if [ -e "$dst" ] && [ ! -e "$src" ]; then
      mv "$dst" "$src" && echo "restored: ${dst#$ROOT/} -> ${src#$ROOT/}"
    else
      echo "skip: ${dst#$ROOT/}"
    fi
  done
  drop_empty_vendor_dirs
  mv "$1" "$1.undone"
}

drop_empty_vendor_dirs() {
  local fmt
  for fmt in VST3 VST Components; do
    [ -d "$ROOT/$fmt" ] && find "$ROOT/$fmt" -mindepth 1 -maxdepth 1 -type d ! -name '*.*' -empty -delete
  done
}

# Moves back every component recorded in the move logs (versions before 1.1 sorted AU too)
restore_au() {
  local log src dst restored=0
  for log in "$LOG_DIR"/plugin-sort-*.log; do
    [ -f "$log" ] || continue
    while IFS=$'\t' read -r src dst; do
      case "$src" in "$COMPONENTS"/*) ;; *) continue ;; esac
      if [ -e "$dst" ] && [ ! -e "$src" ]; then
        mv "$dst" "$src" && echo "restored: ${dst#$ROOT/} -> ${src#$ROOT/}" && restored=$((restored + 1))
      fi
    done < "$log"
  done
  drop_empty_vendor_dirs
  # make macOS rescan Audio Units
  killall -9 AudioComponentRegistrar 2>/dev/null
  echo "Restored AU: $restored"
}

# Moves plugin bundles to the owner's Trash. Only bundles inside $ROOT are accepted.
trash_plugins() {
  local trash p name dest
  trash="${PLUGIN_SORT_TRASH:-$(eval echo ~"${OWNER:-$USER}")/.Trash}"
  for p in "$@"; do
    case "$p" in
      *"/../"*) echo "skip: $p"; continue ;;
      "$ROOT"/*.vst3|"$ROOT"/*.vst|"$ROOT"/*.component|"$ROOT"/*.clap) ;;
      *) echo "skip: $p"; continue ;;
    esac
    [ -e "$p" ] || { echo "skip: $p"; continue; }
    name="${p##*/}"
    dest="$trash/$name"
    [ -e "$dest" ] && dest="$trash/${name%.*} $(date +%H.%M.%S).${name##*.}"
    mv "$p" "$dest" || continue
    [ -n "$OWNER" ] && chown -R "$OWNER" "$dest"
    echo "trashed: ${p#$ROOT/}"
  done
  drop_empty_vendor_dirs
  killall -9 AudioComponentRegistrar 2>/dev/null
}

nested_au() {
  find "$COMPONENTS" -mindepth 2 -maxdepth 2 -name '*.component' 2>/dev/null | wc -l | tr -d ' '
}

# The app passes log dir and owner explicitly: osascript runs without SUDO_USER
OWNER="${PLUGIN_SORT_OWNER:-$SUDO_USER}"
LOG_DIR="${PLUGIN_SORT_LOG_DIR:-$HOME}"
[ -z "$PLUGIN_SORT_LOG_DIR" ] && [ -n "$SUDO_USER" ] && LOG_DIR=$(eval echo ~"$SUDO_USER")

MODE="dry"
case "$1" in
  --apply)      MODE="apply" ;;
  --undo)       undo "$2"; exit ;;
  --restore-au) needs_root && { echo "Root required: sudo $0 --restore-au"; exit 1; }
                restore_au; exit ;;
  --trash)      needs_root && { echo "Root required: sudo $0 --trash PATH…"; exit 1; }
                shift; trash_plugins "$@"; exit ;;
  "")           ;;
  *)            usage; exit 1 ;;
esac

if [ "$MODE" = "apply" ] && needs_root; then
  echo "Root required: sudo $0 --apply"; exit 1
fi

LOG="$LOG_DIR/plugin-sort-$(date +%Y%m%d-%H%M%S).log"
moved=0

for fmt in $FORMATS; do
  dir="$ROOT/$fmt"
  [ "$fmt" = "Components" ] && continue
  [ -d "$dir" ] || continue
  echo "== $fmt"
  for plug in "$dir"/*.vst3 "$dir"/*.vst "$dir"/*.component; do
    [ -e "$plug" ] || continue
    name="${plug##*/}"

    # Waves plugins are managed by Waves Central — leave them alone
    case "$name" in WaveShell*) echo "  skip (Waves): $name"; continue ;; esac

    # Bundles another plugin loads from a fixed path (Serum 2's AU wraps its VST3)
    case "$name" in Serum2.vst3) echo "  keep: $name"; continue ;; esac

    id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plug/Contents/Info.plist" 2>/dev/null)
    vendor=$(vendor_from_id "$id")
    if [ -z "$vendor" ]; then
      echo "  unknown vendor: $name"; continue
    fi
    folder=$(existing_dir "$dir" "$(pretty_name "$vendor")")
    dest="$dir/$folder/$name"

    if [ -e "$dest" ]; then
      echo "  exists: $folder/$name"; continue
    fi

    echo "  $name -> $folder/"
    if [ "$MODE" = "apply" ]; then
      mkdir -p "$dir/$folder" && mv "$plug" "$dest" && printf '%s\t%s\n' "$plug" "$dest" >> "$LOG"
    fi
    moved=$((moved + 1))
  done
done

echo
nested=$(nested_au)
[ "$nested" -gt 0 ] && echo "nested AU: $nested (run --restore-au)"
if [ "$MODE" = "apply" ]; then
  [ -n "$OWNER" ] && [ -f "$LOG" ] && chown "$OWNER" "$LOG"
  echo "Moved: $moved"
  [ -f "$LOG" ] && echo "Log: $LOG (undo: sudo $0 --undo \"$LOG\")"
else
  echo "Would move: $moved (dry run, use --apply to move)"
fi
