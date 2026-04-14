#!/bin/sh
set -eu

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$REPO_DIR/dist}"
CONFIGURATION="${CONFIGURATION:-release}"
APP_DIR="$BUILD_DIR/DevStackMenu.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
IMPORTER_APP="$BUILD_DIR/Import Compose To DX.app"
IMPORTER_RESOURCES_DIR="$IMPORTER_APP/Contents/Resources"

remove_or_archive() {
  target="$1"
  [ -e "$target" ] || return 0

  if rm -rf "$target" 2>/dev/null; then
    return 0
  fi

  target_dir="$(dirname "$target")"
  target_name="$(basename "$target")"
  archived_target="$target_dir/.$target_name.stale.$(date +%s).$$"
  mv "$target" "$archived_target"
}

remove_or_archive "$APP_DIR"
remove_or_archive "$IMPORTER_APP"
mkdir -p "$BUILD_DIR" "$MACOS_DIR" "$RESOURCES_DIR"

swift build \
  -c "$CONFIGURATION" \
  --package-path "$REPO_DIR" \
  --product DevStackMenu

BIN_DIR="$(swift build -c "$CONFIGURATION" --package-path "$REPO_DIR" --show-bin-path)"

cp -X "$REPO_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp -X "$REPO_DIR/Resources/DevStackMenu.icns" "$RESOURCES_DIR/DevStackMenu.icns"
cp -X "$BIN_DIR/DevStackMenu" "$MACOS_DIR/DevStackMenu"

osacompile -o "$IMPORTER_APP" "$REPO_DIR/Resources/ImportComposeToDX.applescript"
mkdir -p "$IMPORTER_RESOURCES_DIR"
cp -X "$REPO_DIR/Resources/ImportComposeToDX.icns" "$IMPORTER_RESOURCES_DIR/ImportComposeToDX.icns"
cp -X "$REPO_DIR/Resources/ImportComposeToDX.icns" "$IMPORTER_RESOURCES_DIR/droplet.icns"

/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string Import Compose To DX" "$IMPORTER_APP/Contents/Info.plist" >/dev/null 2>&1 || /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Import Compose To DX" "$IMPORTER_APP/Contents/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Add :CFBundleName string Import Compose To DX" "$IMPORTER_APP/Contents/Info.plist" >/dev/null 2>&1 || /usr/libexec/PlistBuddy -c "Set :CFBundleName Import Compose To DX" "$IMPORTER_APP/Contents/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string local.devstackmenu.import-compose" "$IMPORTER_APP/Contents/Info.plist" >/dev/null 2>&1 || /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier local.devstackmenu.import-compose" "$IMPORTER_APP/Contents/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "$IMPORTER_APP/Contents/Info.plist" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string ImportComposeToDX.icns" "$IMPORTER_APP/Contents/Info.plist" >/dev/null 2>&1 || /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile ImportComposeToDX.icns" "$IMPORTER_APP/Contents/Info.plist" >/dev/null
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

find "$APP_DIR" "$IMPORTER_APP" -exec xattr -c {} + >/dev/null 2>&1 || true

touch "$APP_DIR"
touch "$IMPORTER_APP"
printf 'Built %s\n' "$APP_DIR"
printf 'Built %s\n' "$IMPORTER_APP"
