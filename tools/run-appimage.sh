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

# Default dev-run behavior:
# - force bundled DOSBox in AppImage
# - force scanline shader mode on
# This bypasses stale ~/.config/iyagi-terminal/.env values when running via
# this helper script. (The packaged AppImage itself still follows user .env.)
export DOSBOX_SOURCE="${DOSBOX_SOURCE:-bundled}"
export DOSBOX_SCANLINES="${DOSBOX_SCANLINES:-1}"
export DOSBOX_GLSHADER="${DOSBOX_GLSHADER:-crt/vga-1080p-fake-double-scan}"

# By default, do NOT force DOSBox-X override.
#
# Optional opt-in override for local experiments:
#   RUN_APPIMAGE_FORCE_DOSBOX_X=1 bash tools/run-appimage.sh
# You can also override the binary path with RUN_APPIMAGE_DOSBOX_BIN.
if [[ "${RUN_APPIMAGE_FORCE_DOSBOX_X:-0}" =~ ^(1|true|yes|on)$ ]]; then
    DOSBOX_BIN_OVERRIDE="${RUN_APPIMAGE_DOSBOX_BIN:-$DOSBOX_BIN_DEFAULT}"
    if [ ! -x "$DOSBOX_BIN_OVERRIDE" ]; then
        echo "ERROR: RUN_APPIMAGE_FORCE_DOSBOX_X is enabled but DOSBox-X is not executable:"
        echo "       $DOSBOX_BIN_OVERRIDE"
        exit 1
    fi
    echo "Using DOSBox-X override for AppImage run:"
    echo "  DOSBOX_BIN=$DOSBOX_BIN_OVERRIDE"
    export DOSBOX_SOURCE=system
    export DOSBOX_BIN="$DOSBOX_BIN_OVERRIDE"
fi
# Leave USER_DATA_ROOT unset by default so AppImage uses XDG config/data dirs.
# Set USER_DATA_ROOT explicitly if you want portable/repo-local data.

exec "$APPIMAGE"
