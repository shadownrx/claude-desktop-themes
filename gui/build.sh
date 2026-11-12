#!/bin/zsh
# Compila "Temas para Claude.app" y el zip para compartir.
set -euo pipefail
cd ${0:A:h}
OUT=build
APP="$OUT/Temas para Claude.app"
rm -rf $OUT && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 -parse-as-library -target arm64-apple-macos14.0 \
  -o "$OUT/TemasClaude-arm64" TemasClaude.swift
swiftc -O -swift-version 5 -parse-as-library -target x86_64-apple-macos14.0 \
  -o "$OUT/TemasClaude-x86_64" TemasClaude.swift
lipo -create -output "$APP/Contents/MacOS/TemasClaude" $OUT/TemasClaude-arm64 $OUT/TemasClaude-x86_64

cp ../instalar-tema-claude.command "$APP/Contents/Resources/"
cp -R ../proxy ../themes "$APP/Contents/Resources/"

# Ícono
"$APP/Contents/MacOS/TemasClaude" --icon $OUT/icon.png
mkdir -p $OUT/AppIcon.iconset
for s in 16 32 128 256 512; do
  sips -z $s $s $OUT/icon.png --out $OUT/AppIcon.iconset/icon_${s}x${s}.png >/dev/null
  sips -z $((s*2)) $((s*2)) $OUT/icon.png --out $OUT/AppIcon.iconset/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns $OUT/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Temas para Claude</string>
  <key>CFBundleDisplayName</key><string>Temas para Claude</string>
  <key>CFBundleIdentifier</key><string>local.temas-para-claude</string>
  <key>CFBundleExecutable</key><string>TemasClaude</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>2.2</string>
  <key>CFBundleVersion</key><string>22</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

codesign --force --deep --sign - "$APP"
rm -f $OUT/TemasClaude-* && rm -rf $OUT/AppIcon.iconset
(cd $OUT && ditto -c -k --keepParent "Temas para Claude.app" "Temas-para-Claude.zip")
echo "Listo: $PWD/$OUT/Temas para Claude.app y Temas-para-Claude.zip"
