#!/bin/zsh
# Compila con xcodebuild. Uso:
#   scripts/build.sh mac                 # app de macOS (Debug)
#   scripts/build.sh sim ["iPhone 16"]   # compila, instala y abre en el simulador de iOS
#   scripts/build.sh device              # compila para iPhone físico (firma automática)
set -e
cd "$(dirname "$0")/.."
project=DomainWidget.xcodeproj
scheme=DomainWidget
derived=build/xcode
bundle_id=com.raul.DomainWidget

case "${1:-mac}" in
  mac)
    xcodebuild -project $project -scheme $scheme -configuration Debug \
      -destination 'platform=macOS' -derivedDataPath $derived build
    echo "$derived/Build/Products/Debug/DomainWidget.app"
    ;;
  sim)
    device="${2:-$(xcrun simctl list devices available | grep -m1 -oE 'iPhone[^(]+' | sed 's/ *$//')}"
    echo "Simulador: $device"
    xcodebuild -project $project -scheme $scheme -configuration Debug \
      -destination "platform=iOS Simulator,name=$device" -derivedDataPath $derived build
    xcrun simctl boot "$device" 2>/dev/null || true
    open -a Simulator
    xcrun simctl install "$device" "$derived/Build/Products/Debug-iphonesimulator/DomainWidget.app"
    xcrun simctl launch "$device" $bundle_id
    ;;
  device)
    xcodebuild -project $project -scheme $scheme -configuration Debug \
      -destination 'generic/platform=iOS' -derivedDataPath $derived \
      -allowProvisioningUpdates build
    echo "Instálala desde Xcode (Product > Run con tu iPhone seleccionado) o con:"
    echo "  xcrun devicectl device install app --device <UDID> $derived/Build/Products/Debug-iphoneos/DomainWidget.app"
    ;;
  *)
    echo "Uso: $0 mac|sim [nombre]|device" >&2
    exit 1
    ;;
esac
