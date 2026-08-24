#!/bin/bash
# Capture screenshots of Clipstack for the README.
#
#   ./scripts/capture-screenshots.sh                  every shot
#   ./scripts/capture-screenshots.sh clipboard pinned  just those
#
# Needs Screen Recording permission for whichever app runs it (Terminal,
# iTerm, VS Code...). macOS asks the first time. If it says
# "could not create image from display", grant it here and run again:
#
#   System Settings > Privacy & Security > Screen Recording
#
# Put something in your clipboard history first, or the shots will be of an
# empty list.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Defaults to the installed copy; CLIPSTACK_APP can point at a fresh build so a
# capture run does not have to replace /Applications (which, with an ad-hoc
# signature, would cost you the Accessibility grant).
APP="${CLIPSTACK_APP:-/Applications/Clipstack.app/Contents/MacOS/Clipstack}"
OUT="$ROOT/Assets/screenshots"

[ -x "$APP" ] || { echo "No Clipstack at $APP. Run ./install.sh first." >&2; exit 1; }

# Any arguments name the shots to take; no arguments means all of them.
ONLY="$*"

mkdir -p "$OUT"

# Fail early with a clear message rather than writing blank images.
probe="$(mktemp -t clipstack-probe).png"
if ! screencapture -x "$probe" 2>/dev/null || [ ! -s "$probe" ]; then
    cat >&2 <<'MSG'
Screen Recording permission is missing.

  System Settings > Privacy & Security > Screen Recording
  Switch on the app you are running this from (Terminal, iTerm, VS Code...),
  then quit and reopen it and run this again.
MSG
    rm -f "$probe"
    exit 1
fi
rm -f "$probe"

# capture <name> <env var> <value> <min window width> [open panel: yes|no]
#
# The panel is only opened for panel shots. Opening it alongside the settings
# window would make the panel key, and macOS then draws the settings window's
# switches in inactive grey.
capture() {
    local name="$1" env_var="$2" value="$3" min_width="$4" panel="${5:-yes}"

    if [ -n "${ONLY:-}" ] && [[ " $ONLY " != *" $name "* ]]; then
        return
    fi

    pkill -x Clipstack 2>/dev/null && sleep 1 || true
    wait 2>/dev/null || true
    if [ "$panel" = "yes" ]; then
        env "$env_var=$value" CLIPSTACK_DEBUG_PANEL=1 "$APP" >/dev/null 2>&1 &
    else
        env "$env_var=$value" "$APP" >/dev/null 2>&1 &
    fi

    # Poll rather than guess: the emoji grid takes noticeably longer to lay out
    # than the lists do.
    local id="" waited=0
    while [ "$waited" -lt 12 ]; do
        sleep 1; waited=$((waited + 1))
        id="$(swift "$ROOT/scripts/window-id.swift" "$min_width" 2>/dev/null)" && [ -n "$id" ] && break
    done
    sleep 1   # let the first frame settle before capturing

    if [ -z "$id" ]; then
        echo "  ! $name — no window appeared"
        return
    fi

    # -o omits the window shadow, so the image crops tightly.
    screencapture -x -o -l"$id" "$OUT/$name.png"
    echo "  ✓ $name.png  ($(sips -g pixelWidth -g pixelHeight "$OUT/$name.png" 2>/dev/null |
        awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w"x"h}'))"
}

echo "Capturing panel tabs"
for tab in clipboard pinned emoji kaomoji symbols; do
    capture "$tab" CLIPSTACK_DEBUG_TAB "$tab" 300
done

echo "Capturing settings"
# Settings is wider than the panel, so ask for the larger window.
capture "settings" CLIPSTACK_DEBUG_SETTINGS 1 380 no

pkill -x Clipstack 2>/dev/null || true
open /Applications/Clipstack.app

echo
echo "Saved to $OUT"
