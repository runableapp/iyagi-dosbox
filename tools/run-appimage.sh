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
# - force bundled DOSBox in AppImage for runtime consistency
# - use the same USER_DATA_ROOT as run-dosbox.sh (iyagi-data/) so .env + tuning
#   match local dev; AppImage launch.sh otherwise uses XDG dirs and a different .env
export DOSBOX_SOURCE="${DOSBOX_SOURCE:-bundled}"
if [[ "${RUN_APPIMAGE_XDG:-0}" =~ ^(1|true|yes|on)$ ]]; then
    : # use AppImage default user dir: ~/.local/share/iyagi-terminal/ (same layout as iyagi-data/)
else
    export USER_DATA_ROOT="${USER_DATA_ROOT:-$REPO_ROOT/iyagi-data}"
    echo "run-appimage: USER_DATA_ROOT=$USER_DATA_ROOT (repo iyagi-data; RUN_APPIMAGE_XDG=1 for ~/.local/share/iyagi-terminal)"
fi

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
# NOTE: When you run the AppImage directly (no this script), USER_DATA_ROOT is unset
# and launch.sh uses ~/.local/share/iyagi-terminal/ — a different .env than iyagi-data/.
#
# Bridge CONNECT debug logging: this wrapper sets IYAGI_BRIDGE_DEBUG_OVERRIDE=1 so launch.sh
# forces BRIDGE_DEBUG=1 after reading .env (handy for dev). Direct AppImage runs do not set
# this, so BRIDGE_DEBUG follows .env (default 0). To use .env only from this script:
#   IYAGI_BRIDGE_DEBUG_OVERRIDE=0 ./tools/run-appimage.sh
: "${IYAGI_BRIDGE_DEBUG_OVERRIDE:=1}"
export IYAGI_BRIDGE_DEBUG_OVERRIDE

exec "$APPIMAGE"
