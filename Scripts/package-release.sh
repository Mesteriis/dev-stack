#!/bin/sh
set -eu

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$REPO_DIR/dist}"
CONFIGURATION="${CONFIGURATION:-release}"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$REPO_DIR/Resources/Info.plist" 2>/dev/null || printf '%s' '0.0.0')"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$REPO_DIR/Resources/Info.plist" 2>/dev/null || printf '%s' '1')"
PKG_NAME="DevStackMenu-${VERSION}-${BUILD_NUMBER}.pkg"
PACKAGE_ID="local.devstackmenu.pkg"
PKG_PATH="$BUILD_DIR/$PKG_NAME"
PKG_ROOT_DIR="$BUILD_DIR/pkgroot"

rm -rf "$PKG_ROOT_DIR"
mkdir -p "$PKG_ROOT_DIR/Applications" "$PKG_ROOT_DIR/usr/local/bin"

"$REPO_DIR/Scripts/build-app.sh"

swift build \
  -c "$CONFIGURATION" \
  --package-path "$REPO_DIR" \
  --product dx

BIN_DIR="$(swift build -c "$CONFIGURATION" --package-path "$REPO_DIR" --show-bin-path)"
DX_BIN="$BIN_DIR/dx"

if [ ! -x "$DX_BIN" ]; then
  printf 'dx binary not found at %s\n' "$DX_BIN" >&2
  exit 1
fi

ditto "$BUILD_DIR/DevStackMenu.app" "$PKG_ROOT_DIR/Applications/DevStackMenu.app"
ditto "$BUILD_DIR/Import Compose To DX.app" "$PKG_ROOT_DIR/Applications/Import Compose To DX.app"
ditto "$DX_BIN" "$PKG_ROOT_DIR/usr/local/bin/dx"

chmod 755 "$PKG_ROOT_DIR/usr/local/bin/dx"

pkgbuild \
  --scripts "$REPO_DIR/Scripts/pkg-scripts" \
  --root "$PKG_ROOT_DIR" \
  --identifier "$PACKAGE_ID" \
  --version "$VERSION" \
  --install-location / \
  "$PKG_PATH"

printf 'Package created: %s\n' "$PKG_PATH"
