#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/Vendor"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

LAMPA_SOURCE_COMMIT="8150685226a5838040a5795a32be27108491cadb"
LAMPA_SOURCE_URL="https://github.com/yumata/lampa-source/archive/${LAMPA_SOURCE_COMMIT}.zip"
TORR_VERSION="MatriX.145"
TORR_URL="https://github.com/YouROK/TorrServer/releases/download/${TORR_VERSION}/TorrServer-ios-TorrServerKit.xcframework.zip"
TORR_SHA256="868969629a594c0f033192ed87e5b555b4a96bab69496e3d7dab1b394bc3cc6b"

echo "[1/5] Build LampaS-style web client from source..."
curl -fL --retry 3 "$LAMPA_SOURCE_URL" -o "$TMP/lampa-source.zip"
unzip -q "$TMP/lampa-source.zip" -d "$TMP/lampa-source"
LAMPA_SRC="$(find "$TMP/lampa-source" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
test -f "$LAMPA_SRC/src/app.js"

# LampaS behavior: no preroll/banner advertising inside the bundled web client.
# Keep the public API shape so Player imports keep working, but make advertising a no-op.
cat > "$LAMPA_SRC/src/interaction/advert/preroll.js" <<'EOF'
function init(){}

function show(data, call){
    if(typeof call === 'function') call()
}

export default {
    init,
    show
}
EOF

cat > "$LAMPA_SRC/src/interaction/advert/manager.js" <<'EOF'
function init(){}

export default {
    init
}
EOF

# The upstream gulp merge task signals completion too early for one-shot CI.
# Add a CI-only equivalent that returns the Rollup stream so gulp waits correctly.
cat >> "$LAMPA_SRC/gulpfile.js" <<'EOF'

function ci_merge(){
    let ciPlugins = [babel({
        babelHelpers: 'bundled',
        presets: ['@babel/preset-env']
    }), commonjs, nodeResolve, worker()]

    return rollup({
        input: srcFolder+"app.js",
        plugins: ciPlugins,
        output: {
            format: 'iife',
            sourcemap: false
        },
        onwarn: function(){ return; }
    })
    .pipe(source('app.js'))
    .pipe(buffer())
    .pipe(replace(/return kIsNodeJS/g, "return false"))
    .pipe(dest(dstFolder));
}

exports.ci = series(
    ci_merge,
    plugins,
    sass_task,
    lang_task,
    sync_github,
    uglify_task,
    public_github,
    write_manifest,
    index_github
);
EOF

pushd "$LAMPA_SRC" >/dev/null
if [[ -f package-lock.json ]]; then
  npm ci --legacy-peer-deps
else
  npm install --legacy-peer-deps
fi
npx gulp ci
popd >/dev/null

LAMPA_BUILD="$LAMPA_SRC/build/github/lampa"
test -f "$LAMPA_BUILD/index.html"
test -f "$LAMPA_BUILD/app.min.js"

rm -rf "$VENDOR/Lampa"
mkdir -p "$VENDOR/Lampa"
ditto "$LAMPA_BUILD" "$VENDOR/Lampa"

echo "[2/5] Generate LampaS app icon..."
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
NSColor(calibratedRed: 0.067, green: 0.067, blue: 0.067, alpha: 1.0).setFill()
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

echo "[3/5] Download TorrServerKit ${TORR_VERSION}..."
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

echo "[4/5] Generate Xcode project..."
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen not found. Install: brew install xcodegen"
  exit 1
fi
cd "$ROOT"
xcodegen generate

echo "[5/5] Done"
echo "Lampa source: $LAMPA_SOURCE_COMMIT (LampaS-style no-ad build)"
echo "TorrServer: http://127.0.0.1:8090"
