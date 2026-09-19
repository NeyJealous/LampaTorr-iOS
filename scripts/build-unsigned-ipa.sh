#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUNDLE_ID="${1:-${BUNDLE_ID:-dev.lampatorr.ios}}"
if [[ ! "$BUNDLE_ID" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$ ]]; then
  echo "Invalid Bundle ID: $BUNDLE_ID" >&2
  exit 2
fi

if [[ ! -d Vendor/TorrServerKit.xcframework || ! -d LampaTorr.xcodeproj ]]; then
  bash ./scripts/prepare.sh
fi

rm -rf build Payload LampaTorr-unsigned.ipa

echo "Resolving Swift packages..."
xcodebuild   -project LampaTorr.xcodeproj   -scheme LampaTorr   -resolvePackageDependencies

echo "Building unsigned device app..."
xcodebuild   -project LampaTorr.xcodeproj   -scheme LampaTorr   -configuration Release   -sdk iphoneos   -derivedDataPath "$ROOT/build/DerivedData"   PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID"   CODE_SIGNING_ALLOWED=NO   CODE_SIGNING_REQUIRED=NO   CODE_SIGN_IDENTITY=""   DEVELOPMENT_TEAM=""   build

APP="$ROOT/build/DerivedData/Build/Products/Release-iphoneos/LampaTorr.app"
test -d "$APP"
test -f "$APP/Info.plist"

ACTUAL_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"
if [[ "$ACTUAL_BUNDLE_ID" != "$BUNDLE_ID" ]]; then
  echo "Bundle ID mismatch: expected $BUNDLE_ID, got $ACTUAL_BUNDLE_ID" >&2
  exit 3
fi

mkdir -p Payload
ditto "$APP" Payload/LampaTorr.app
zip -qry LampaTorr-unsigned.ipa Payload
rm -rf Payload

test -s LampaTorr-unsigned.ipa

echo "Created: $ROOT/LampaTorr-unsigned.ipa"
echo "Bundle ID: $BUNDLE_ID"
echo "Unsigned IPA: sign it on iPhone with Ksign and your certificate/provisioning profile."
