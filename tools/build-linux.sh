#!/bin/bash
# tools/build-linux.sh — Build a self-contained Linux AppImage of IYAGI.
#
# Run from the repository root:
#   bash tools/build-linux.sh
#
# Output: dist/IYAGI-linux-x86_64.AppImage
#
# Developer options:
#   IYAGI_DEV_SYNC_CONFIG=1 bash tools/build-linux.sh
#     After building, overwrite the runtime IYAGI config files (I.CNF, I.TEL)
#     in USER_DATA_ROOT (or the AppImage default XDG dir if USER_DATA_ROOT is unset).
#     This is for local development only; it intentionally overwrites user settings.
#
# Default dev workflow:
#   - Treat iyagi-data/.env as the "tuning scratchpad"
#   - Copy it into resources/common/.env.example BEFORE bundling (so the AppImage bakes it)
#   - Copy it into the runtime user-data .env AFTER the build (so your next run matches)
#
# Prerequisites (all available without sudo on a stock Ubuntu runner):
#   go       — to compile the bridge binary
#   python3  — to run configure_iyagi.py
#   wget     — to download DOSBox-Staging and appimagetool
#   tar      — to extract the DOSBox tarball
#   file     — to locate the dosbox binary after extraction

set -euo pipefail

# ─── Version pins ─────────────────────────────────────────────────────────────

DOSBOX_VERSION="0.82.2"
DOSBOX_URL="https://github.com/dosbox-staging/dosbox-staging/releases/download/v${DOSBOX_VERSION}/dosbox-staging-linux-x86_64-v${DOSBOX_VERSION}.tar.xz"
APPIMAGETOOL_URL="https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"

# ─── Paths ────────────────────────────────────────────────────────────────────

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/.build/linux"
DIST_DIR="$REPO_ROOT/dist"
OUTPUT="$DIST_DIR/IYAGI-linux-x86_64.AppImage"

APPDIR="$BUILD_DIR/AppDir"
DOSBOX_EXTRACT="$BUILD_DIR/dosbox-staging"
TOOLS_CACHE="$BUILD_DIR/cache"

cd "$REPO_ROOT"

# ─── Helpers ─────────────────────────────────────────────────────────────────

log()  { echo ""; echo "▶ $*"; }
ok()   { echo "  ✓ $*"; }
err()  { echo "  ✗ $*" >&2; exit 1; }

check_cmd() {
    command -v "$1" >/dev/null 2>&1 || err "Required command not found: $1 — please install it"
}

# ─── 1. Preflight checks ─────────────────────────────────────────────────────

log "Checking prerequisites..."
check_cmd go
check_cmd python3
check_cmd wget
check_cmd tar
check_cmd file

go version | head -1
python3 --version
python3 -c "import PIL" >/dev/null 2>&1 || err "Python Pillow is required for icon conversion. Install with: python3 -m pip install pillow"

IYAGI_PREPARED_DIR="${IYAGI_PREPARED_DIR:-$(python3 "$REPO_ROOT/scripts/prepare_iyagi_source.py")}"
ok "Using canonical IYAGI source from $IYAGI_PREPARED_DIR"
ok "All prerequisites met"

# ─── Dev defaults: promote iyagi-data/.env to template ────────────────────────

DEV_ENV_SRC="$REPO_ROOT/iyagi-data/.env"
DEV_ENV_DST="$REPO_ROOT/resources/common/.env.example"
if [ -f "$DEV_ENV_SRC" ]; then
    log "Promoting $DEV_ENV_SRC -> $DEV_ENV_DST (dev default tuning)"
    cp -f "$DEV_ENV_SRC" "$DEV_ENV_DST"
    ok "Updated bundled .env template from iyagi-data/.env"
else
    ok "No $DEV_ENV_SRC found; using existing resources/common/.env.example"
fi

# ─── 2. Prepare build directory ──────────────────────────────────────────────

log "Preparing build directories..."
rm -rf "$BUILD_DIR"
mkdir -p "$APPDIR/usr/bin" "$DOSBOX_EXTRACT" "$TOOLS_CACHE" "$DIST_DIR"
ok "Build dirs ready: $BUILD_DIR"

# ─── 3. Compile bridge binary ────────────────────────────────────────────────

log "Compiling bridge binary (GOOS=linux GOARCH=amd64)..."
(
    cd "$REPO_ROOT/bridge"
    go run ./cmd/embed-sounds
    GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o "$APPDIR/usr/bin/bridge" .
)
chmod +x "$APPDIR/usr/bin/bridge"
ok "bridge binary: $(du -sh "$APPDIR/usr/bin/bridge" | cut -f1)"

# ─── 4. Download DOSBox-Staging ──────────────────────────────────────────────

DOSBOX_ARCHIVE="$TOOLS_CACHE/dosbox-staging-linux-x86_64-v${DOSBOX_VERSION}.tar.xz"

log "Downloading DOSBox-Staging v${DOSBOX_VERSION}..."
if [ -f "$DOSBOX_ARCHIVE" ]; then
    ok "Cached: $DOSBOX_ARCHIVE"
else
    if ! wget -q --show-progress "$DOSBOX_URL" -O "$DOSBOX_ARCHIVE"; then
        # Older tags used a legacy filename without x86_64 in the asset name.
        LEGACY_DOSBOX_URL="https://github.com/dosbox-staging/dosbox-staging/releases/download/v${DOSBOX_VERSION}/dosbox-staging-linux-v${DOSBOX_VERSION}.tar.xz"
        DOSBOX_ARCHIVE="$TOOLS_CACHE/dosbox-staging-linux-v${DOSBOX_VERSION}.tar.xz"
        wget -q --show-progress "$LEGACY_DOSBOX_URL" -O "$DOSBOX_ARCHIVE"
    fi
    ok "Downloaded: $(du -sh "$DOSBOX_ARCHIVE" | cut -f1)"
fi

log "Extracting DOSBox-Staging..."
tar xf "$DOSBOX_ARCHIVE" -C "$DOSBOX_EXTRACT" --strip-components=1

# Find the dosbox binary (location may vary across release versions)
DOSBOX_BIN="$(find "$DOSBOX_EXTRACT" -type f -name "dosbox" | head -1)"
if [ -z "$DOSBOX_BIN" ]; then
    err "dosbox binary not found inside the tarball. Check the release structure."
fi
ok "Found dosbox at: $DOSBOX_BIN"

cp "$DOSBOX_BIN" "$APPDIR/usr/bin/dosbox"
chmod +x "$APPDIR/usr/bin/dosbox"

# Copy any .so files DOSBox needs from the extracted tree (if present)
SO_DIR="$(dirname "$DOSBOX_BIN")"
if find "$SO_DIR" -name "*.so*" -maxdepth 1 | grep -q .; then
    mkdir -p "$APPDIR/usr/lib"
    find "$SO_DIR" -name "*.so*" -maxdepth 1 -exec cp -P {} "$APPDIR/usr/lib/" \;
    ok "Bundled shared libraries from release"
fi

# Copy shader resources used by DOSBox-Staging OpenGL scanline mode.
# Runtime launcher expects ./glshaders relative to staging cwd.
GLSHADERS_SRC="$(python3 - "$DOSBOX_EXTRACT" <<'PYEOF'
from pathlib import Path
import sys

root = Path(sys.argv[1])
candidates = []
for p in root.rglob("glshaders"):
    if p.is_dir() and (p / "interpolation").exists():
        candidates.append(p)

if candidates:
    candidates.sort(key=lambda p: len(str(p)))
    print(candidates[0])
PYEOF
)"
if [ -n "$GLSHADERS_SRC" ] && [ -d "$GLSHADERS_SRC" ]; then
    cp -a "$GLSHADERS_SRC" "$APPDIR/glshaders"
    ok "Bundled glshaders: $GLSHADERS_SRC"
else
    echo "  ! WARNING: glshaders directory not found in DOSBox-Staging archive"
fi

# ─── 5. Assemble AppDir payload ──────────────────────────────────────────────

log "Assembling AppDir payload..."

# IYAGI program files — copy from canonical prepared source
mkdir -p "$APPDIR/app"
cp -r "$IYAGI_PREPARED_DIR/." "$APPDIR/app/"
ok "Copied IYAGI files ($(ls "$APPDIR/app" | wc -l) files)"

# Downloads folder placeholder (writable user data is outside AppImage at runtime)
mkdir -p "$APPDIR/downloads"

# DOSBox config and .env template
cp "$REPO_ROOT/resources/common/dosbox.conf" "$APPDIR/dosbox.conf"
cp "$REPO_ROOT/resources/common/.env.example" "$APPDIR/.env.example"

ok "AppDir payload assembled"

# ─── 6. AppRun entry point ───────────────────────────────────────────────────

log "Installing AppRun (launch script)..."
cp "$REPO_ROOT/resources/linux/launch.sh" "$APPDIR/AppRun"
chmod +x "$APPDIR/AppRun"
ok "AppRun installed"

# ─── 7. Desktop integration files ───────────────────────────────────────────

log "Writing .desktop entry and icon..."

cat > "$APPDIR/iyagi.desktop" << 'EOF'
[Desktop Entry]
Name=IYAGI Terminal
Comment=Korean DOS BBS terminal (IYAGI 5.3) over SSH
Exec=AppRun
Icon=iyagi
StartupWMClass=app.runable.iyagi-dosbox
Type=Application
Categories=Network;TerminalEmulator;
EOF

# Convert the canonical WebP icon to PNG for AppImage desktop integration.
python3 - << 'PYEOF'
from pathlib import Path
from PIL import Image

src = Path("resources/iyagi-icon.webp")
dst = Path(".build/linux/AppDir/iyagi.png")
if not src.exists():
    raise SystemExit(f"Missing icon source: {src}")

im = Image.open(src).convert("RGBA")
im.save(dst, format="PNG")
PYEOF
ok "Desktop entry and icon written"

# ─── 8. Download appimagetool ────────────────────────────────────────────────

APPIMAGETOOL="$TOOLS_CACHE/appimagetool-x86_64.AppImage"

log "Downloading appimagetool..."
if [ -f "$APPIMAGETOOL" ]; then
    ok "Cached: $APPIMAGETOOL"
else
    wget -q --show-progress "$APPIMAGETOOL_URL" -O "$APPIMAGETOOL"
    chmod +x "$APPIMAGETOOL"
    ok "Downloaded appimagetool"
fi

# ─── 9. Build the AppImage ───────────────────────────────────────────────────

log "Building AppImage..."

# appimagetool needs FUSE; if FUSE is not available (common in containers/CI),
# use --appimage-extract-and-run to run it without FUSE.
APPIMAGE_EXTRACT_AND_RUN=1 "$APPIMAGETOOL" "$APPDIR" "$OUTPUT" 2>&1

ok "AppImage created: $OUTPUT"
echo ""
echo "───────────────────────────────────────────────"
echo "  Output : $OUTPUT"
echo "  Size   : $(du -sh "$OUTPUT" | cut -f1)"
echo "───────────────────────────────────────────────"
echo ""
echo "To run:"
echo "  chmod +x $OUTPUT"
echo "  $OUTPUT"
echo ""
echo "User data directory (single tree, same layout as iyagi-data/):"
echo "  \${XDG_DATA_HOME:-~/.local/share}/iyagi-terminal/"
echo "  (.env, keys/, app/, downloads/, staging/ — created on first run if missing)"
echo "(Set USER_DATA_ROOT to override for portable/repo-local mode.)"
echo "For ATDT target mode, you can dial directly from IYAGI, e.g.:"
echo "  ATDT127.0.0.1:40000"
echo "IYAGI_USER is an optional default only."
echo ""

# ─── 10. Developer-only: sync defaults into runtime dir ──────────────────────

if [[ "${IYAGI_DEV_SYNC_CONFIG:-0}" =~ ^(1|true|yes|on)$ ]]; then
    TARGET_ROOT="${USER_DATA_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/iyagi-terminal}"
    TARGET_APP="$TARGET_ROOT/app"
    log "Developer sync: overwriting runtime I.CNF/I.TEL in $TARGET_APP (and app/IYAGI mirror)"
    mkdir -p "$TARGET_APP/IYAGI"
    for name in I.CNF I.TEL; do
        cp -f "$REPO_ROOT/app/IYAGI/$name" "$TARGET_APP/$name"
        cp -f "$REPO_ROOT/app/IYAGI/$name" "$TARGET_APP/IYAGI/$name"
    done
    ok "Synced runtime config files"
fi

TARGET_ROOT="${USER_DATA_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/iyagi-terminal}"
TARGET_ENV="$TARGET_ROOT/.env"
log "Developer sync: overwriting runtime .env at $TARGET_ENV"
mkdir -p "$TARGET_ROOT"
cp -f "$REPO_ROOT/resources/common/.env.example" "$TARGET_ENV"
ok "Synced runtime .env"
