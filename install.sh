#!/bin/zsh
# Eppur installieren: lokales Signaturzertifikat (einmalig), Dienst und App bauen,
# App nach /Applications kopieren und starten.
#
# Voraussetzungen: Xcode 27+ mit Metal Toolchain
#   xcodebuild -downloadComponent MetalToolchain
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_DEST="/Applications/Eppur.app"

echo "▸ 1/4 Signaturzertifikat prüfen"
"$ROOT/Eppur/scripts/create-signing-cert.sh"

echo "▸ 2/4 Dienst bauen und installieren (Parakeet + Qwen)"
"$ROOT/EppurServer/install.sh"

echo "▸ 3/4 App bauen (Release)"
DERIVED="$ROOT/Eppur/.build-xcode"
xcodebuild build \
  -project "$ROOT/Eppur/Eppur.xcodeproj" \
  -scheme Eppur \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  -quiet

echo "▸ 4/4 Nach /Applications installieren"
rm -rf "$APP_DEST"
cp -R "$DERIVED/Build/Products/Release/Eppur.app" "$APP_DEST"
# -n: immer eine neue Instanz starten. Ohne -n holt macOS nur die laufende (alte)
# App nach vorn. Die neue Instanz beendet die alte selbst und ersetzt den Dienst.
open -n "$APP_DEST"

echo
echo "Fertig: $APP_DEST"
echo "Beim ersten Start fragt Eppur einmalig nach Mikrofon, Bedienungshilfen und (optional) Bildschirmaufnahme."
