#!/bin/sh
set -eu

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <package-path> [require-signed-flag]" >&2
  echo "Example: $0 dist/DevStackMenu-0.1.0-1.pkg 0" >&2
  exit 1
fi

PACKAGE_PATH="$1"
REQUIRE_SIGNED="${2:-0}"

if [ ! -f "$PACKAGE_PATH" ]; then
  echo "Package not found: $PACKAGE_PATH" >&2
  exit 1
fi

PAYLOAD_LIST="$(mktemp)"
trap 'rm -f "$PAYLOAD_LIST"' EXIT

echo "Checking payload for $PACKAGE_PATH"
pkgutil --payload-files "$PACKAGE_PATH" | sort > "$PAYLOAD_LIST"

for REQUIRED in \
  "./Applications/DevStackMenu.app" \
  "./Applications/Import Compose To DX.app" \
  "./Library/LaunchAgents/local.devstackmenu.autostart.plist" \
  "./usr/local/bin/dx"
do
  if ! grep -Fxq "$REQUIRED" "$PAYLOAD_LIST"; then
    echo "Required payload path missing: $REQUIRED" >&2
    exit 1
  fi
done

echo "Payload paths validated"

if ! pkgutil --check-signature "$PACKAGE_PATH" > /tmp/devstack-package-signature.txt 2>&1; then
  if [ "$REQUIRE_SIGNED" = "1" ]; then
    echo "Package signature check failed but signing is required" >&2
    cat /tmp/devstack-package-signature.txt >&2
    exit 1
  fi
  echo "Package is not signed (expected in unsigned CI mode)"
  cat /tmp/devstack-package-signature.txt
  exit 0
fi

echo "Package signature is present"
