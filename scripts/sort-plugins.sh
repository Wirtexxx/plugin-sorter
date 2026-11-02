#!/bin/bash
# plugin-sorter — moves audio plugins in /Library/Audio/Plug-Ins/{VST3,VST,Components}
# into developer folders. The developer is taken from the bundle's CFBundleIdentifier
# (com.fabfilter.Pro-Q.3 -> FabFilter).

ROOT="/Library/Audio/Plug-Ins"
FORMATS="VST3 VST Components"

usage() {
  cat <<EOF
Usage:
  $0                 dry run: show what would be moved
  sudo $0 --apply    move plugins
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

# com.fabfilter.X -> fabfilter, co.uk.gvst.X -> gvst, app.cradle.X -> cradle
vendor_from_id() {
  local IFS=. part
  for part in $1; do
    case "$(lower "$part")" in
      com|co|uk|net|org|io|app|de|fr|nl|se|dk|ch|at|it|jp|au|ca|us) continue ;;
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

MODE="dry"
case "$1" in
  --apply) MODE="apply" ;;
  "")      ;;
  *)       usage; exit 1 ;;
esac

if [ "$MODE" = "apply" ] && [ "$EUID" -ne 0 ]; then
  echo "Root required: sudo $0 --apply"; exit 1
fi

moved=0

for fmt in $FORMATS; do
  dir="$ROOT/$fmt"
  [ -d "$dir" ] || continue
  echo "== $fmt"
  for plug in "$dir"/*.vst3 "$dir"/*.vst "$dir"/*.component; do
    [ -e "$plug" ] || continue
    name="${plug##*/}"

    # Waves plugins are managed by Waves Central — leave them alone
    case "$name" in WaveShell*) echo "  skip (Waves): $name"; continue ;; esac

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
      mkdir -p "$dir/$folder" && mv "$plug" "$dest"
    fi
    moved=$((moved + 1))
  done
done

echo
if [ "$MODE" = "apply" ]; then
  echo "Moved: $moved"
else
  echo "Would move: $moved (dry run, use --apply to move)"
fi
