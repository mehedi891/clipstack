#!/bin/bash
# Rebuild and relaunch, replacing any running instance.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Clipstack.app"

"$ROOT/scripts/build-app.sh"

echo "==> Stopping running instance"
pkill -x Clipstack 2>/dev/null && sleep 0.5 || true

echo "==> Launching"
open "$APP"
