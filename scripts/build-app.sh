#!/bin/sh
# Builds release binaries and assembles build/Crow's Nest.app (no Xcode required).
#   VERSION=0.2.0 ./scripts/build-app.sh    set the version shown in Finder and About
#   UNIVERSAL=1 ./scripts/build-app.sh      Apple silicon + Intel in one app (for downloads)
set -eu
cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.1.0}"
if [ "${UNIVERSAL:-0}" = "1" ]; then
  # Built per architecture and joined with lipo: the one-step multi-arch build needs full Xcode.
  swift build -c release --triple arm64-apple-macosx14.0
  swift build -c release --triple x86_64-apple-macosx14.0
  ARM="$(swift build -c release --triple arm64-apple-macosx14.0 --show-bin-path)"
  X86="$(swift build -c release --triple x86_64-apple-macosx14.0 --show-bin-path)"
  BIN="build/universal"
  rm -rf "$BIN"; mkdir -p "$BIN"
  for f in CrowsNestApp crowsnest-bridge; do lipo -create "$ARM/$f" "$X86/$f" -output "$BIN/$f"; done
else
  swift build -c release
  BIN="$(swift build -c release --show-bin-path)"
fi
APP="build/Crow's Nest.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
# App icon: rendered from the pixel bot by the app itself, then packed into an .icns.
rm -rf build/AppIcon.iconset
"$BIN/CrowsNestApp" --render-icon build/AppIcon.iconset >/dev/null
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cp "$BIN/CrowsNestApp" "$APP/Contents/MacOS/Crow's Nest"
cp "$BIN/crowsnest-bridge" "$APP/Contents/Helpers/crowsnest-bridge"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Crow's Nest</string>
  <key>CFBundleDisplayName</key><string>Crow's Nest</string>
  <key>CFBundleIdentifier</key><string>io.github.goodguyej.crowsnest</string>
  <key>CFBundleExecutable</key><string>Crow's Nest</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>__VERSION__</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Crow's Nest asks your terminal app to bring the right tab to the front when you click a session.</string>
</dict>
</plist>
PLIST
sed -i '' "s/__VERSION__/$VERSION/" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP/Contents/Helpers/crowsnest-bridge" >/dev/null 2>&1
codesign --force --sign - "$APP" >/dev/null 2>&1
echo "Built $APP"
