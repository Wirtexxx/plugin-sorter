#!/bin/bash
# Builds "Plugin Sorter.app" — universal (Apple Silicon + Intel), macOS 11+
#
#   ./build.sh               build into build/
#   ./build.sh --install     build and copy to /Applications
#   ./build.sh --screenshot  also render docs/screenshot.png
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Plugin Sorter.app"
TARGET_MACOS=11

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/AppIcon.iconset

echo "› Compiling"
for arch in arm64 x86_64; do
  swiftc -O -parse-as-library -target "$arch-apple-macos$TARGET_MACOS" App/*.swift -o "build/PluginSorter-$arch"
done
lipo -create build/PluginSorter-arm64 build/PluginSorter-x86_64 -output "$APP/Contents/MacOS/PluginSorter"

cp scripts/sort-plugins.sh "$APP/Contents/Resources/sort-plugins.sh"

echo "› Drawing icon"
swiftc tools/icon.swift -o build/icon && build/icon build/icon.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon.png --out "build/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) build/icon.png --out "build/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

VERSION=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Plugin Sorter</string>
  <key>CFBundleDisplayName</key><string>Plugin Sorter</string>
  <key>CFBundleIdentifier</key><string>io.github.wirtexxx.plugin-sorter</string>
  <key>CFBundleExecutable</key><string>PluginSorter</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION:-1.0.0}</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>ru</string><string>uk</string><string>de</string></array>
  <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
  <key>LSMinimumSystemVersion</key><string>$TARGET_MACOS.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

codesign --force -s - "$APP"

if [ "${1:-}" = "--screenshot" ]; then
  echo "› Rendering screenshot"
  # every app source except the @main entry point, which the snapshot tool replaces
  swiftc -parse-as-library -target "$(uname -m)-apple-macos$TARGET_MACOS" \
    $(ls App/*.swift | grep -v PluginSorterApp.swift) tools/snapshot.swift -o build/snapshot
  mkdir -p docs
  build/snapshot docs/screenshot.png en
  cp build/icon.png docs/icon.png
fi

rm -rf build/PluginSorter-* build/icon build/snapshot build/AppIcon.iconset
echo "✓ Built: $APP"

if [ "${1:-}" = "--install" ]; then
  rm -rf "/Applications/Plugin Sorter.app"
  cp -R "$APP" /Applications/
  echo "✓ Installed to /Applications"
fi
