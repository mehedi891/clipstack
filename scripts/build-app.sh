#!/bin/bash
# Assemble Clipstack.app from the SwiftPM build product.
#
# There is no Xcode on this machine, so the .app bundle is built by hand:
# compile with SwiftPM, then lay out Contents/{MacOS,Resources} around the
# binary and sign it.
#
# Signing identity: set CODESIGN_IDENTITY to the name of a self-signed
# code-signing certificate to keep the Accessibility permission across
# rebuilds. Without it the app is ad-hoc signed and macOS revokes that
# permission every time the binary changes. See docs/PLAN.md.
set -euo pipefail

CONFIG="${CONFIG:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Clipstack"
APP="$ROOT/build/$APP_NAME.app"
BUILD_DIR="$ROOT/.build/$CONFIG"

cd "$ROOT"

# Render the icon only when the generator has changed: `swift <script>` compiles
# on every run, which is slow enough to notice on an incremental build.
ICNS="$ROOT/build/Clipstack.icns"
if [ ! -f "$ICNS" ] || [ "$ROOT/scripts/generate-icon.swift" -nt "$ICNS" ]; then
    echo "==> Rendering app icon"
    swift "$ROOT/scripts/generate-icon.swift" | sed 's/^/    /'
    iconutil -c icns "$ROOT/build/Clipstack.iconset" -o "$ICNS"
fi

# SwiftPM copies resources into its bundle but never prunes ones that have been
# deleted or renamed, so stale files accumulate and get shipped. Clearing the
# bundle first forces a clean copy; it is regenerated on every build anyway.
rm -rf "$BUILD_DIR"/*.bundle

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$ICNS" "$APP/Contents/Resources/Clipstack.icns"

# SwiftPM emits target resources as sibling .bundle directories rather than
# placing them in the app. Bundle.module resolves them via the main bundle's
# resource path, so they must land in Contents/Resources.
shopt -s nullglob
bundles=("$BUILD_DIR"/*.bundle)
if [ ${#bundles[@]} -gt 0 ]; then
    for b in "${bundles[@]}"; do
        echo "    resource bundle: $(basename "$b")"
        cp -R "$b" "$APP/Contents/Resources/"
    done
else
    echo "    (no resource bundles)"
fi
shopt -u nullglob

# Signing identity, in order of preference:
#   1. CODESIGN_IDENTITY, if set
#   2. a self-signed certificate named "Clipstack Dev", if one exists
#   3. ad-hoc
# Options 1 and 2 keep the Accessibility grant across rebuilds; ad-hoc does not,
# because macOS keys that permission to the signature and ad-hoc changes with
# every build. See README.md for how to create the certificate.
DEV_CERT="Clipstack Dev"
if [ -n "${CODESIGN_IDENTITY:-}" ]; then
    IDENTITY="$CODESIGN_IDENTITY"
elif security find-certificate -c "$DEV_CERT" >/dev/null 2>&1; then
    IDENTITY="$DEV_CERT"
else
    IDENTITY="-"
    echo "    note: signing ad-hoc; Accessibility permission will need re-granting"
    echo "          after each rebuild. See README.md to avoid this."
fi

echo "==> codesign (identity: $IDENTITY)"
codesign --force --deep --sign "$IDENTITY" \
    --options runtime \
    --timestamp=none \
    "$APP" 2>&1 | sed 's/^/    /' || {
        echo "!! codesign failed" >&2
        exit 1
    }

codesign -dv "$APP" 2>&1 | sed 's/^/    /'

echo "==> Built $APP"
