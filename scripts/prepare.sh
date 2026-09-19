#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/Vendor"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

LAMPA_COMMIT="d3d3d1cbd943b7fb9de9b470c2f8bc0f3e241a94"
LAMPA_URL="https://github.com/yumata/lampa/archive/${LAMPA_COMMIT}.zip"
TORR_VERSION="MatriX.145"
TORR_URL="https://github.com/YouROK/TorrServer/releases/download/${TORR_VERSION}/TorrServer-ios-TorrServerKit.xcframework.zip"
TORR_SHA256="868969629a594c0f033192ed87e5b555b4a96bab69496e3d7dab1b394bc3cc6b"

echo "[1/4] Download Lampa..."
curl -fL --retry 3 "$LAMPA_URL" -o "$TMP/lampa.zip"
unzip -q "$TMP/lampa.zip" -d "$TMP/lampa"
LAMPA_DIR="$(find "$TMP/lampa" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
test -f "$LAMPA_DIR/index.html"
rm -rf "$VENDOR/Lampa"
mkdir -p "$VENDOR/Lampa"
ditto "$LAMPA_DIR" "$VENDOR/Lampa"
rm -rf "$VENDOR/Lampa/.git" "$VENDOR/Lampa/.github"

echo "[2/4] Download TorrServerKit ${TORR_VERSION}..."
curl -fL --retry 3 "$TORR_URL" -o "$TMP/torrserverkit.zip"
ACTUAL_SHA="$(shasum -a 256 "$TMP/torrserverkit.zip" | awk '{print $1}')"
if [[ "$ACTUAL_SHA" != "$TORR_SHA256" ]]; then
  echo "Checksum mismatch for TorrServerKit"
  echo "Expected: $TORR_SHA256"
  echo "Actual:   $ACTUAL_SHA"
  exit 1
fi
unzip -q "$TMP/torrserverkit.zip" -d "$TMP/torrserverkit"
XCFRAMEWORK="$(find "$TMP/torrserverkit" -name 'TorrServerKit.xcframework' -type d | head -n 1)"
test -n "$XCFRAMEWORK"
rm -rf "$VENDOR/TorrServerKit.xcframework"
ditto "$XCFRAMEWORK" "$VENDOR/TorrServerKit.xcframework"

echo "[3/4] Generate Xcode project..."
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen not found. Install: brew install xcodegen"
  exit 1
fi
cd "$ROOT"
xcodegen generate

echo "[4/4] Done"
echo "Open: $ROOT/LampaTorr.xcodeproj"
echo "TorrServer: http://127.0.0.1:8090"
