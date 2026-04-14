#!/bin/sh
set -eu

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <package-path>" >&2
  echo "Example: $0 dist/DevStackMenu-0.1.0-1.pkg" >&2
  exit 1
fi

PACKAGE_PATH="$1"

IDENTITY="${CODESIGN_INSTALLER_IDENTITY:-}"
CERT_P12_BASE64="${MACOS_INSTALLER_CERT_P12_BASE64:-}"
CERT_PASSWORD="${MACOS_INSTALLER_CERT_PASSWORD:-}"
REQUIRE_NOTARIZE="${REQUIRE_NOTARIZE:-0}"
NOTARY_KEY_ID="${NOTARYTOOL_KEY_ID:-}"
NOTARY_ISSUER="${NOTARYTOOL_ISSUER_ID:-}"
NOTARY_KEY_P8="${NOTARYTOOL_KEY_P8_BASE64:-}"

if [ -z "$IDENTITY" ] && [ -z "$CERT_P12_BASE64" ]; then
  echo "Code signing is not configured. Set CODESIGN_INSTALLER_IDENTITY and MACOS_INSTALLER_CERT_P12_BASE64 to enable signing."
  exit 0
fi

if [ -z "$IDENTITY" ]; then
  echo "CODESIGN_INSTALLER_IDENTITY is not set." >&2
  exit 1
fi

if [ -z "$CERT_P12_BASE64" ] || [ -z "$CERT_PASSWORD" ]; then
  echo "Certificate payload missing. Set MACOS_INSTALLER_CERT_P12_BASE64 and MACOS_INSTALLER_CERT_PASSWORD." >&2
  exit 1
fi

KEYCHAIN_PATH="${RUNNER_TEMP:-/tmp}/devstack-signing.keychain-db"
CERT_FILE="${RUNNER_TEMP:-/tmp}/devstack-installer.p12"
SIGNED_PATH="${PACKAGE_PATH%.pkg}-signed.pkg"

echo "$CERT_P12_BASE64" | base64 --decode > "$CERT_FILE"
security create-keychain -p "" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 7200 "$KEYCHAIN_PATH"
security unlock-keychain "$KEYCHAIN_PATH"
security import "$CERT_FILE" -k "$KEYCHAIN_PATH" -P "$CERT_PASSWORD" -A
security list-keychains -d user -s "$KEYCHAIN_PATH"
security set-key-partition-list -S apple-tool:,apple: -s -k "" "$KEYCHAIN_PATH"

echo "Signing package with identity: $IDENTITY"
productsign --sign "$IDENTITY" "$PACKAGE_PATH" "$SIGNED_PATH"
mv "$SIGNED_PATH" "$PACKAGE_PATH"

if [ "$REQUIRE_NOTARIZE" = "1" ]; then
  if [ -z "$NOTARY_KEY_ID" ] || [ -z "$NOTARY_ISSUER" ] || [ -z "$NOTARY_KEY_P8" ]; then
    echo "Notarization requested but credentials are incomplete." >&2
    echo "Set NOTARYTOOL_KEY_ID, NOTARYTOOL_ISSUER_ID, NOTARYTOOL_KEY_P8_BASE64" >&2
    exit 1
  fi

  KEY_P8_PATH="${RUNNER_TEMP:-/tmp}/devstack_notary.p8"
  echo "$NOTARY_KEY_P8" | base64 --decode > "$KEY_P8_PATH"

  echo "Submitting package for notarization"
  notarytool submit "$PACKAGE_PATH" \
    --key "$KEY_P8_PATH" \
    --key-id "$NOTARY_KEY_ID" \
    --issuer "$NOTARY_ISSUER" \
    --wait

  echo "Stapling package"
  xcrun stapler staple "$PACKAGE_PATH"
fi
