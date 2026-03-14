#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPIMAGE="$REPO_ROOT/dist/IYAGI-linux-x86_64.AppImage"
DOSBOX_BIN_DEFAULT="$REPO_ROOT/third_party/dosbox-x/unpacked/usr/bin/dosbox-x"

if [ ! -x "$APPIMAGE" ]; then
    echo "ERROR: AppImage not found or not executable: $APPIMAGE"
    echo "Build it first with: bash tools/build-linux.sh"
    exit 1
fi

if [ ! -x "$DOSBOX_BIN_DEFAULT" ]; then
    echo "WARNING: Standalone DOSBox-X not found at: $DOSBOX_BIN_DEFAULT"
    echo "Running AppImage without DOSBOX_BIN override."
    exec "$APPIMAGE"
fi

# Override launcher selection at runtime without editing iyagi-data/.env.
export DOSBOX_SOURCE=system
export DOSBOX_BIN="$DOSBOX_BIN_DEFAULT"
# Leave USER_DATA_ROOT unset by default so AppImage uses XDG config/data dirs.
# Set USER_DATA_ROOT explicitly if you want portable repo-local data.

exec "$APPIMAGE"
