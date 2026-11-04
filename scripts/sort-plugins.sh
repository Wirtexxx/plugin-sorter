#!/bin/bash
# plugin-sorter — moves audio plugins in /Library/Audio/Plug-Ins/{VST3,VST}
# into developer folders. The developer is taken from the bundle's CFBundleIdentifier
# (com.fabfilter.Pro-Q.3 -> FabFilter).
#
# Audio Units are never sorted: macOS only registers components that sit directly
# in Components, so an AU inside a subfolder disappears from every host.

# Root trusts nothing from its environment: these would move the allow-lists and the Trash. The
# overrides are for the tests, which run as a normal user.
if [ "$EUID" -eq 0 ]; then
  unset PLUGIN_SORT_ROOT PLUGIN_SORT_DATA_ROOTS PLUGIN_SORT_TRASH
fi

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
  sudo $0 --trash-data PATH…    move leftovers in the shared data folders to the Trash
  sudo $0 --forget-receipt PKGID…  forget installer receipts
                        (the three may be combined in one call: --trash A --trash-data B --forget-receipt C)
  sudo $0 --disable PATH…  move plugin bundles to Disabled/ so no host sees them, nothing is deleted
  sudo $0 --enable PATH…   move bundles from Disabled/ back to where they were
  sudo $0 --unquarantine PATH…  remove the quarantine flag from plugin bundles
  sudo $0 --relocate SRC DST    move one plugin bundle to another place in the plugin tree
  $0 --reset-au         make macOS rescan Audio Units

Environment:
  PLUGIN_SORT_FORMATS  folders to process (default: "VST3 VST", Components is ignored)
  PLUGIN_SORT_LOG_DIR  where to write the move log (default: invoking user's home)
  PLUGIN_SORT_OWNER    user that should own the log (default: \$SUDO_USER)
  PLUGIN_SORT_ROOT     plugin tree to work on (default: /Library/Audio/Plug-Ins)
  PLUGIN_SORT_DATA_ROOTS  colon-separated folders --trash-data may work in
                       (default: /Library/Application Support:/Library/Audio/Presets)
  PLUGIN_SORT_TRASH    where --trash moves bundles (default: the owner's ~/.Trash)
  PLUGIN_SORT_KEEP_FILE  file with bundle names (one per line) to leave in place when sorting
EOF
}

lower() { echo "$1" | tr '[:upper:]' '[:lower:]'; }

# Bundles another plugin loads from a fixed path stay where they are: Serum 2's AU wraps its
# VST3 at VST3/Serum2.vst3. The app adds more to PLUGIN_SORT_KEEP_FILE when it finds them.
is_kept() {
  case "$1" in Serum2.vst3) return 0 ;; esac
  [ -n "$PLUGIN_SORT_KEEP_FILE" ] && [ -f "$PLUGIN_SORT_KEEP_FILE" ] && grep -Fxq -- "$1" "$PLUGIN_SORT_KEEP_FILE"
}

# True when no part of a path below $ROOT is a symlink: a link planted in one of the (world-writable)
# format folders must not lead a privileged move out of the tree. $ROOT itself may be spelled any way.
no_symlinks_below_root() {
  local p="$1"
  while [ "$p" != "$ROOT" ] && [ -n "$p" ] && [ "$p" != "/" ]; do
    [ -L "$p" ] && return 1
    p="${p%/*}"
  done
  return 0
}

# True for a plugin bundle path inside $ROOT, the only places the privileged commands may touch.
# The extension is matched in any case, as the app's inventory does.
is_plugin_path() {
  case "$1" in
    *"/../"*|*"/./"*) return 1 ;;
    "$ROOT"/?*) ;;
    *) return 1 ;;
  esac
  case "$(lower "${1##*.}")" in
    vst3|vst|component|clap) ;;
    *) return 1 ;;
  esac
  no_symlinks_below_root "$1"
}

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
  set -f   # the id comes from the plugin: a "*" in it must stay a "*"
  for part in $1; do
    case "$(lower "$part")" in
      com|co|uk|net|org|io|app|audio|de|fr|nl|se|dk|ch|at|it|jp|au|ca|us) continue ;;
      *) echo "$part"; break ;;
    esac
  done
  set +f
}

# A vendor from a bundle id becomes a folder name, so only plain names are taken
plain_vendor() {
  case "$1" in ""|*[!A-Za-z0-9._-]*) return 1 ;; esac
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

# The log lives in the user's home, so what it says is not trusted: only moves inside the plugin tree
# are carried out. A log that didn't go through in full is kept, and undoing it again does the rest.
undo() {
  [ -f "$1" ] || { echo "No such log: $1"; exit 1; }
  local src dst failed=0
  while IFS=$'\t' read -r src dst; do
    if ! is_plugin_path "$src" || ! is_plugin_path "$dst"; then
      echo "failed: $dst"; failed=1; continue
    fi
    if [ -e "$dst" ] && [ ! -e "$src" ]; then
      if mv "$dst" "$src"; then
        echo "restored: ${dst#$ROOT/} -> ${src#$ROOT/}"
      else
        echo "failed: ${dst#$ROOT/}"; failed=1
      fi
    else
      echo "skip: ${dst#$ROOT/}"
    fi
  done < <(tail -r "$1")
  drop_empty_vendor_dirs
  [ "$failed" -eq 0 ] || return 1
  mv "$1" "$1.undone"
}

drop_empty_vendor_dirs() {
  local fmt
  for fmt in VST3 VST Components; do
    [ -d "$ROOT/$fmt" ] && find "$ROOT/$fmt" -mindepth 1 -maxdepth 1 -type d ! -name '*.*' -empty -delete
  done
  # Disabled/<format>/<vendor>, then Disabled/<format>, then Disabled itself
  if [ -d "$ROOT/Disabled" ]; then
    find "$ROOT/Disabled" -mindepth 2 -maxdepth 2 -type d ! -name '*.*' -empty -delete
    find "$ROOT/Disabled" -mindepth 1 -maxdepth 1 -type d -empty -delete
    rmdir "$ROOT/Disabled" 2>/dev/null
  fi
  return 0
}

# Moves back every component recorded in the move logs (versions before 1.1 sorted AU too)
restore_au() {
  local log src dst restored=0
  for log in "$LOG_DIR"/plugin-sort-*.log; do
    [ -f "$log" ] || continue
    while IFS=$'\t' read -r src dst; do
      case "$src" in "$COMPONENTS"/*) ;; *) continue ;; esac
      { is_plugin_path "$src" && is_plugin_path "$dst"; } || continue
      if [ -e "$dst" ] && [ ! -e "$src" ]; then
        mv "$dst" "$src" && echo "restored: ${dst#$ROOT/} -> ${src#$ROOT/}" && restored=$((restored + 1))
      fi
    done < "$log"
  done
  # Components that got into subfolders some other way (logs deleted, an installer, by hand)
  local nested name
  while IFS= read -r nested; do
    [ -n "$nested" ] || continue
    name="${nested##*/}"
    if [ -e "$COMPONENTS/$name" ]; then
      echo "skip: ${nested#$ROOT/}"
    else
      mv "$nested" "$COMPONENTS/$name" && echo "restored: ${nested#$ROOT/} -> ${COMPONENTS#$ROOT/}/$name" \
        && restored=$((restored + 1))
    fi
  done <<EOF_NESTED
$(find "$COMPONENTS" -mindepth 2 -maxdepth 2 -name '*.component' 2>/dev/null)
EOF_NESTED
  drop_empty_vendor_dirs
  reset_au_cache
  echo "Restored AU: $restored"
}

# A user name that is safe to look up and to put in a path
valid_user() {
  case "$1" in ""|*[!A-Za-z0-9._-]*) return 1 ;; esac
}

# A user's home folder, from the directory service. Nothing is evaluated.
home_of() {
  local home
  valid_user "$1" || return 1
  home=$(dscl . -read "/Users/$1" NFSHomeDirectory 2>/dev/null | sed -n 's/^NFSHomeDirectory: //p' | head -n 1)
  echo "${home:-/Users/$1}"
}

# Where the owner's Trash is
trash_dir() {
  local home
  if [ -n "$PLUGIN_SORT_TRASH" ]; then echo "$PLUGIN_SORT_TRASH"; return; fi
  home=$(home_of "${OWNER:-$USER}") || return 1
  echo "$home/.Trash"
}

# Moves $1 into the Trash under its own name, or "name 2" while that is taken. Bundles keep their
# extension ("OTT 2.vst3"). Prints the final path.
move_to_trash() {
  local src="$1" trash name dest n
  trash=$(trash_dir) && [ -n "$trash" ] || return 1
  name="${src##*/}"
  dest="$trash/$name"
  n=2
  while [ -e "$dest" ]; do
    case "$(lower "${name##*.}")" in
      vst3|vst|component|clap) dest="$trash/${name%.*} $n.${name##*.}" ;;
      *)                       dest="$trash/$name $n" ;;
    esac
    n=$((n + 1))
  done
  mv "$src" "$dest" || return 1
  [ -n "$OWNER" ] && chown -R "$OWNER" "$dest"
  echo "$dest"
}

# Moves plugin bundles to the owner's Trash. Only bundles inside $ROOT are accepted.
# Fails unless every one of them moved.
trash_plugins() {
  local p all=0
  for p in "$@"; do
    { is_plugin_path "$p" && [ -e "$p" ]; } || { echo "skip: $p"; all=1; continue; }
    move_to_trash "$p" >/dev/null || { echo "failed: $p"; all=1; continue; }
    echo "trashed: ${p#$ROOT/}"
  done
  drop_empty_vendor_dirs
  reset_au_cache
  return $all
}

# Folders under which --trash-data may work: colon-separated, the developers' presets and libraries
DATA_ROOTS="${PLUGIN_SORT_DATA_ROOTS:-/Library/Application Support:/Library/Audio/Presets}"

# True for a path strictly inside one of the data roots: not the root, no "." or ".." parts, not a symlink,
# and none of its folders a symlink either (so it can't lead out of the root).
is_data_path() {
  local p="$1" r parent real_root real_parent IFS=:
  case "$p" in
    *"/../"*|*"/./"*|*/..|*/.|*/) return 1 ;;
  esac
  [ -L "$p" ] && return 1
  for r in $DATA_ROOTS; do
    case "$p" in "$r"/?*) ;; *) continue ;; esac
    parent="${p%/*}"
    real_root=$(cd "$r" 2>/dev/null && pwd -P) || continue
    real_parent=$(cd "$parent" 2>/dev/null && pwd -P) || continue
    # The folder holding it must really be where its spelling says, below the real root
    [ "$real_parent" = "$real_root${parent#"$r"}" ] && return 0
  done
  return 1
}

# Moves leftovers of a plugin (presets, libraries) from the shared data folders to the Trash.
trash_data() {
  local p dest
  for p in "$@"; do
    { is_data_path "$p" && [ -e "$p" ]; } || { echo "skip: $p"; continue; }
    move_to_trash "$p" >/dev/null || { echo "failed: $p"; continue; }
    echo "trashed-data: $p"
  done
}

# Forgets installer receipts. Under PLUGIN_SORT_ROOT (the tests) it only says so.
forget_receipts() {
  local id
  for id in "$@"; do
    case "$id" in
      ""|*[!A-Za-z0-9._-]*|-*|.|..|.*|[Cc][Oo][Mm].[Aa][Pp][Pp][Ll][Ee].*) echo "skip: $id"; continue ;;
    esac
    if [ -n "$PLUGIN_SORT_ROOT" ] || pkgutil --forget "$id" >/dev/null 2>&1; then
      echo "forgot: $id"
    else
      echo "failed: $id"
    fi
  done
}

# --trash PATH… --trash-data PATH… --forget-receipt PKGID…, any of them, one password for all
remove_plugins() {
  local mode="" arg
  local plugins=() data=() receipts=()
  for arg in "$@"; do
    case "$arg" in
      --trash|--trash-data|--forget-receipt) mode="$arg" ;;
      *) case "$mode" in
           --trash)          plugins+=("$arg") ;;
           --trash-data)     data+=("$arg") ;;
           --forget-receipt) receipts+=("$arg") ;;
         esac ;;
    esac
  done
  # Preferences, presets and receipts go only with plugin files that really moved: otherwise the
  # plugin would still be installed, without its settings and without the record of its installer
  if [ "${#plugins[@]}" -gt 0 ] && ! trash_plugins "${plugins[@]}"; then
    echo "failed: the plugin files were not all moved; nothing else was removed"
    return 1
  fi
  [ "${#data[@]}" -gt 0 ] && trash_data "${data[@]}"
  [ "${#receipts[@]}" -gt 0 ] && forget_receipts "${receipts[@]}"
  return 0
}

# True when a path relative to $ROOT starts in a format folder (VST3/…, Components/…)
in_format_folder() {
  case "$1" in VST3/*|VST/*|Components/*|CLAP/*) return 0 ;; *) return 1 ;; esac
}

# Hosts scan the format folders recursively, so a plugin is switched off by moving it out of them,
# to $ROOT/Disabled/<same path>. Never overwrites anything.
disable_plugins() {
  local p rel dest all=0
  for p in "$@"; do
    { is_plugin_path "$p" && [ -e "$p" ]; } || { echo "skip: $p"; all=1; continue; }
    rel="${p#$ROOT/}"
    in_format_folder "$rel" || { echo "skip: $p"; all=1; continue; }
    dest="$ROOT/Disabled/$rel"
    { [ -e "$dest" ] || [ -L "$dest" ] || ! no_symlinks_below_root "$dest"; } && { echo "skip: $p"; all=1; continue; }
    mkdir -p "$(dirname "$dest")" && mv "$p" "$dest" || { echo "failed: $rel"; all=1; continue; }
    echo "disabled: $rel"
  done
  drop_empty_vendor_dirs
  reset_au_cache
  return $all
}

# Moves bundles from $ROOT/Disabled back to their place; a reinstalled plugin there is never overwritten.
enable_plugins() {
  local p rel dest all=0
  for p in "$@"; do
    { is_plugin_path "$p" && [ -e "$p" ]; } || { echo "skip: $p"; all=1; continue; }
    case "$p" in "$ROOT/Disabled/"*) ;; *) echo "skip: $p"; all=1; continue ;; esac
    rel="${p#$ROOT/Disabled/}"
    in_format_folder "$rel" || { echo "skip: $p"; all=1; continue; }
    dest="$ROOT/$rel"
    { [ -e "$dest" ] || [ -L "$dest" ] || ! no_symlinks_below_root "$dest"; } && { echo "skip: $p"; all=1; continue; }
    mkdir -p "$(dirname "$dest")" && mv "$p" "$dest" || { echo "failed: $rel"; all=1; continue; }
    echo "enabled: $rel"
  done
  drop_empty_vendor_dirs
  reset_au_cache
  return $all
}

unquarantine_plugins() {
  local p done=0
  for p in "$@"; do
    { is_plugin_path "$p" && [ -e "$p" ]; } || { echo "skip: $p"; continue; }
    xattr -dr com.apple.quarantine "$p" 2>/dev/null
    if xattr "$p" 2>/dev/null | grep -q com.apple.quarantine; then
      echo "failed: ${p#$ROOT/}"
    else
      echo "unquarantined: ${p#$ROOT/}"
      done=$((done + 1))
    fi
  done
  [ "$done" -gt 0 ]
}

# Moves one bundle within the plugin tree, e.g. a VST3 another plugin expects at a fixed path
relocate_plugin() {
  local src="$1" dst="$2"
  if ! is_plugin_path "$src" || ! is_plugin_path "$dst" || [ ! -e "$src" ] || [ -e "$dst" ] \
     || [ ! -d "$(dirname "$dst")" ] || [ "${src##*.}" != "${dst##*.}" ]; then
    echo "skip: $src"
    return 1
  fi
  mv "$src" "$dst" || { echo "failed: ${src#$ROOT/}"; return 1; }
  echo "relocated: ${src#$ROOT/} -> ${dst#$ROOT/}"
  drop_empty_vendor_dirs
  reset_au_cache
}

# Makes macOS rescan Audio Units. Never fails: the registrar may simply not be running.
reset_au_cache() {
  [ -z "$PLUGIN_SORT_ROOT" ] && killall -9 AudioComponentRegistrar 2>/dev/null
  return 0
}

nested_au() {
  find "$COMPONENTS" -mindepth 2 -maxdepth 2 -name '*.component' 2>/dev/null | wc -l | tr -d ' '
}

# The app passes log dir and owner explicitly: osascript runs without SUDO_USER
OWNER="${PLUGIN_SORT_OWNER:-$SUDO_USER}"
if [ -n "$OWNER" ] && ! valid_user "$OWNER"; then
  echo "Invalid owner name"; exit 1
fi
LOG_DIR="${PLUGIN_SORT_LOG_DIR:-$HOME}"
if [ -z "$PLUGIN_SORT_LOG_DIR" ] && valid_user "$SUDO_USER"; then
  LOG_DIR=$(home_of "$SUDO_USER")
fi

MODE="dry"
case "$1" in
  --apply)      MODE="apply" ;;
  --undo)       needs_root && { echo "Root required: sudo $0 --undo LOG"; exit 1; }
                undo "$2"; exit ;;
  --restore-au) needs_root && { echo "Root required: sudo $0 --restore-au"; exit 1; }
                restore_au; exit ;;
  --trash|--trash-data|--forget-receipt)
                needs_root && { echo "Root required: sudo $0 --trash PATH…"; exit 1; }
                remove_plugins "$@"; exit ;;
  --disable)    needs_root && { echo "Root required: sudo $0 --disable PATH…"; exit 1; }
                shift; disable_plugins "$@"; exit ;;
  --enable)     needs_root && { echo "Root required: sudo $0 --enable PATH…"; exit 1; }
                shift; enable_plugins "$@"; exit ;;
  --unquarantine) needs_root && { echo "Root required: sudo $0 --unquarantine PATH…"; exit 1; }
                shift; unquarantine_plugins "$@"; exit ;;
  --relocate)   needs_root && { echo "Root required: sudo $0 --relocate SRC DST"; exit 1; }
                relocate_plugin "$2" "$3"; exit ;;
  --reset-au)   reset_au_cache; echo "AU cache reset"; exit 0 ;;
  "")           ;;
  *)            usage; exit 1 ;;
esac

if [ "$MODE" = "apply" ] && needs_root; then
  echo "Root required: sudo $0 --apply"; exit 1
fi

moved=0
failed=0

# The log's folder belongs to the user: noclobber refuses a link planted under the log's name, and the
# open descriptor keeps writing to this file whatever happens to its name later
if [ "$MODE" = "apply" ]; then
  created=""
  for attempt in 1 2 3; do
    LOG="$LOG_DIR/plugin-sort-$(date +%Y%m%d-%H%M%S).log"
    if ( set -C; : > "$LOG" ) 2>/dev/null; then created=1; break; fi
    sleep 1   # a run earlier in this second, the names go by the second
  done
  [ -n "$created" ] || { echo "Can't create the log: $LOG"; exit 1; }
  exec 3>>"$LOG"
fi

for fmt in $FORMATS; do
  dir="$ROOT/$fmt"
  [ "$fmt" = "Components" ] && continue
  [ -d "$dir" ] || continue
  echo "== $fmt"
  for plug in "$dir"/*.vst3 "$dir"/*.vst "$dir"/*.component; do
    [ -e "$plug" ] || continue
    name="${plug##*/}"

    # The format folders are often writable by everyone: a link is nothing we put there
    if [ -L "$plug" ]; then echo "  skip: $name"; continue; fi

    # Waves plugins are managed by Waves Central — leave them alone
    case "$name" in WaveShell*) echo "  skip (Waves): $name"; continue ;; esac

    # Bundles another plugin loads from a fixed path (Serum 2's AU wraps its VST3)
    if is_kept "$name"; then echo "  keep: $name"; continue; fi

    id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plug/Contents/Info.plist" 2>/dev/null)
    vendor=$(vendor_from_id "$id")
    if ! plain_vendor "$vendor"; then
      echo "  unknown vendor: $name"; continue
    fi
    folder=$(existing_dir "$dir" "$(pretty_name "$vendor")")
    dest="$dir/$folder/$name"

    # A link in place of a vendor folder would lead the move out of the plugin tree
    if ! no_symlinks_below_root "$dir/$folder"; then echo "  skip: $name"; continue; fi

    if [ -e "$dest" ]; then
      echo "  exists: $folder/$name"; continue
    fi

    if [ "$MODE" = "apply" ]; then
      if mkdir -p "$dir/$folder" && mv "$plug" "$dest"; then
        printf '%s\t%s\n' "$plug" "$dest" >&3
      else
        echo "  failed: $name"; failed=$((failed + 1)); continue
      fi
    fi
    echo "  $name -> $folder/"
    moved=$((moved + 1))
  done
done

echo
nested=$(nested_au)
[ "$nested" -gt 0 ] && echo "nested AU: $nested (run --restore-au)"
if [ "$MODE" = "apply" ]; then
  exec 3>&-
  [ -s "$LOG" ] || rm -f "$LOG"
  [ -n "$OWNER" ] && [ -f "$LOG" ] && chown -h "$OWNER" "$LOG"
  echo "Moved: $moved"
  [ -f "$LOG" ] && echo "Log: $LOG (undo: sudo $0 --undo \"$LOG\")"
else
  echo "Would move: $moved (dry run, use --apply to move)"
fi
[ "$failed" -eq 0 ]
