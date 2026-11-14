#!/bin/zsh
# Baut Eppur als Universal-App (Apple Silicon + Intel), signiert mit „Eppur Local Signing“,
# packt sie als ZIP und veröffentlicht sie als GitHub-Release v<MARKETING_VERSION>.
# Die Update-Funktion der App lädt genau dieses ZIP („Eppur-<Version>.zip“).
#
#   Eppur/scripts/release.sh            # bauen, prüfen, Release anlegen
#   Eppur/scripts/release.sh --dry-run  # nur bauen und prüfen
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROJECT="$ROOT/Eppur/Eppur.xcodeproj"
VERSION=$(sed -n 's/.*"MARKETING_VERSION": "\(.*\)".*/\1/p' "$PROJECT/project.xcproj" | head -1)
DERIVED="$ROOT/Eppur/.build-xcode/release"
DIST="$ROOT/dist"
ZIP="$DIST/Eppur-$VERSION.zip"
TAG="v$VERSION"

[[ -n "$VERSION" ]] || { echo "MARKETING_VERSION nicht gefunden" >&2; exit 1; }
if [[ "${1:-}" != "--dry-run" ]]; then
  [[ -z "$(git -C "$ROOT" status --porcelain)" ]] || { echo "Arbeitskopie nicht sauber – erst committen." >&2; exit 1; }
  git -C "$ROOT" fetch -q origin
  [[ "$(git -C "$ROOT" rev-parse HEAD)" == "$(git -C "$ROOT" rev-parse origin/main)" ]] \
    || { echo "HEAD ist nicht origin/main – erst pushen." >&2; exit 1; }
fi

echo "▸ Baue Eppur $VERSION (arm64 + x86_64)"
rm -rf "$DERIVED"
xcodebuild build \
  -project "$PROJECT" -scheme Eppur -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$DERIVED" \
  ONLY_ACTIVE_ARCH=NO -quiet
APP="$DERIVED/Build/Products/Release/Eppur.app"

echo "▸ Prüfe"
ARCHS=$(lipo -archs "$APP/Contents/MacOS/Eppur")
[[ "$ARCHS" == *arm64* && "$ARCHS" == *x86_64* ]] || { echo "Keine Universal-App: $ARCHS" >&2; exit 1; }
codesign --verify --strict --deep "$APP"
SIGNATURE=$(codesign -dvv "$APP" 2>&1)
[[ "$SIGNATURE" == *"Authority=Eppur Local Signing"* ]] \
  || { echo "Nicht mit „Eppur Local Signing“ signiert" >&2; exit 1; }
BUILT=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
[[ "$BUILT" == "$VERSION" ]] || { echo "Version $BUILT ≠ $VERSION" >&2; exit 1; }
echo "  $ARCHS · Version $BUILT · signiert"

mkdir -p "$DIST"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "▸ $ZIP ($(du -h "$ZIP" | cut -f1))"

[[ "${1:-}" == "--dry-run" ]] && exit 0

echo "▸ GitHub-Release $TAG"
gh release create "$TAG" "$ZIP" --repo tpa339/eppur --title "Eppur $VERSION" --generate-notes
gh release view "$TAG" --repo tpa339/eppur --json tagName,assets --jq '.tagName + " · " + (.assets | map(.name) | join(", "))'
