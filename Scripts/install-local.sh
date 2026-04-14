#!/bin/sh
set -eu

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$REPO_DIR/dist}"
APPLICATIONS_DIR="${APPLICATIONS_DIR:-$HOME/Applications}"

"$REPO_DIR/Scripts/build-app.sh"

mkdir -p "$APPLICATIONS_DIR"
ditto "$BUILD_DIR/DevStackMenu.app" "$APPLICATIONS_DIR/DevStackMenu.app"
ditto "$BUILD_DIR/Import Compose To DX.app" "$APPLICATIONS_DIR/Import Compose To DX.app"
touch "$APPLICATIONS_DIR"

printf 'Installed %s\n' "$APPLICATIONS_DIR/DevStackMenu.app"
printf 'Installed %s\n' "$APPLICATIONS_DIR/Import Compose To DX.app"
