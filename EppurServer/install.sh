#!/bin/zsh
# Baut den Eppur-Dienst (Release) und installiert ihn dorthin, wo die App ihn startet:
#   ~/Library/Application Support/Eppur/bin/eppur-server
# Voraussetzung: Xcode mit Metal Toolchain (xcodebuild -downloadComponent MetalToolchain).
set -euo pipefail

cd "$(dirname "$0")"
DERIVED=".build-xcode"
DEST="$HOME/Library/Application Support/Eppur/bin"

xcodebuild build \
  -scheme EppurServer \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  -skipMacroValidation \
  -quiet

PRODUCTS="$DERIVED/Build/Products/Release"
mkdir -p "$DEST"
rm -rf "$DEST"/*.bundle(N)
cp "$PRODUCTS/eppur-server" "$DEST/"
# Metal-Shader (default.metallib) und weitere Ressourcen liegen in Bundles neben dem Binary.
for bundle in "$PRODUCTS"/*.bundle(N); do
  cp -R "$bundle" "$DEST/"
done

echo "Installiert: $DEST/eppur-server"
echo "Test: curl -s http://127.0.0.1:47823/health"
