#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/Vendor"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

TORR_VERSION="MatriX.145"
TORR_URL="https://github.com/YouROK/TorrServer/releases/download/${TORR_VERSION}/TorrServer-ios-TorrServerKit.xcframework.zip"
TORR_SHA256="868969629a594c0f033192ed87e5b555b4a96bab69496e3d7dab1b394bc3cc6b"

echo "[1/3] Generate black LampaS app icon..."
ICON_B64="$ROOT/LampaTorr/Resources/LampaSIcon.base64"
RAW_ICON="$TMP/lampas-icon.png"
APPICON_DIR="$ROOT/LampaTorr/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$APPICON_DIR"

python3 - "$ICON_B64" "$RAW_ICON" <<'PY'
import base64, pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text().strip()
pathlib.Path(sys.argv[2]).write_bytes(base64.b64decode(source))
PY

cat > "$TMP/render-icon.swift" <<'SWIFT'
import AppKit
import Foundation

guard CommandLine.arguments.count == 3,
      let source = NSImage(contentsOfFile: CommandLine.arguments[1]) else {
    fatalError("Unable to load LampaS icon")
}

let size = NSSize(width: 1024, height: 1024)
let canvas = NSImage(size: size)
canvas.lockFocus()
NSColor.black.setFill()
NSRect(origin: .zero, size: size).fill()
NSGraphicsContext.current?.imageInterpolation = .high
source.draw(
    in: NSRect(x: 152, y: 152, width: 720, height: 720),
    from: NSRect(origin: .zero, size: source.size),
    operation: .sourceOver,
    fraction: 1.0
)
canvas.unlockFocus()

guard let tiff = canvas.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Unable to render app icon")
}

try png.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
SWIFT

swift "$TMP/render-icon.swift" "$RAW_ICON" "$APPICON_DIR/AppIcon-1024.png"

cat > "$APPICON_DIR/Contents.json" <<'EOF'
{
  "images" : [
    {
      "filename" : "AppIcon-1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

echo "[2/3] Download TorrServerKit ${TORR_VERSION}..."
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

echo "[3/3] Generate Xcode project..."
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen not found. Install: brew install xcodegen"
  exit 1
fi
cd "$ROOT"
xcodegen generate

echo "Done"
echo "Web UI: https://cf.lampa.mx"
echo "TorrServer: http://127.0.0.1:8090"
echo "VLC: embedded VLCKit"
