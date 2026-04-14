#!/bin/sh
set -eu
set -o pipefail

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PKG_PATH=""
REQUIRE_SIGNED="0"

if [ "$#" -gt 2 ]; then
  echo "Too many arguments. Usage: $0 [--signed] <package>" >&2
  exit 1
fi

if [ "$#" -ge 1 ]; then
  if [ "$1" = "--signed" ]; then
    REQUIRE_SIGNED="1"
    PKG_PATH="${2:-}"
  else
    PKG_PATH="$1"
  fi
fi

if [ -z "$PKG_PATH" ]; then
  PKG_PATH="$(cd "$REPO_DIR" && ls -1t dist/DevStackMenu-*.pkg 2>/dev/null | head -n 1 || true)"
fi

if [ -z "$PKG_PATH" ] || [ ! -f "$PKG_PATH" ]; then
  echo "Package not found. Provide a path: ./Scripts/release-smoke-install.sh dist/DevStackMenu-...pkg" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
TMP_LOG="$TMP_DIR/release-install.log"
TMP_PAYLOAD="$TMP_DIR/payload.txt"
TMP_DX_STATUS="$TMP_DIR/dx-status.txt"
TMP_DX_STATUS_ERR="$TMP_DIR/dx-status.err"
trap 'rm -rf "$TMP_DIR"' EXIT

printf 'Using package: %s\n' "$PKG_PATH"
"$REPO_DIR/Scripts/verify-package.sh" "$PKG_PATH" "$REQUIRE_SIGNED"

printf 'Inspecting payload paths:\n'
pkgutil --payload-files "$PKG_PATH" | sort > "$TMP_PAYLOAD"
cat "$TMP_PAYLOAD"
printf '\n'

if [ "$REQUIRE_SIGNED" = "1" ] && ! pkgutil --check-signature "$PKG_PATH" >/dev/null 2>&1; then
  echo "Package signature is required but missing." >&2
  exit 1
fi

printf 'Installing package (requires sudo)...\n'
if [ "$(id -u)" -eq 0 ]; then
  installer -pkg "$PKG_PATH" -target / | tee "$TMP_LOG"
else
  sudo installer -pkg "$PKG_PATH" -target / | tee "$TMP_LOG"
fi

printf 'Verifying installed artifacts...\n'
if [ ! -x /usr/local/bin/dx ]; then
  echo "dx missing in /usr/local/bin" >&2
  exit 1
fi

if [ ! -d "/Applications/DevStackMenu.app" ]; then
  echo "DevStackMenu.app missing in /Applications" >&2
  exit 1
fi

if [ ! -d "/Applications/Import Compose To DX.app" ]; then
  echo "Import Compose To DX.app missing in /Applications" >&2
  exit 1
fi

if /usr/local/bin/dx status >"$TMP_DX_STATUS" 2>"$TMP_DX_STATUS_ERR"; then
  printf 'dx status: '
  cat "$TMP_DX_STATUS"
else
  echo "dx failed to run" >&2
  cat "$TMP_DX_STATUS_ERR"
  exit 1
fi

if command -v dx >/dev/null 2>&1; then
  printf 'dx path from PATH: %s\n' "$(command -v dx)"
else
  printf 'dx is not on current PATH. Binary is at /usr/local/bin/dx\n'
  printf 'You can add it for this shell with: export PATH="/usr/local/bin:$PATH"\n'
  printf 'In zsh, run `rehash` after install to refresh command cache.\n'
fi

printf '\nSmoke install passed.\n'
printf 'To clean artifacts: sudo rm -rf /Applications/DevStackMenu.app /Applications/Import\\ Compose\\ To\\ DX.app /usr/local/bin/dx\n'
