#!/bin/bash
# Diagnose and repair "Clipstack keeps asking for Accessibility permission".
#
#   ./scripts/fix-permissions.sh
#
# macOS binds this permission to an app's code signature at a fixed location.
# Three things break that binding, and all three look identical from the
# outside — you grant permission, and the app still says it does not have it.
set -euo pipefail

APP_NAME="Clipstack"
BUNDLE_ID="com.efoli.Clipstack"
CANONICAL="/Applications/$APP_NAME.app"

step() { printf '\n\033[1m%s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
info() { printf '    %s\n' "$1"; }

PROBLEM=false

# ------------------------------------------------------- 1. where is it running
step "Checking where $APP_NAME is running from"

PID="$(pgrep -x "$APP_NAME" 2>/dev/null || true)"
if [ -z "$PID" ]; then
    warn "not running"
    RUNNING_PATH=""
else
    RUNNING_PATH="$(ps -o comm= -p "$PID" | sed "s|/Contents/MacOS/$APP_NAME||")"
    info "$RUNNING_PATH"

    case "$RUNNING_PATH" in
        /Volumes/*)
            warn "It is running from a mounted disk image."
            info "A disk image is temporary and read-only, so macOS cannot keep"
            info "a permission for it. Drag $APP_NAME to your Applications folder"
            info "and open it from there instead."
            PROBLEM=true
            ;;
        *AppTranslocation*)
            warn "macOS is running it from a randomised temporary copy"
            info "(App Translocation). Move $APP_NAME to Applications, then run:"
            info "  xattr -dr com.apple.quarantine $CANONICAL"
            PROBLEM=true
            ;;
        "$CANONICAL")
            ok "running from $CANONICAL — correct"
            ;;
        *)
            warn "running from an unusual location"
            info "Installing to $CANONICAL is more reliable."
            ;;
    esac
fi

# ----------------------------------------------------- 2. duplicate copies
step "Looking for other copies"

COPIES=()
while IFS= read -r line; do
    [ -n "$line" ] && COPIES+=("$line")
done < <(
    {
        [ -e "$CANONICAL" ] && echo "$CANONICAL"
        [ -e "$HOME/Applications/$APP_NAME.app" ] && echo "$HOME/Applications/$APP_NAME.app"
        ls -d /Volumes/*/"$APP_NAME.app" 2>/dev/null || true
    } | sort -u
)

if [ "${#COPIES[@]}" -le 1 ]; then
    ok "only one copy found"
else
    warn "${#COPIES[@]} copies found — macOS may be tracking the wrong one:"
    for copy in "${COPIES[@]}"; do info "$copy"; done
    info "Keep $CANONICAL and delete or eject the others."
    PROBLEM=true
fi

# ---------------------------------------------------------- 3. the signature
step "Checking the signature"

if [ -e "$CANONICAL" ]; then
    if codesign -dvvv "$CANONICAL" 2>&1 | grep -q "Signature=adhoc"; then
        warn "ad-hoc signed"
        info "The signature changes on every rebuild, so macOS treats each build"
        info "as a different app and revokes the permission. To fix permanently:"
        info "  ./scripts/create-signing-cert.sh   (then rebuild)"
    else
        ok "signed with a stable identity — the permission should persist"
    fi
else
    warn "$CANONICAL is not installed. Run ./install.sh"
fi

# ------------------------------------------------------------ 4. reset TCC
step "Clearing stale permission records"

# Duplicate records are common after a rename, a move, or a rebuild: System
# Settings shows one entry while macOS matches against another.
OUTPUT="$(tccutil reset Accessibility "$BUNDLE_ID" 2>&1 || true)"
COUNT="$(printf '%s\n' "$OUTPUT" | grep -c "Successfully reset" || true)"

if [ "${COUNT:-0}" -gt 1 ]; then
    warn "found $COUNT conflicting records — this was very likely the problem"
else
    ok "records cleared"
fi

# ------------------------------------------------------------------ restart
if [ -e "$CANONICAL" ]; then
    step "Restarting $APP_NAME"
    pkill -x "$APP_NAME" 2>/dev/null && sleep 1 || true
    open "$CANONICAL"
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null && ok "running from $CANONICAL"
fi

cat <<NEXT

────────────────────────────────────────────────────────────────
  Now grant the permission again — it is no longer in the list:

    System Settings > Privacy & Security > Accessibility
    click +, choose $CANONICAL, switch it on

  Then open Clipstack with Cmd+Shift+V and click any item. If it
  pastes into the app you were using, it worked.
NEXT

if [ "$PROBLEM" = true ]; then
    cat <<'NEXT'

  Fix the warnings above first, or the permission will not stick.
NEXT
fi
echo "────────────────────────────────────────────────────────────────"

open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" 2>/dev/null || true
