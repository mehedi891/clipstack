#!/bin/bash
# Package Clipstack as a distributable .dmg.
#
# Produces a working disk image whatever signing you have. What differs is what
# a recipient experiences:
#
#   Developer ID + notarized  → opens with a double click, no warnings
#   Developer ID only         → "unidentified developer", right-click → Open
#   ad-hoc (the default here) → Gatekeeper blocks it; see the install notes
#
# To sign and notarize, set both:
#   CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE="clipstack"     # from: xcrun notarytool store-credentials
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Clipstack"
APP="$ROOT/build/$APP_NAME.app"
DIST="$ROOT/dist"
STAGE="$DIST/stage"

cd "$ROOT"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Info.plist")"
DMG="$DIST/$APP_NAME-$VERSION.dmg"

echo "==> Building $APP_NAME $VERSION"
"$ROOT/scripts/build-app.sh" >/dev/null

# --- Staging -----------------------------------------------------------------
echo "==> Staging disk image contents"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"

cp -R "$APP" "$STAGE/"
# The drag-to-install convention: the app beside an Applications shortcut.
ln -s /Applications "$STAGE/Applications"

# --- Notarization state ------------------------------------------------------
# Ask Gatekeeper directly rather than inferring from which variables are set.
if spctl --assess --type execute "$APP" >/dev/null 2>&1; then
    ACCEPTED=yes
else
    ACCEPTED=no
fi

if [ "$ACCEPTED" = "no" ]; then
    echo "==> Adding install notes (build is not accepted by Gatekeeper)"
    cat > "$STAGE/Read Me First.txt" <<'NOTES'
Clipstack
=========

INSTALL
  Drag Clipstack onto the Applications folder in this window.

FIRST LAUNCH
  This build is not notarised by Apple, so macOS will refuse to open it on the
  first try. This is expected, and it is a signing issue, not a problem with
  the app.

  1. Open your Applications folder.
  2. Right-click (or Control-click) Clipstack and choose "Open".
  3. Click "Open" in the dialog that appears.

  If macOS says the app is damaged, remove the download quarantine flag from
  Terminal and try again:

      xattr -dr com.apple.quarantine /Applications/Clipstack.app

  You only have to do this once.

USING IT
  Clipstack lives in the menu bar; it has no Dock icon.
  Press Cmd+Shift+V to open the clipboard panel.
  Open the panel once and press "Turn on" to start recording history.

  To paste automatically, grant Accessibility permission when asked
  (System Settings > Privacy & Security > Accessibility). Without it,
  selecting an item still copies it and you press Cmd+V yourself.

  Nothing is sent anywhere. History is stored only on this Mac, at
  ~/Library/Application Support/Clipstack/
NOTES
fi

# --- Disk image --------------------------------------------------------------
echo "==> Creating $DMG"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$DMG" | sed 's/^/    /'

rm -rf "$STAGE"

# --- Sign and notarise, when credentials allow -------------------------------
if [ -n "${CODESIGN_IDENTITY:-}" ]; then
    echo "==> Signing the disk image"
    codesign --force --sign "$CODESIGN_IDENTITY" "$DMG"
fi

if [ -n "${NOTARY_PROFILE:-}" ]; then
    # Uploads the disk image to Apple. Typically a few minutes.
    echo "==> Submitting for notarisation (this uploads the app to Apple)"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

    echo "==> Stapling the ticket"
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG" | sed 's/^/    /'
fi

# --- Report ------------------------------------------------------------------
SIZE="$(du -h "$DMG" | cut -f1 | tr -d ' ')"
echo
echo "==> Done: $DMG ($SIZE)"

if [ "$ACCEPTED" = "yes" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "    Recipients can open it with a double click."
else
    echo "    WARNING: not notarised. Recipients must right-click > Open the first"
    echo "    time, and may need to clear the quarantine flag. Install notes are"
    echo "    included in the disk image. See README.md to fix this properly."
fi
