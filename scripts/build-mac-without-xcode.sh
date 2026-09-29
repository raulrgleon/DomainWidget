#!/bin/zsh
# Compila la app de macOS solo con las Command Line Tools (sin xcodebuild ni catálogo de assets).
# Útil para probar cambios cuando Xcode no está disponible. Resultado: build/cli/DomainWidget.app
set -e
cd "$(dirname "$0")/.."
app="build/cli/DomainWidget.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

swiftc -O -parse-as-library \
  -target "$(uname -m)-apple-macos14.0" \
  $(find DomainWidget -name "*.swift") \
  -o "$app/Contents/MacOS/DomainWidget"

cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>DomainWidget</string>
	<key>CFBundleIdentifier</key><string>com.raul.DomainWidget.dev</string>
	<key>CFBundleName</key><string>DomainWidget</string>
	<key>CFBundleDisplayName</key><string>Datos de dominio (dev)</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>2.0</string>
	<key>CFBundleVersion</key><string>2</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>NSPrincipalClass</key><string>NSApplication</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
</dict>
</plist>
EOF

iconset="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$iconset"
cp DomainWidget/Assets.xcassets/AppIcon.appiconset/icon_*x*.png "$iconset/"
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$app"
echo "$app"
