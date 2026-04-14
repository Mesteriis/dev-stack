#!/bin/sh
set -eu

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$REPO_DIR/dist}"
CONFIGURATION="${CONFIGURATION:-release}"
APP_DIR="$BUILD_DIR/DevStackMenu.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
IMPORTER_APP="$BUILD_DIR/Import Compose To DX.app"

rm -rf "$APP_DIR" "$IMPORTER_APP"
mkdir -p "$BUILD_DIR" "$MACOS_DIR" "$CONTENTS_DIR/Resources"

swift build \
  -c "$CONFIGURATION" \
  --package-path "$REPO_DIR" \
  --product DevStackMenu

BIN_DIR="$(swift build -c "$CONFIGURATION" --package-path "$REPO_DIR" --show-bin-path)"

cp "$REPO_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$BIN_DIR/DevStackMenu" "$MACOS_DIR/DevStackMenu"

osacompile -o "$IMPORTER_APP" "$REPO_DIR/Resources/ImportComposeToDX.applescript"

/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string Import Compose To DX" "$IMPORTER_APP/Contents/Info.plist" >/dev/null 2>&1 || /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Import Compose To DX" "$IMPORTER_APP/Contents/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Add :CFBundleName string Import Compose To DX" "$IMPORTER_APP/Contents/Info.plist" >/dev/null 2>&1 || /usr/libexec/PlistBuddy -c "Set :CFBundleName Import Compose To DX" "$IMPORTER_APP/Contents/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string local.devstackmenu.import-compose" "$IMPORTER_APP/Contents/Info.plist" >/dev/null 2>&1 || /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier local.devstackmenu.import-compose" "$IMPORTER_APP/Contents/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$IMPORTER_APP/Contents/Info.plist" >/dev/null 2>&1 || /usr/libexec/PlistBuddy -c "Set :LSUIElement true" "$IMPORTER_APP/Contents/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Delete :CFBundleDocumentTypes" "$IMPORTER_APP/Contents/Info.plist" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes array" "$IMPORTER_APP/Contents/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0 dict" "$IMPORTER_APP/Contents/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:CFBundleTypeName string YAML File" "$IMPORTER_APP/Contents/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:CFBundleTypeRole string Viewer" "$IMPORTER_APP/Contents/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:LSHandlerRank string Alternate" "$IMPORTER_APP/Contents/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:CFBundleTypeExtensions array" "$IMPORTER_APP/Contents/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:CFBundleTypeExtensions:0 string yml" "$IMPORTER_APP/Contents/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:CFBundleTypeExtensions:1 string yaml" "$IMPORTER_APP/Contents/Info.plist" >/dev/null

touch "$APP_DIR"
printf 'Built %s\n' "$APP_DIR"
printf 'Built %s\n' "$IMPORTER_APP"
