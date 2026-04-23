#!/bin/bash
# launch.sh — Linux launcher / AppRun entry point for the IYAGI AppImage.
#
# When run as an AppRun script inside an AppImage, the AppImage runtime sets:
#   $APPIMAGE  — absolute path to the .AppImage file
#   $APPDIR    — absolute path to the squashfs mount (read-only)
#   $OWD       — original working directory
#
# AppImage user-writable layout matches tools/run-dosbox.sh (single tree):
#   ${XDG_DATA_HOME:-~/.local/share}/iyagi-terminal/
#     .env, keys/, app/, downloads/, staging/
# Override with USER_DATA_ROOT for portable/testing (e.g. repo iyagi-data/).
#
# Direct AppImage + default XDG data dir: if an iyagi-data/ directory sits next to the
# .AppImage file (e.g. dist/IYAGI.AppImage and dist/iyagi-data/), its .env, optional
# dosbox.conf, and app/I.CNF / app/I.TEL are copied into the XDG tree each launch so
# behavior matches tools/run-appimage.sh without the wrapper. Disable with
# IYAGI_NO_PORTABLE_DATA_SYNC=1 or by exporting USER_DATA_ROOT yourself.
#
# Package layout inside the AppImage ($APPDIR):
#   usr/bin/dosbox   — DOSBox-Staging binary
#   usr/bin/bridge   — TCP→SSH bridge binary
#   app/             — IYAGI 5.3 program files
#   dosbox.conf      — DOSBox configuration

set -euo pipefail

BRIDGE_PID=""

cleanup() {
    if [ -n "${BRIDGE_PID:-}" ] && kill -0 "$BRIDGE_PID" 2>/dev/null; then
        echo "Stopping bridge (pid $BRIDGE_PID)..."
        kill "$BRIDGE_PID" 2>/dev/null || true
        wait "$BRIDGE_PID" 2>/dev/null || true
    fi
}

trap cleanup EXIT INT TERM

pick_unused_tcp_port() {
    python3 - <<'PYEOF'
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PYEOF
}

is_port_available() {
    local port="$1"
    python3 - "$port" <<'PYEOF'
import socket
import sys
port = int(sys.argv[1])
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
try:
    s.bind(("127.0.0.1", port))
except OSError:
    sys.exit(1)
finally:
    s.close()
sys.exit(0)
PYEOF
}

# ─── Locate package root ─────────────────────────────────────────────────────

# When running as AppRun, APPDIR is set. When running as a plain script
# (e.g. during development), fall back to the script's own directory.
if [ -z "${APPDIR:-}" ]; then
    APPDIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
fi

BRIDGE="$APPDIR/usr/bin/bridge"
BUNDLED_APP_DIR="$APPDIR/app"
DOSBOX_CONF="$APPDIR/dosbox.conf"

# Captured before USER_DATA_ROOT may be set below (run-appimage.sh / manual export).
USER_DATA_ROOT_WAS_SET_AT_START=0
if [[ -v USER_DATA_ROOT ]]; then
    USER_DATA_ROOT_WAS_SET_AT_START=1
fi

# User-writable data location:
# - If USER_DATA_ROOT is provided, use it directly (portable/testing).
# - AppImage default: single directory under XDG_DATA_HOME (same layout as iyagi-data/).
# - Non-AppImage script: repository-local iyagi-data next to this script.
if [ -n "${USER_DATA_ROOT:-}" ]; then
    USER_DATA_ROOT="$(readlink -f "$USER_DATA_ROOT")"
    CONFIG_ROOT="$USER_DATA_ROOT"
    DATA_ROOT="$USER_DATA_ROOT"
elif [ -n "${APPIMAGE:-}" ]; then
    USER_DATA_ROOT="$(readlink -f "${XDG_DATA_HOME:-$HOME/.local/share}/iyagi-terminal")"
    CONFIG_ROOT="$USER_DATA_ROOT"
    DATA_ROOT="$USER_DATA_ROOT"
else
    USER_DATA_ROOT="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/iyagi-data"
    CONFIG_ROOT="$USER_DATA_ROOT"
    DATA_ROOT="$USER_DATA_ROOT"
fi

KEYS_DIR="$CONFIG_ROOT/keys"
DOWNLOADS_DIR="$DATA_ROOT/downloads"
RUNTIME_APP_DIR="$DATA_ROOT/app"
KEY_FILE="$KEYS_DIR/id_rsa"

mkdir -p "$KEYS_DIR" "$DOWNLOADS_DIR"

PORTABLE_IYAGI_DATA_DIR=""
if [ -n "${APPIMAGE:-}" ] && [ "$USER_DATA_ROOT_WAS_SET_AT_START" = 0 ]; then
    if [[ ! "${IYAGI_NO_PORTABLE_DATA_SYNC:-0}" =~ ^(1|true|yes|on)$ ]]; then
        _apimg_resolved="$(readlink -f "$APPIMAGE" 2>/dev/null || true)"
        if [ -n "$_apimg_resolved" ] && [ -f "$_apimg_resolved" ]; then
            _portable_try="$(readlink -f "$(dirname "$_apimg_resolved")/iyagi-data" 2>/dev/null || true)"
            if [ -n "$_portable_try" ] && [ -d "$_portable_try" ]; then
                PORTABLE_IYAGI_DATA_DIR="$_portable_try"
            fi
        fi
    fi
fi

if [ -n "$PORTABLE_IYAGI_DATA_DIR" ] && [ -f "$PORTABLE_IYAGI_DATA_DIR/.env" ]; then
    mkdir -p "$USER_DATA_ROOT"
    cp -f "$PORTABLE_IYAGI_DATA_DIR/.env" "$USER_DATA_ROOT/.env"
    echo "Portable iyagi-data: synced .env from $PORTABLE_IYAGI_DATA_DIR -> $USER_DATA_ROOT/.env"
fi

if [ -n "${APPIMAGE:-}" ]; then
    echo "IYAGI user data directory: $USER_DATA_ROOT"
    if [ -n "$PORTABLE_IYAGI_DATA_DIR" ]; then
        echo "  (portable $PORTABLE_IYAGI_DATA_DIR -> XDG each launch; IYAGI_NO_PORTABLE_DATA_SYNC=1 to use only XDG templates)"
    else
        echo "  (tools/run-appimage.sh sets USER_DATA_ROOT to <repo>/iyagi-data; or place iyagi-data/ next to this AppImage to sync .env + app/I.CNF into XDG)"
    fi
    echo "  I.CNF path: $RUNTIME_APP_DIR/I.CNF — IYAGI_SYNC_CONFIG_ON_START=1 refreshes from bundle only."
fi

ensure_runtime_app_copy() {
    # Default AppImage behavior: seed once, then keep runtime app/ writable and stable.
    # This avoids overwriting user settings (e.g. I.CNF) on every launch.
    if [ -f "$RUNTIME_APP_DIR/I.EXE" ]; then
        return
    fi
    echo "Seeding writable app files to: $RUNTIME_APP_DIR"
    rm -rf "$RUNTIME_APP_DIR"
    mkdir -p "$RUNTIME_APP_DIR"
    cp -a "$BUNDLED_APP_DIR/." "$RUNTIME_APP_DIR/"
}

sync_iyagi_runtime_config() {
    # Optional: refresh selected config files from the packaged defaults.
    # This intentionally does NOT overwrite the whole app/ directory, to avoid wiping user data.
    # Bundle layout is flat ($APPDIR/app/I.CNF). IYAGI may also use app/IYAGI/ (legacy); mirror so both match.
    for name in I.CNF I.TEL; do
        src=""
        if [ -f "$BUNDLED_APP_DIR/$name" ]; then
            src="$BUNDLED_APP_DIR/$name"
        elif [ -f "$BUNDLED_APP_DIR/IYAGI/$name" ]; then
            src="$BUNDLED_APP_DIR/IYAGI/$name"
        fi
        if [ -n "$src" ]; then
            cp -f "$src" "$RUNTIME_APP_DIR/$name"
            mkdir -p "$RUNTIME_APP_DIR/IYAGI"
            cp -f "$src" "$RUNTIME_APP_DIR/IYAGI/$name"
        fi
    done
}


# ─── Load user config ────────────────────────────────────────────────────────

ENV_FILE="$USER_DATA_ROOT/.env"
if [ ! -f "$ENV_FILE" ]; then
    # First run only: template is $APPDIR/.env.example (from resources/common/.env.example at build time).
    # Python does not rewrite this file. If .env already exists, update it manually or replace it to pick up a newer bundled template.
    cp "$APPDIR/.env.example" "$ENV_FILE"
    if [ -n "${APPIMAGE:-}" ]; then
        echo "=== First run: created default config at $ENV_FILE (edit anytime for IYAGI_USER, ports, etc.)"
    else
        echo ""
        echo "=== First run: created config file at $ENV_FILE"
        echo "    Edit it if needed (IYAGI_USER, ports), then re-run."
        echo ""
        read -rp "Press ENTER to open it now (or Ctrl+C to exit and edit manually)..."
        "${EDITOR:-nano}" "$ENV_FILE"
    fi
fi

# Preserve explicit process-level overrides so callers can bypass stale .env
# values (useful for dev helpers like tools/run-appimage.sh).
OVERRIDE_DOSBOX_SOURCE="${DOSBOX_SOURCE-__UNSET__}"
OVERRIDE_DOSBOX_BIN="${DOSBOX_BIN-__UNSET__}"
OVERRIDE_DOSBOX_SCANLINES="${DOSBOX_SCANLINES-__UNSET__}"
OVERRIDE_DOSBOX_GLSHADER="${DOSBOX_GLSHADER-__UNSET__}"

# AppImage: drop DOSBOX_BIN inherited from the parent environment (desktop session,
# dev shells) so resolve_dosbox_bin honors DOSBOX_SOURCE=bundled. A deliberate
# override is still honored via OVERRIDE_DOSBOX_BIN after sourcing .env.
if [ -n "${APPIMAGE:-}" ] && [ "$OVERRIDE_DOSBOX_BIN" = "__UNSET__" ]; then
    unset DOSBOX_BIN
fi

# Normalize CRLF so values like DOSBOX_CPU_CYCLES=2000\r parse as numeric.
if [ -f "$ENV_FILE" ] && command -v sed >/dev/null 2>&1 && grep -q $'\r' "$ENV_FILE" 2>/dev/null; then
    sed -i 's/\r$//' "$ENV_FILE" || true
fi

# shellcheck source=/dev/null
source "$ENV_FILE"

if [ "$OVERRIDE_DOSBOX_SOURCE" != "__UNSET__" ]; then
    DOSBOX_SOURCE="$OVERRIDE_DOSBOX_SOURCE"
fi
if [ "$OVERRIDE_DOSBOX_BIN" != "__UNSET__" ]; then
    DOSBOX_BIN="$OVERRIDE_DOSBOX_BIN"
fi
if [ "$OVERRIDE_DOSBOX_SCANLINES" != "__UNSET__" ]; then
    DOSBOX_SCANLINES="$OVERRIDE_DOSBOX_SCANLINES"
fi
if [ "$OVERRIDE_DOSBOX_GLSHADER" != "__UNSET__" ]; then
    DOSBOX_GLSHADER="$OVERRIDE_DOSBOX_GLSHADER"
fi

# AppImage: a parent environment (desktop, IDE, shell profile) can export
# DOSBOX_CPU_CYCLES=max / auto etc. If .env does not assign these keys, the bad
# value would otherwise survive `source` and make the guest (and cursor) run too fast.
if [ -n "${APPIMAGE:-}" ]; then
    if [[ ! "${DOSBOX_CPU_CYCLES:-}" =~ ^[0-9]+$ ]]; then
        if [ -n "${DOSBOX_CPU_CYCLES:-}" ]; then
            echo "NOTE: Ignoring invalid DOSBOX_CPU_CYCLES='$DOSBOX_CPU_CYCLES' from environment (using .env / default 1000)." >&2
        fi
        unset DOSBOX_CPU_CYCLES
    fi
    if [[ ! "${DOSBOX_FRAMESKIP:-}" =~ ^[0-9]+$ ]]; then
        if [ -n "${DOSBOX_FRAMESKIP:-}" ]; then
            echo "NOTE: Ignoring invalid DOSBOX_FRAMESKIP='$DOSBOX_FRAMESKIP' from environment (using .env / default 1)." >&2
        fi
        unset DOSBOX_FRAMESKIP
    fi
fi

IYAGI_USER="${IYAGI_USER:-user}"
IYAGI_SSH_PORT="${IYAGI_SSH_PORT:-22}"
BRIDGE_PORT="${BRIDGE_PORT:-2323}"
SSH_AUTH_MODE="${SSH_AUTH_MODE:-bbs}"
BRIDGE_CLIENT_ENCODING="${BRIDGE_CLIENT_ENCODING:-euc-kr}"
BRIDGE_SERVER_ENCODING="${BRIDGE_SERVER_ENCODING:-euc-kr}"
BRIDGE_SERVER_REPAIR_MOJIBAKE="${BRIDGE_SERVER_REPAIR_MOJIBAKE:-1}"
BRIDGE_ANSI_RESET_HACK="${BRIDGE_ANSI_RESET_HACK:-0}"
BRIDGE_ANSI_COLOR_COMPAT_HACK="${BRIDGE_ANSI_COLOR_COMPAT_HACK:-1}"
BRIDGE_ANSI_DEFAULT_FG="${BRIDGE_ANSI_DEFAULT_FG:-37}"
BRIDGE_ANSI_DEFAULT_BG="${BRIDGE_ANSI_DEFAULT_BG:-44}"
BRIDGE_ANSI_DEFAULT_MODE="${BRIDGE_ANSI_DEFAULT_MODE:-sgr}"
BRIDGE_DEBUG="${BRIDGE_DEBUG:-0}"
BRIDGE_DEBUG_RENDER_SERVER="${BRIDGE_DEBUG_RENDER_SERVER:-0}"
BRIDGE_SSH_ANNOUNCE_IYAGI="${BRIDGE_SSH_ANNOUNCE_IYAGI:-1}"
# Optional: refresh packaged I.CNF/I.TEL into runtime on each start (default off).
IYAGI_SYNC_CONFIG_ON_START="${IYAGI_SYNC_CONFIG_ON_START:-0}"
# tools/run-appimage.sh sets this so dev runs can force debug on after .env (default off).
if [[ "${IYAGI_BRIDGE_DEBUG_OVERRIDE:-0}" =~ ^(1|true|yes|on)$ ]]; then
    BRIDGE_DEBUG=1
fi
BRIDGE_CTRL_C_HANGUP="${BRIDGE_CTRL_C_HANGUP:-1}"
BRIDGE_CONNECT_TIMEOUT_SEC="${BRIDGE_CONNECT_TIMEOUT_SEC:-5}"
BRIDGE_BUSY_REPEAT="${BRIDGE_BUSY_REPEAT:-5}"
BRIDGE_BUSY_GAP_MS="${BRIDGE_BUSY_GAP_MS:-0}"
BRIDGE_DTMF_GAP_MS="${BRIDGE_DTMF_GAP_MS:-320}"
BRIDGE_POST_DTMF_DELAY_MS="${BRIDGE_POST_DTMF_DELAY_MS:-500}"
DOSBOX_VIDEO_BACKEND="${DOSBOX_VIDEO_BACKEND:-auto}"
DOSBOX_WAYLAND_STRICT="${DOSBOX_WAYLAND_STRICT:-0}"
# AppImage: use bundled DOSBox-Staging unless the user exported DOSBOX_SOURCE
# before launching (.env "auto" would otherwise prefer system dosbox and skew timing).
if [ -n "${APPIMAGE:-}" ]; then
    if [ "$OVERRIDE_DOSBOX_SOURCE" = "__UNSET__" ]; then
        DOSBOX_SOURCE="bundled"
    fi
else
    DOSBOX_SOURCE="${DOSBOX_SOURCE:-auto}"
fi
DOSBOX_BIN="${DOSBOX_BIN:-}"
DOSBOX_X_WINDOWRES="${DOSBOX_X_WINDOWRES:-1024x768}"
DOSBOX_X_SCALER="${DOSBOX_X_SCALER:-hq2x forced}"
DOSBOX_X_SCANLINES="${DOSBOX_X_SCANLINES:-0}"
DOSBOX_X_SCANLINE_SCALER="${DOSBOX_X_SCANLINE_SCALER:-scan2x forced}"
DOSBOX_X_SCANLINE_OUTPUT="${DOSBOX_X_SCANLINE_OUTPUT:-openglnb}"
DOSBOX_SCANLINES="${DOSBOX_SCANLINES:-1}"
DOSBOX_GLSHADER="${DOSBOX_GLSHADER:-crt/vga-1080p-fake-double-scan}"
DOSBOX_CPU_CORE="${DOSBOX_CPU_CORE:-simple}"
DOSBOX_CPU_CPUTYPE="${DOSBOX_CPU_CPUTYPE:-386}"
DOSBOX_CPU_CYCLES="${DOSBOX_CPU_CYCLES:-1000}"
DOSBOX_FRAMESKIP="${DOSBOX_FRAMESKIP:-1}"
if [[ ! "$DOSBOX_FRAMESKIP" =~ ^[0-9]+$ ]] || [ "$DOSBOX_FRAMESKIP" -lt 0 ] || [ "$DOSBOX_FRAMESKIP" -gt 10 ]; then
    DOSBOX_FRAMESKIP=1
fi

if [ "${BRIDGE_PORT:-}" = "auto" ] || [ -z "${BRIDGE_PORT:-}" ]; then
    BRIDGE_PORT="$(pick_unused_tcp_port)"
    echo "Selected bridge port automatically: $BRIDGE_PORT"
elif ! is_port_available "$BRIDGE_PORT"; then
    old_port="$BRIDGE_PORT"
    BRIDGE_PORT="$(pick_unused_tcp_port)"
    echo "Configured BRIDGE_PORT=$old_port is in use; switched to free port: $BRIDGE_PORT"
fi

# DOSBox-Staging expects numeric cpu_cycles (e.g. 1000), not "fixed 1000" on the CLI.
# DOSBox-X still uses classic cycles= with "fixed N" syntax.
if [[ "$DOSBOX_CPU_CYCLES" =~ ^[0-9]+$ ]]; then
    DOSBOX_CPU_CYCLES_ARG_X="fixed ${DOSBOX_CPU_CYCLES}"
    DOSBOX_CPU_CYCLES_ARG_STAGING="${DOSBOX_CPU_CYCLES}"
else
    # Staging needs a numeric cpu_cycles in conf/CLI; junk values (e.g. CRLF) become "max" speed.
    echo "WARNING: DOSBOX_CPU_CYCLES='$DOSBOX_CPU_CYCLES' is not a plain integer; using 1000 for Staging timing (see dosbox.conf comment)." >&2
    DOSBOX_CPU_CYCLES_ARG_X="$DOSBOX_CPU_CYCLES"
    DOSBOX_CPU_CYCLES_ARG_STAGING="1000"
fi

if [[ "${DOSBOX_X_SCANLINES,,}" =~ ^(1|true|yes|on)$ ]]; then
    DOSBOX_X_EFFECTIVE_SCALER="$DOSBOX_X_SCANLINE_SCALER"
    DOSBOX_X_EFFECTIVE_OUTPUT="$DOSBOX_X_SCANLINE_OUTPUT"
    DOSBOX_X_DOUBLESCAN="true"
else
    DOSBOX_X_EFFECTIVE_SCALER="$DOSBOX_X_SCALER"
    DOSBOX_X_EFFECTIVE_OUTPUT="surface"
    DOSBOX_X_DOUBLESCAN="false"
fi

DOSBOX_STAGING_OUTPUT="texture"
DOSBOX_STAGING_GLSHADER="none"
DOSBOX_STAGING_INTEGER_SCALING="auto"
DOSBOX_SCANLINE_WINDOWRES="${DOSBOX_SCANLINE_WINDOWRES:-1280x960}"
# Match tools/run-dosbox.sh: default 1024x768 unless scanline OpenGL path is active.
DOSBOX_STAGING_WINDOWRES="1024x768"
if [[ "${DOSBOX_SCANLINES,,}" =~ ^(1|true|yes|on)$ ]]; then
    if [ -d "$APPDIR/glshaders" ]; then
        DOSBOX_STAGING_OUTPUT="opengl"
        DOSBOX_STAGING_GLSHADER="$DOSBOX_GLSHADER"
        DOSBOX_STAGING_INTEGER_SCALING="vertical"
        DOSBOX_STAGING_WINDOWRES="$DOSBOX_SCANLINE_WINDOWRES"
    else
        echo "WARNING: DOSBOX_SCANLINES is enabled but glshaders are missing; falling back to texture output."
    fi
fi

# Prefer system dosbox for better desktop integration (title bar/decorations)
# when available. Fallback to bundled dosbox in the package.
resolve_dosbox_bin() {
    local bundled="$APPDIR/usr/bin/dosbox"
    local common_bins=(
        "/usr/bin/dosbox"
        "/usr/games/dosbox"
        "/usr/bin/dosbox-staging"
        "/usr/local/bin/dosbox"
        "/usr/local/bin/dosbox-staging"
    )

    # Highest priority: explicit path override.
    if [ -n "$DOSBOX_BIN" ]; then
        if [ -x "$DOSBOX_BIN" ]; then
            echo "$DOSBOX_BIN"
            return 0
        fi
        echo "ERROR: DOSBOX_BIN is set but not executable: $DOSBOX_BIN" >&2
        return 1
    fi

    find_system_dosbox() {
        if command -v dosbox >/dev/null 2>&1; then
            command -v dosbox
            return 0
        fi
        if command -v dosbox-staging >/dev/null 2>&1; then
            command -v dosbox-staging
            return 0
        fi
        local c
        for c in "${common_bins[@]}"; do
            if [ -x "$c" ]; then
                echo "$c"
                return 0
            fi
        done
        return 1
    }

    case "$DOSBOX_SOURCE" in
        system)
            if find_system_dosbox >/dev/null 2>&1; then
                find_system_dosbox
            else
                echo "ERROR: DOSBOX_SOURCE=system but no system dosbox binary found (PATH or common locations)" >&2
                return 1
            fi
            ;;
        bundled)
            if [ -x "$bundled" ]; then
                echo "$bundled"
            else
                echo "ERROR: DOSBOX_SOURCE=bundled but bundled dosbox missing at $bundled" >&2
                return 1
            fi
            ;;
        auto|*)
            if find_system_dosbox >/dev/null 2>&1; then
                find_system_dosbox
            elif [ -x "$bundled" ]; then
                echo "$bundled"
            else
                echo "ERROR: neither system dosbox nor bundled dosbox is available" >&2
                return 1
            fi
            ;;
    esac
}

DOSBOX="$(resolve_dosbox_bin)"
echo "Using DOSBox binary: $DOSBOX"
echo "Config root: $CONFIG_ROOT"
echo "Data root: $DATA_ROOT"
echo "Env file (sourced): $ENV_FILE"
echo "DOSBox profile: DOSBOX_SOURCE=$DOSBOX_SOURCE cpu_cycles=$DOSBOX_CPU_CYCLES_ARG_STAGING frameskip=$DOSBOX_FRAMESKIP window=${DOSBOX_STAGING_WINDOWRES} output=${DOSBOX_STAGING_OUTPUT} (DOSBOX_SCANLINES=$DOSBOX_SCANLINES)"

# DOSBox-X and DOSBox-Staging don't share identical config options.
# If DOSBox-X is used, force a 2x scaler at launch so window size
# behavior is consistent for this project.
IS_DOSBOX_X=0
DOSBOX_ARGS_PRIMARY=()
DOSBOX_ARGS_FALLBACK=()
if [[ "$(basename "$DOSBOX")" == *dosbox-x* ]]; then
    IS_DOSBOX_X=1
    # DOSBox-X profile tuned for strict 2x pixel-doubling:
    # - Primary: surface + forced normal2x (most reliable for exact 2x).
    # - Fallback: OpenGL backend + fixed window size.
    DOSBOX_ARGS_PRIMARY=(
        -nomenu
        -set "output=${DOSBOX_X_EFFECTIVE_OUTPUT}"
        -set "windowresolution=${DOSBOX_X_WINDOWRES}"
        -set "doublescan=${DOSBOX_X_DOUBLESCAN}"
        -set "showmenu=false"
        -set "scaler=${DOSBOX_X_EFFECTIVE_SCALER}"
    )
    DOSBOX_ARGS_FALLBACK=(
        -nomenu
        -set "output=openglnb"
        -set "windowresolution=${DOSBOX_X_WINDOWRES}"
        -set "doublescan=${DOSBOX_X_DOUBLESCAN}"
        -set "showmenu=false"
        -set "scaler=${DOSBOX_X_EFFECTIVE_SCALER}"
    )
    echo "Detected DOSBox-X: output=${DOSBOX_X_EFFECTIVE_OUTPUT}, scaler=${DOSBOX_X_EFFECTIVE_SCALER}, scanlines=${DOSBOX_X_SCANLINES}"
fi

# ─── SSH auth mode setup ─────────────────────────────────────────────────────

case "$SSH_AUTH_MODE" in
    bbs)
        echo "SSH auth mode: bbs (no local keypair required)"
        ;;
    key)
        mkdir -p "$KEYS_DIR"
        if [ ! -f "$KEY_FILE" ]; then
            echo ""
            echo "=== First run: generating SSH key pair ==="
            ssh-keygen -t rsa -b 4096 -f "$KEY_FILE" -N "" -C "iyagi-terminal"
            echo ""
            echo ">>> Add the public key below to your SSH server's ~/.ssh/authorized_keys:"
            echo ""
            cat "${KEY_FILE}.pub"
            echo ""
            read -rp "Press ENTER once the key has been uploaded to the server..."
        fi
        ;;
    *)
        echo "ERROR: invalid SSH_AUTH_MODE=$SSH_AUTH_MODE (expected: bbs or key)"
        exit 1
        ;;
esac

# ─── Start the bridge ────────────────────────────────────────────────────────

SSH_ARGS_COMMON="-o BatchMode=no -o PreferredAuthentications=keyboard-interactive,password,publickey -o PubkeyAuthentication=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
if [ "$SSH_AUTH_MODE" = "key" ]; then
    SSH_TEMPLATE="ssh $SSH_ARGS_COMMON -i ${KEY_FILE} -p {port} {userhost}"
else
    SSH_TEMPLATE="ssh $SSH_ARGS_COMMON -p {port} {userhost}"
fi
echo "Bridge listen (IYAGI dial target): 127.0.0.1:${BRIDGE_PORT}"
echo "Bridge debug logging: ${BRIDGE_DEBUG}"
echo "Bridge Ctrl+C hangup: ${BRIDGE_CTRL_C_HANGUP}"
echo "Bridge connect timeout: ${BRIDGE_CONNECT_TIMEOUT_SEC}s"
echo "Bridge busy repeat: ${BRIDGE_BUSY_REPEAT}"
echo "Bridge busy gap: ${BRIDGE_BUSY_GAP_MS}ms"
echo "Bridge ANSI reset hack: ${BRIDGE_ANSI_RESET_HACK}"
echo "Bridge ANSI color compat: ${BRIDGE_ANSI_COLOR_COMPAT_HACK} (default fg=${BRIDGE_ANSI_DEFAULT_FG} bg=${BRIDGE_ANSI_DEFAULT_BG} mode=${BRIDGE_ANSI_DEFAULT_MODE})"
echo "Bridge debug render server: ${BRIDGE_DEBUG_RENDER_SERVER}"
echo "Bridge SSH announce IYAGI (OpenSSH SetEnv): ${BRIDGE_SSH_ANNOUNCE_IYAGI}"
echo "Bridge DTMF gap: ${BRIDGE_DTMF_GAP_MS}ms"
echo "Bridge post-DTMF delay: ${BRIDGE_POST_DTMF_DELAY_MS}ms"
echo "Bridge ATDT target mode: enabled (example: ATDT127.0.0.1:${IYAGI_SSH_PORT})"

# IYAGI_DEBUG_LOG: optional file redirect for bridge (uncomment to use)
# IYAGI_DEBUG_LOG="${IYAGI_DEBUG_LOG:-0}"
# IYAGI_DEBUG_LOG_FILE="${IYAGI_DEBUG_LOG_FILE:-}"
# BRIDGE_LOG_PATH=""
# if [[ "${IYAGI_DEBUG_LOG,,}" =~ ^(1|true|yes|on)$ ]] || [ -n "${IYAGI_DEBUG_LOG_FILE:-}" ]; then
#     LOG_DIR="$DATA_ROOT/logs"
#     mkdir -p "$LOG_DIR"
#     if [ -n "${IYAGI_DEBUG_LOG_FILE:-}" ]; then
#         BRIDGE_LOG_PATH="$IYAGI_DEBUG_LOG_FILE"
#     else
#         BRIDGE_LOG_PATH="$LOG_DIR/bridge-$(date +%Y%m%d-%H%M%S).log"
#     fi
#     echo "Bridge debug log: $BRIDGE_LOG_PATH"
# fi
BRIDGE_LOG_PATH=""

bridge_cmd=(
    env
    BRIDGE_PORT="$BRIDGE_PORT"
    BRIDGE_CMD=""
    BRIDGE_CMD_TEMPLATE="$SSH_TEMPLATE"
    BRIDGE_SSH_USER="$IYAGI_USER"
    BRIDGE_CLIENT_ENCODING="$BRIDGE_CLIENT_ENCODING"
    BRIDGE_SERVER_ENCODING="$BRIDGE_SERVER_ENCODING"
    BRIDGE_SERVER_REPAIR_MOJIBAKE="$BRIDGE_SERVER_REPAIR_MOJIBAKE"
    BRIDGE_ANSI_RESET_HACK="$BRIDGE_ANSI_RESET_HACK"
    BRIDGE_ANSI_COLOR_COMPAT_HACK="$BRIDGE_ANSI_COLOR_COMPAT_HACK"
    BRIDGE_ANSI_DEFAULT_FG="$BRIDGE_ANSI_DEFAULT_FG"
    BRIDGE_ANSI_DEFAULT_BG="$BRIDGE_ANSI_DEFAULT_BG"
    BRIDGE_ANSI_DEFAULT_MODE="$BRIDGE_ANSI_DEFAULT_MODE"
    BRIDGE_DEBUG="$BRIDGE_DEBUG"
    BRIDGE_DEBUG_RENDER_SERVER="$BRIDGE_DEBUG_RENDER_SERVER"
    BRIDGE_SSH_ANNOUNCE_IYAGI="$BRIDGE_SSH_ANNOUNCE_IYAGI"
    BRIDGE_CTRL_C_HANGUP="$BRIDGE_CTRL_C_HANGUP"
    BRIDGE_CONNECT_TIMEOUT_SEC="$BRIDGE_CONNECT_TIMEOUT_SEC"
    BRIDGE_BUSY_REPEAT="$BRIDGE_BUSY_REPEAT"
    BRIDGE_BUSY_GAP_MS="$BRIDGE_BUSY_GAP_MS"
    BRIDGE_DTMF_GAP_MS="$BRIDGE_DTMF_GAP_MS"
    BRIDGE_POST_DTMF_DELAY_MS="$BRIDGE_POST_DTMF_DELAY_MS"
    "$BRIDGE"
)
# if [ -n "$BRIDGE_LOG_PATH" ]; then
#     "${bridge_cmd[@]}" >>"$BRIDGE_LOG_PATH" 2>&1 &
# else
    "${bridge_cmd[@]}" &
# fi

BRIDGE_PID=$!
echo "bridge started on 127.0.0.1:${BRIDGE_PORT} (pid $BRIDGE_PID)"
sleep 1

# Verify the bridge actually started
if ! kill -0 "$BRIDGE_PID" 2>/dev/null; then
    echo "ERROR: bridge failed to start. Check that $BRIDGE exists and is executable."
    exit 1
fi

# ─── Run DOSBox ──────────────────────────────────────────────────────────────

# dosbox.conf uses relative paths (./app, ./downloads), so we must cd to a
# staging directory that has both symlinks in place.
STAGING="$DATA_ROOT/staging"
mkdir -p "$STAGING"
ensure_runtime_app_copy
if [[ "${IYAGI_SYNC_CONFIG_ON_START,,}" =~ ^(1|true|yes|on)$ ]]; then
    echo "Syncing IYAGI runtime config (I.CNF/I.TEL) from packaged defaults..."
    sync_iyagi_runtime_config
fi
if [ -n "${PORTABLE_IYAGI_DATA_DIR:-}" ]; then
    for name in I.CNF I.TEL; do
        if [ -f "$PORTABLE_IYAGI_DATA_DIR/app/$name" ]; then
            mkdir -p "$RUNTIME_APP_DIR/IYAGI"
            cp -f "$PORTABLE_IYAGI_DATA_DIR/app/$name" "$RUNTIME_APP_DIR/$name"
            cp -f "$PORTABLE_IYAGI_DATA_DIR/app/$name" "$RUNTIME_APP_DIR/IYAGI/$name"
            echo "Portable iyagi-data: synced app/$name -> $RUNTIME_APP_DIR/"
        fi
    done
fi
# Symlink writable app files into the staging area.
ln -sfn "$RUNTIME_APP_DIR" "$STAGING/app"
ln -sfn "$DOWNLOADS_DIR" "$STAGING/downloads"
if [ -d "$APPDIR/glshaders" ]; then
    ln -sfn "$APPDIR/glshaders" "$STAGING/glshaders"
fi
# Always refresh dosbox.conf from the packaged version so updates take effect.
# (Users should customize via .env, not by editing staging/dosbox.conf.)
cp "$DOSBOX_CONF" "$STAGING/dosbox.conf"
if [ -n "${PORTABLE_IYAGI_DATA_DIR:-}" ] && [ -f "$PORTABLE_IYAGI_DATA_DIR/dosbox.conf" ]; then
    cp -f "$PORTABLE_IYAGI_DATA_DIR/dosbox.conf" "$STAGING/dosbox.conf"
    echo "Portable iyagi-data: base dosbox.conf from $PORTABLE_IYAGI_DATA_DIR (bridge/CPU lines patched next)"
fi

# Route COM4 traffic to the local bridge (AT commands are parsed by bridge).
python3 - "$STAGING/dosbox.conf" "$BRIDGE_PORT" "$DOSBOX_CPU_CORE" "$DOSBOX_CPU_CPUTYPE" "$DOSBOX_CPU_CYCLES_ARG_STAGING" "$DOSBOX_FRAMESKIP" <<'PYEOF'
import pathlib
import re
import sys

conf_path = pathlib.Path(sys.argv[1])
bridge_port = sys.argv[2].replace("\r", "").strip()
core = sys.argv[3].replace("\r", "").strip()
cputype = sys.argv[4].replace("\r", "").strip()
cycles_staging = sys.argv[5].replace("\r", "").strip()
frameskip = sys.argv[6].replace("\r", "").strip()
text = conf_path.read_text(encoding="utf-8", errors="ignore")

# Match tools/run-dosbox.py: force baseline SDL output + MIDI before bridge/CPU tweaks.
patterns = [
    (r"(?im)^output\s*=.*$", "output=texture"),
    (r"(?im)^mididevice\s*=.*$", "mididevice=none"),
]
for pat, repl in patterns:
    if re.search(pat, text):
        text = re.sub(pat, repl, text)
    else:
        text += "\n" + repl + "\n"

# Staging: plain cpu_cycles=2000 can be treated differently than fixed 2000 in some builds.
cycles_conf = f"fixed {cycles_staging}" if cycles_staging.isdigit() else cycles_staging

serial4_line = f"serial4=nullmodem server:127.0.0.1 port:{bridge_port} transparent:1"
serial1_line = "serial1=disabled"
mouse_capture_line = "mouse_capture=nomouse"
mouse_middle_release_line = "mouse_middle_release=false"
dos_mouse_driver_line = "dos_mouse_driver=false"
texture_renderer_line = "texture_renderer=auto"

if re.search(r"(?m)^\s*serial1\s*=", text):
    text = re.sub(r"(?m)^\s*serial1\s*=.*$", serial1_line, text)
else:
    text += f"\n[serial]\n{serial1_line}\n"

if re.search(r"(?m)^\s*serial4\s*=", text):
    text = re.sub(r"(?m)^\s*serial4\s*=.*$", serial4_line, text)
else:
    if "[serial]" not in text:
        text += "\n[serial]\n"
    text += f"{serial4_line}\n"

if re.search(r"(?m)^\s*mouse_capture\s*=", text):
    text = re.sub(r"(?m)^\s*mouse_capture\s*=.*$", mouse_capture_line, text)
else:
    if "[mouse]" not in text:
        text += "\n[mouse]\n"
    text += f"{mouse_capture_line}\n"

if re.search(r"(?m)^\s*mouse_middle_release\s*=", text):
    text = re.sub(r"(?m)^\s*mouse_middle_release\s*=.*$", mouse_middle_release_line, text)
else:
    if "[mouse]" not in text:
        text += "\n[mouse]\n"
    text += f"{mouse_middle_release_line}\n"

if re.search(r"(?m)^\s*dos_mouse_driver\s*=", text):
    text = re.sub(r"(?m)^\s*dos_mouse_driver\s*=.*$", dos_mouse_driver_line, text)
else:
    if "[mouse]" not in text:
        text += "\n[mouse]\n"
    text += f"{dos_mouse_driver_line}\n"

if re.search(r"(?m)^\s*texture_renderer\s*=", text):
    text = re.sub(r"(?m)^\s*texture_renderer\s*=.*$", texture_renderer_line, text)
else:
    if "[sdl]" not in text:
        text += "\n[sdl]\n"
    text += f"{texture_renderer_line}\n"

# Bake CPU + render timing into conf (Staging ignores -set frameskip).
# IMPORTANT: do not use "append on miss" for cpu_cycles — our template has
# cycles= but not cpu_cycles=; appending cpu_cycles at EOF first duplicates lines
# and can confuse Staging (faster/wrong timing).
if re.search(r"(?im)^\s*core\s*=", text):
    text = re.sub(r"(?im)^\s*core\s*=.*$", f"core={core}", text)
else:
    if "[cpu]" not in text:
        text += "\n[cpu]\n"
    text += f"core={core}\n"

if re.search(r"(?im)^\s*cputype\s*=", text):
    text = re.sub(r"(?im)^\s*cputype\s*=.*$", f"cputype={cputype}", text)
else:
    if "[cpu]" not in text:
        text += "\n[cpu]\n"
    text += f"cputype={cputype}\n"

if re.search(r"(?im)^\s*cycles\s*=", text):
    text = re.sub(r"(?im)^\s*cycles\s*=.*$", f"cpu_cycles={cycles_conf}", text)
elif re.search(r"(?im)^\s*cpu_cycles\s*=", text):
    text = re.sub(r"(?im)^\s*cpu_cycles\s*=.*$", f"cpu_cycles={cycles_conf}", text)
else:
    if "[cpu]" not in text:
        text += "\n[cpu]\n"
    text += f"cpu_cycles={cycles_conf}\n"

if re.search(r"(?im)^\s*frameskip\s*=", text):
    text = re.sub(r"(?im)^\s*frameskip\s*=.*$", f"frameskip={frameskip}", text)
else:
    if "[render]" not in text:
        text += "\n[render]\n"
    text += f"frameskip={frameskip}\n"

conf_path.write_text(text, encoding="utf-8")
PYEOF

set +e
run_dosbox_with_env() {
    local label="$1"
    local profile="$2"
    shift 2
    local -a extra_args=()
    local -a forced_env=(
        "SDL_RENDER_DRIVER=software"
        "SDL_FRAMEBUFFER_ACCELERATION=software"
        "LIBGL_ALWAYS_SOFTWARE=1"
    )
    if [ "$profile" = "fallback" ]; then
        extra_args=("${DOSBOX_ARGS_FALLBACK[@]}")
    else
        extra_args=("${DOSBOX_ARGS_PRIMARY[@]}")
    fi
    for env_arg in "$@"; do
        if [ "$env_arg" = "SDL_VIDEODRIVER=x11" ]; then
            forced_env+=("SDL_VIDEO_X11_FORCE_EGL=1")
            break
        fi
    done
    echo "Launching DOSBox backend: $label"
    if [ "$IS_DOSBOX_X" -eq 1 ]; then
        (cd "$STAGING" && env "${forced_env[@]}" "$@" "$DOSBOX" -conf dosbox.conf -set "core=${DOSBOX_CPU_CORE}" -set "cputype=${DOSBOX_CPU_CPUTYPE}" -set "cycles=${DOSBOX_CPU_CYCLES_ARG_X}" -set "frameskip=${DOSBOX_FRAMESKIP}" -set "mouse_capture=nomouse" -set "mouse_middle_release=false" -set "dos_mouse_driver=false" "${extra_args[@]}")
    else
        # Note: DOSBox-Staging rejects -set frameskip=...; frameskip is applied via patched dosbox.conf.
        # --noprimaryconf/--nolocalconf match run-dosbox.sh so host ~/.config/dosbox-staging/*.conf cannot override cycles/timing.
        (cd "$STAGING" && env "${forced_env[@]}" "$@" "$DOSBOX" \
            --noprimaryconf --nolocalconf \
            -conf dosbox.conf \
            -set "core=${DOSBOX_CPU_CORE}" -set "cputype=${DOSBOX_CPU_CPUTYPE}" -set "cpu_cycles=${DOSBOX_CPU_CYCLES_ARG_STAGING}" \
            -set "startup_verbosity=quiet" \
            -set "windowresolution=${DOSBOX_STAGING_WINDOWRES}" \
            -set "output=${DOSBOX_STAGING_OUTPUT}" -set "glshader=${DOSBOX_STAGING_GLSHADER}" -set "integer_scaling=${DOSBOX_STAGING_INTEGER_SCALING}" \
            -set "ne2000=false" -set "texture_renderer=auto" \
            -set "mouse_capture=nomouse" -set "mouse_middle_release=false" -set "dos_mouse_driver=false" "${extra_args[@]}")
    fi
}

run_dosbox_plain() {
    local label="$1"
    local profile="$2"
    local -a extra_args=()
    if [ "$profile" = "fallback" ]; then
        extra_args=("${DOSBOX_ARGS_FALLBACK[@]}")
    else
        extra_args=("${DOSBOX_ARGS_PRIMARY[@]}")
    fi
    echo "Launching DOSBox backend: $label"
    if [ "$IS_DOSBOX_X" -eq 1 ]; then
        (cd "$STAGING" && SDL_FRAMEBUFFER_ACCELERATION=software LIBGL_ALWAYS_SOFTWARE=1 "$DOSBOX" -conf dosbox.conf -set "core=${DOSBOX_CPU_CORE}" -set "cputype=${DOSBOX_CPU_CPUTYPE}" -set "cycles=${DOSBOX_CPU_CYCLES_ARG_X}" -set "frameskip=${DOSBOX_FRAMESKIP}" -set "mouse_capture=nomouse" -set "mouse_middle_release=false" -set "dos_mouse_driver=false" "${extra_args[@]}")
    else
        (cd "$STAGING" && SDL_RENDER_DRIVER=software SDL_FRAMEBUFFER_ACCELERATION=software LIBGL_ALWAYS_SOFTWARE=1 "$DOSBOX" \
            --noprimaryconf --nolocalconf \
            -conf dosbox.conf \
            -set "core=${DOSBOX_CPU_CORE}" -set "cputype=${DOSBOX_CPU_CPUTYPE}" -set "cpu_cycles=${DOSBOX_CPU_CYCLES_ARG_STAGING}" \
            -set "startup_verbosity=quiet" \
            -set "windowresolution=${DOSBOX_STAGING_WINDOWRES}" \
            -set "output=${DOSBOX_STAGING_OUTPUT}" -set "glshader=${DOSBOX_STAGING_GLSHADER}" -set "integer_scaling=${DOSBOX_STAGING_INTEGER_SCALING}" \
            -set "ne2000=false" -set "texture_renderer=auto" \
            -set "mouse_capture=nomouse" -set "mouse_middle_release=false" -set "dos_mouse_driver=false" "${extra_args[@]}")
    fi
}

DOSBOX_RC=1

should_retry_backend() {
    local rc="$1"
    # User interrupts should not trigger backend fallback relaunch.
    if [ "$rc" -eq 130 ] || [ "$rc" -eq 143 ]; then
        return 1
    fi
    [ "$rc" -ne 0 ]
}

# For DOSBox-X, prefer a plain launch (no forced SDL backend env vars)
# to avoid backend-specific window quirks.
if [ "$IS_DOSBOX_X" -eq 1 ]; then
    run_dosbox_plain "dosbox-x direct" "primary"
    DOSBOX_RC=$?
    if should_retry_backend "$DOSBOX_RC"; then
        echo "DOSBox-X direct primary profile failed; trying fallback profile..."
        run_dosbox_plain "dosbox-x direct fallback profile" "fallback"
        DOSBOX_RC=$?
    fi
elif [ "$DOSBOX_VIDEO_BACKEND" = "wayland" ]; then
    run_dosbox_with_env "wayland (forced)" "primary" \
        SDL_VIDEODRIVER=wayland \
        SDL_RENDER_DRIVER=software \
        SDL_VIDEO_WAYLAND_ALLOW_LIBDECOR=1 \
        SDL_VIDEO_WAYLAND_PREFER_LIBDECOR=1 \
        LIBGL_ALWAYS_SOFTWARE=1
    DOSBOX_RC=$?
    if should_retry_backend "$DOSBOX_RC" && [ "$IS_DOSBOX_X" -eq 1 ]; then
        echo "Wayland primary profile failed; trying DOSBox-X fallback profile..."
        run_dosbox_with_env "wayland (forced fallback profile)" "fallback" \
            SDL_VIDEODRIVER=wayland \
            SDL_RENDER_DRIVER=software \
            SDL_VIDEO_WAYLAND_ALLOW_LIBDECOR=1 \
            SDL_VIDEO_WAYLAND_PREFER_LIBDECOR=1 \
            LIBGL_ALWAYS_SOFTWARE=1
        DOSBOX_RC=$?
    fi
elif [ "$DOSBOX_VIDEO_BACKEND" = "x11" ]; then
    run_dosbox_with_env "x11 (forced)" "primary" \
        SDL_VIDEODRIVER=x11 \
        SDL_RENDER_DRIVER=software \
        LIBGL_ALWAYS_SOFTWARE=1
    DOSBOX_RC=$?
    if should_retry_backend "$DOSBOX_RC" && [ "$IS_DOSBOX_X" -eq 1 ]; then
        echo "X11 primary profile failed; trying DOSBox-X fallback profile..."
        run_dosbox_with_env "x11 (forced fallback profile)" "fallback" \
            SDL_VIDEODRIVER=x11 \
            SDL_RENDER_DRIVER=software \
            LIBGL_ALWAYS_SOFTWARE=1
        DOSBOX_RC=$?
    fi
else
    # Auto mode: choose by session type, then fallback.
    if [ "${XDG_SESSION_TYPE:-}" = "wayland" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
        if [ "$DOSBOX_WAYLAND_STRICT" = "1" ] || [ -z "${DISPLAY:-}" ]; then
            run_dosbox_with_env "wayland (auto strict)" "primary" \
                SDL_VIDEODRIVER=wayland \
                SDL_RENDER_DRIVER=software \
                SDL_VIDEO_WAYLAND_ALLOW_LIBDECOR=1 \
                SDL_VIDEO_WAYLAND_PREFER_LIBDECOR=1 \
                LIBGL_ALWAYS_SOFTWARE=1
            DOSBOX_RC=$?
            if should_retry_backend "$DOSBOX_RC" && [ "$IS_DOSBOX_X" -eq 1 ]; then
                echo "Wayland primary profile failed; trying DOSBox-X fallback profile..."
                run_dosbox_with_env "wayland (auto strict fallback profile)" "fallback" \
                    SDL_VIDEODRIVER=wayland \
                    SDL_RENDER_DRIVER=software \
                    SDL_VIDEO_WAYLAND_ALLOW_LIBDECOR=1 \
                    SDL_VIDEO_WAYLAND_PREFER_LIBDECOR=1 \
                    LIBGL_ALWAYS_SOFTWARE=1
                DOSBOX_RC=$?
            fi
            if should_retry_backend "$DOSBOX_RC" && [ -n "${DISPLAY:-}" ]; then
                echo "Wayland backend failed; trying x11 fallback..."
                run_dosbox_with_env "x11 (fallback)" "primary" \
                    SDL_VIDEODRIVER=x11 \
                    SDL_RENDER_DRIVER=software \
                    LIBGL_ALWAYS_SOFTWARE=1
                DOSBOX_RC=$?
                if should_retry_backend "$DOSBOX_RC" && [ "$IS_DOSBOX_X" -eq 1 ]; then
                    echo "X11 primary profile failed; trying DOSBox-X fallback profile..."
                    run_dosbox_with_env "x11 (fallback fallback profile)" "fallback" \
                        SDL_VIDEODRIVER=x11 \
                        SDL_RENDER_DRIVER=software \
                        LIBGL_ALWAYS_SOFTWARE=1
                    DOSBOX_RC=$?
                fi
            fi
        else
            # Prefer x11 under Wayland by default for window decorations/title bar
            # on portable/bundled builds lacking robust libdecor integration.
            run_dosbox_with_env "x11 (auto preferred on wayland)" "primary" \
                SDL_VIDEODRIVER=x11 \
                SDL_RENDER_DRIVER=software \
                LIBGL_ALWAYS_SOFTWARE=1
            DOSBOX_RC=$?
            if should_retry_backend "$DOSBOX_RC"; then
                echo "x11 preferred backend failed; trying wayland fallback..."
                run_dosbox_with_env "wayland (auto fallback)" "primary" \
                    SDL_VIDEODRIVER=wayland \
                    SDL_RENDER_DRIVER=software \
                    SDL_VIDEO_WAYLAND_ALLOW_LIBDECOR=1 \
                    SDL_VIDEO_WAYLAND_PREFER_LIBDECOR=1 \
                    LIBGL_ALWAYS_SOFTWARE=1
                DOSBOX_RC=$?
            fi
            if should_retry_backend "$DOSBOX_RC" && [ "$IS_DOSBOX_X" -eq 1 ]; then
                echo "Fallback profile after x11/wayland failures..."
                run_dosbox_with_env "auto fallback profile" "fallback" \
                    SDL_RENDER_DRIVER=software \
                    LIBGL_ALWAYS_SOFTWARE=1
                DOSBOX_RC=$?
            fi
        fi
    elif [ -n "${DISPLAY:-}" ]; then
        run_dosbox_with_env "x11 (auto)" "primary" \
            SDL_VIDEODRIVER=x11 \
            SDL_RENDER_DRIVER=software \
            LIBGL_ALWAYS_SOFTWARE=1
        DOSBOX_RC=$?
        if should_retry_backend "$DOSBOX_RC" && [ "$IS_DOSBOX_X" -eq 1 ]; then
            echo "X11 primary profile failed; trying DOSBox-X fallback profile..."
            run_dosbox_with_env "x11 (auto fallback profile)" "fallback" \
                SDL_VIDEODRIVER=x11 \
                SDL_RENDER_DRIVER=software \
                LIBGL_ALWAYS_SOFTWARE=1
            DOSBOX_RC=$?
        fi
        if should_retry_backend "$DOSBOX_RC" && [ -n "${WAYLAND_DISPLAY:-}" ]; then
            echo "X11 backend failed; trying wayland fallback..."
            run_dosbox_with_env "wayland (fallback)" "primary" \
                SDL_VIDEODRIVER=wayland \
                SDL_RENDER_DRIVER=software \
                SDL_VIDEO_WAYLAND_ALLOW_LIBDECOR=1 \
                SDL_VIDEO_WAYLAND_PREFER_LIBDECOR=1 \
                LIBGL_ALWAYS_SOFTWARE=1
            DOSBOX_RC=$?
            if should_retry_backend "$DOSBOX_RC" && [ "$IS_DOSBOX_X" -eq 1 ]; then
                echo "Wayland primary profile failed; trying DOSBox-X fallback profile..."
                run_dosbox_with_env "wayland (fallback fallback profile)" "fallback" \
                    SDL_VIDEODRIVER=wayland \
                    SDL_RENDER_DRIVER=software \
                    SDL_VIDEO_WAYLAND_ALLOW_LIBDECOR=1 \
                    SDL_VIDEO_WAYLAND_PREFER_LIBDECOR=1 \
                    LIBGL_ALWAYS_SOFTWARE=1
                DOSBOX_RC=$?
            fi
        fi
    else
        # Last resort if neither DISPLAY nor WAYLAND_DISPLAY is set.
        run_dosbox_with_env "default (no session hints)" "primary" \
            SDL_RENDER_DRIVER=software \
            LIBGL_ALWAYS_SOFTWARE=1
        DOSBOX_RC=$?
        if should_retry_backend "$DOSBOX_RC" && [ "$IS_DOSBOX_X" -eq 1 ]; then
            echo "Default primary profile failed; trying DOSBox-X fallback profile..."
            run_dosbox_with_env "default (fallback profile)" "fallback" \
                SDL_RENDER_DRIVER=software \
                LIBGL_ALWAYS_SOFTWARE=1
            DOSBOX_RC=$?
        fi
    fi
fi
set -e

if [ "$DOSBOX_RC" -ne 0 ]; then
    echo "WARNING: DOSBox exited with code $DOSBOX_RC"
fi
