#!/bin/bash
# Remove Clipstack and everything it stored.
#
#   ./scripts/uninstall.sh          # lists what would be removed, then asks
#   ./scripts/uninstall.sh --yes    # no prompt
#
# One thing cannot be scripted: the entry in System Settings > Privacy &
# Security > Accessibility. That database is protected by SIP and is only
# editable by hand. Instructions are printed at the end.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSUME_YES=false
[ "${1:-}" = "--yes" ] && ASSUME_YES=true

SUPPORT="$HOME/Library/Application Support"
PREFS="$HOME/Library/Preferences"

# Both identifiers: the app shipped as MacClipboard before it was renamed.
PATHS=(
    "$SUPPORT/Clipstack"
    "$SUPPORT/MacClipboard"
    "$PREFS/com.efoli.Clipstack.plist"
    "$PREFS/com.efoli.MacClipboard.plist"
    "$HOME/Library/Caches/com.efoli.Clipstack"
    "$HOME/Library/Saved Application State/com.efoli.Clipstack.savedState"
    "/Applications/Clipstack.app"
    "$HOME/Applications/Clipstack.app"
    "$ROOT/build/Clipstack.app"
)

echo "The following will be removed:"
FOUND=false
for path in "${PATHS[@]}"; do
    if [ -e "$path" ]; then
        SIZE="$(du -sh "$path" 2>/dev/null | cut -f1 | tr -d ' ')"
        echo "  $path  ($SIZE)"
        FOUND=true
    fi
done

if [ "$FOUND" = false ]; then
    echo "  (nothing — already uninstalled)"
    exit 0
fi

echo
echo "This deletes your clipboard history, including pinned items. It cannot be undone."

if [ "$ASSUME_YES" = false ]; then
    printf "Continue? [y/N] "
    read -r reply
    case "$reply" in
        [yY]|[yY][eE][sS]) ;;
        *) echo "Cancelled."; exit 1 ;;
    esac
fi

echo
echo "==> Quitting the app"
pkill -x Clipstack 2>/dev/null && sleep 1 || true
pkill -x MacClipboard 2>/dev/null && sleep 1 || true

echo "==> Clearing preferences"
# `defaults delete` first: the preferences daemon caches domains in memory and
# would otherwise rewrite the plist after it is deleted.
for domain in com.efoli.Clipstack com.efoli.MacClipboard; do
    defaults delete "$domain" 2>/dev/null && echo "    removed $domain" || true
done

echo "==> Removing files"
for path in "${PATHS[@]}"; do
    if [ -e "$path" ]; then
        rm -rf "$path"
        echo "    removed $path"
    fi
done

cat <<'MANUAL'

==> Done.

One step is left, and it has to be done by hand — macOS protects this list:

  System Settings > Privacy & Security > Accessibility
    select Clipstack, then click the "-" button

The entry is harmless once the app is gone, but it keeps the list tidy.

Also worth knowing:
  - Nothing was installed outside your home folder, and no login item was
    registered, so there is nothing else to clean up.
  - The project source in this folder is untouched. Delete the folder itself
    to remove the build tooling and source as well.
MANUAL
