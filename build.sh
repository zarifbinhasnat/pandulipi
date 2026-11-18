#!/bin/bash
# Builds Pandulipi.app into ./build. Usage: ./build.sh [--universal] [--zip] [--install]
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${VERSION:-1.0.0}"
APP="build/Pandulipi.app"

echo "▸ Compiling (release)…"
bin_for() { # $1 = arm64 | x86_64
  swift build -c release --triple "$1-apple-macosx14.0" >&2
  echo "$(swift build -c release --triple "$1-apple-macosx14.0" --show-bin-path)/Pandulipi"
}
if [[ " $* " == *" --universal "* ]]; then
  ARM_BIN="$(bin_for arm64)"
  echo "▸ Compiling Intel slice…"
  X86_BIN="$(bin_for x86_64)"
  mkdir -p build && lipo -create "$ARM_BIN" "$X86_BIN" -output build/Pandulipi-bin
  BIN=build/Pandulipi-bin
  ARCH=universal
else
  ARCH="$(uname -m)"
  BIN="$(bin_for "$ARCH")"
fi

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
cp "$BIN" "$APP/Contents/MacOS/Pandulipi"
cp build/AppIcon.icns "$APP/Contents/Resources/"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1

if [[ " $* " == *" --zip "* ]]; then
  ZIP="build/Pandulipi-$VERSION-macOS-$ARCH.zip"
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
