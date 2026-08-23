#!/bin/bash
# Build and install Clipstack from source.
#
#   ./install.sh              # build, install to /Applications, launch
#   ./install.sh --no-cert    # skip the signing certificate step
#   ./install.sh --here       # run from ./build instead of installing
#
# Everything needed ships with macOS Command Line Tools. Xcode is not required.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Clipstack"
DEST="/Applications/$APP_NAME.app"
BUNDLE_ID="com.efoli.Clipstack"

MAKE_CERT=true
INSTALL=true
for arg in "$@"; do
    case "$arg" in
        --no-cert) MAKE_CERT=false ;;
        --here)    INSTALL=false ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

step() { printf '\n\033[1m%s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
die()  { printf '  \033[31m✗\033[0m %s\n' "$1" >&2; exit 1; }

# ---------------------------------------------------------------- requirements
step "1/5  Checking requirements"

MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[ "$MAJOR" -ge 14 ] || die "macOS 14 or later is required (found $(sw_vers -productVersion))."
ok "macOS $(sw_vers -productVersion)"

if ! command -v swift >/dev/null 2>&1; then
    die "Swift not found. Install the Command Line Tools first:
      xcode-select --install"
fi
ok "$(swift --version 2>/dev/null | head -1)"

# ------------------------------------------------------------------ signing
# macOS ties Accessibility permission to the app's code signature. Ad-hoc
# signing changes it on every build, so the permission is revoked each time.
step "2/5  Signing certificate"

if security find-certificate -c "$APP_NAME Dev" >/dev/null 2>&1; then
    ok "\"$APP_NAME Dev\" already exists"
elif [ "$MAKE_CERT" = false ]; then
    warn "Skipped. The app will be ad-hoc signed, so macOS will ask for"
    warn "Accessibility permission again after every rebuild."
else
    echo "  Creating a local certificate so the Accessibility permission survives"
    echo "  rebuilds. macOS will ask for your login password once."
    echo
    if "$ROOT/scripts/create-signing-cert.sh"; then
        ok "certificate ready"
    else
        warn "Could not create it — continuing with ad-hoc signing."
        warn "See README.md to create one by hand in Keychain Access."
    fi
fi

# -------------------------------------------------------------------- build
step "3/5  Building"
"$ROOT/scripts/build-app.sh" >/dev/null 2>&1 || die "Build failed. Run scripts/build-app.sh to see why."
ok "built $ROOT/build/$APP_NAME.app"

# ------------------------------------------------------------------ install
step "4/5  Installing"

pkill -x "$APP_NAME" 2>/dev/null && sleep 1 || true

if [ "$INSTALL" = false ]; then
    DEST="$ROOT/build/$APP_NAME.app"
    warn "Running from $DEST (--here)"
elif [ -w /Applications ]; then
    rm -rf "$DEST"
    cp -R "$ROOT/build/$APP_NAME.app" "$DEST"
    ok "installed to $DEST"
else
    echo "  /Applications needs administrator access."
    sudo rm -rf "$DEST"
    sudo cp -R "$ROOT/build/$APP_NAME.app" "$DEST"
    sudo chown -R "$(id -u):$(id -g)" "$DEST"
    ok "installed to $DEST"
fi

# Clear any permission record left by an older copy, so the grant below is not
# matched against a signature that no longer exists.
tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true

# ------------------------------------------------------------------- launch
step "5/5  Launching"
open "$DEST"
sleep 2

if pgrep -x "$APP_NAME" >/dev/null; then
    ok "$APP_NAME is running (look for the clipboard icon in your menu bar)"
else
    die "It did not start. Run $DEST/Contents/MacOS/$APP_NAME to see the error."
fi

cat <<NEXT

────────────────────────────────────────────────────────────────
  Done. Two things to do now:

  1. Press Cmd+Shift+V, then click "Turn on" to start recording
     clipboard history. Nothing is recorded until you do.

  2. To paste automatically, allow Accessibility:
       System Settings > Privacy & Security > Accessibility
       click +, choose $DEST, and switch it on

     Without it, clicking an item still copies it and you press
     Cmd+V yourself.

  If the permission will not stick, run:
       ./scripts/fix-permissions.sh
────────────────────────────────────────────────────────────────
NEXT
