#!/bin/bash
# Builds Pandulipi.app into ./build. Usage: ./build.sh [--zip] [--install]
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${VERSION:-1.0.0}"
APP="build/Pandulipi.app"

echo "▸ Compiling (release)…"
swift build -c release

echo "▸ Making icon…"
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
[ -f Resources/icon-1024.png ] || swift Scripts/make_icon.swift Resources/icon-1024.png
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d Resources/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o build/AppIcon.icns

echo "▸ Assembling bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/Pandulipi" "$APP/Contents/MacOS/"
cp build/AppIcon.icns "$APP/Contents/Resources/"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1

if [[ " $* " == *" --zip "* ]]; then
  ZIP="build/Pandulipi-$VERSION-macOS-$(uname -m).zip"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "▸ Zipped: $ZIP"
fi

if [[ " $* " == *" --install "* ]]; then
  rm -rf /Applications/Pandulipi.app
  cp -R "$APP" /Applications/
  echo "▸ Installed to /Applications/Pandulipi.app"
fi

echo "✓ Built $APP"
