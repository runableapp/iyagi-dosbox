#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# DOSBox-Staging only (no DOSBox-X fallback).
DOSBOX_VERSION_PIN="0.82.2"
DOSBOX_URL_PIN="https://github.com/dosbox-staging/dosbox-staging/releases/download/v${DOSBOX_VERSION_PIN}/dosbox-staging-linux-x86_64-v${DOSBOX_VERSION_PIN}.tar.xz"
DOSBOX_ROOT="$REPO_ROOT/third_party/dosbox-staging"
DOSBOX_CACHE_DIR="$DOSBOX_ROOT/cache"
DOSBOX_UNPACKED_DIR="$DOSBOX_ROOT/unpacked"
DOSBOX_BIN="$DOSBOX_UNPACKED_DIR/dosbox"

USER_DATA_ROOT="${USER_DATA_ROOT:-$REPO_ROOT/iyagi-data}"
RUN_DIR="$USER_DATA_ROOT/staging"
APP_DIR="$USER_DATA_ROOT/app"
DOWNLOADS_DIR="$USER_DATA_ROOT/downloads"
KEYS_DIR="$USER_DATA_ROOT/keys"
KEY_FILE="$KEYS_DIR/id_rsa"
ENV_FILE="$USER_DATA_ROOT/.env"
BRIDGE_BIN="$REPO_ROOT/.tmp/direct-run/bridge"
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

ensure_portable_dosbox() {
    local need_install=0
    if [ ! -x "$DOSBOX_BIN" ]; then
        need_install=1
    else
        local ver_out
        ver_out="$("$DOSBOX_BIN" --version 2>/dev/null || true)"
        if [[ "$ver_out" != *"version ${DOSBOX_VERSION_PIN}"* ]]; then
            need_install=1
        fi
    fi

    if [ "$need_install" -eq 0 ]; then
        return 0
    fi

    echo "Installing portable DOSBox-Staging ${DOSBOX_VERSION_PIN}..."
    mkdir -p "$DOSBOX_CACHE_DIR" "$DOSBOX_UNPACKED_DIR"
    local archive="$DOSBOX_CACHE_DIR/dosbox-staging-linux-x86_64-v${DOSBOX_VERSION_PIN}.tar.xz"
    wget -q --show-progress "$DOSBOX_URL_PIN" -O "$archive"

    rm -rf "$DOSBOX_UNPACKED_DIR"
    mkdir -p "$DOSBOX_UNPACKED_DIR"
    tar xf "$archive" -C "$DOSBOX_UNPACKED_DIR" --strip-components=1

    # Some archives place the binary under usr/bin.
    if [ ! -x "$DOSBOX_BIN" ] && [ -x "$DOSBOX_UNPACKED_DIR/usr/bin/dosbox" ]; then
        cp "$DOSBOX_UNPACKED_DIR/usr/bin/dosbox" "$DOSBOX_BIN"
        chmod +x "$DOSBOX_BIN"
    fi
    if [ ! -x "$DOSBOX_BIN" ]; then
        echo "ERROR: installed DOSBox binary not found at $DOSBOX_BIN"
        exit 1
    fi
}

bridge_needs_rebuild() {
    if [ ! -x "$BRIDGE_BIN" ]; then
        return 0
    fi
    python3 - "$REPO_ROOT/bridge" "$BRIDGE_BIN" <<'PYEOF'
from pathlib import Path
import sys

bridge_dir = Path(sys.argv[1])
bin_path = Path(sys.argv[2])
bin_mtime = bin_path.stat().st_mtime_ns

for p in bridge_dir.rglob("*"):
    if not p.is_file():
        continue
    # Rebuild on any Go source/module change or embedded-sound generator inputs.
    if p.suffix in {".go"} or p.name in {"go.mod", "go.sum"}:
        if p.stat().st_mtime_ns > bin_mtime:
            raise SystemExit(0)

raise SystemExit(1)
PYEOF
}

sync_iyagi_runtime_config() {
    local src_dir="$1"
    local dst_dir="$2"
    for name in I.CNF I.TEL; do
        if [ -f "$src_dir/$name" ]; then
            cp -f "$src_dir/$name" "$dst_dir/$name"
        fi
    done
}

if [ ! -f "$REPO_ROOT/resources/common/.env.example" ]; then
    echo "ERROR: missing .env template at resources/common/.env.example"
    exit 1
fi

mkdir -p "$APP_DIR" "$DOWNLOADS_DIR" "$RUN_DIR" "$(dirname "$BRIDGE_BIN")"

if [ ! -f "$ENV_FILE" ]; then
    cp "$REPO_ROOT/resources/common/.env.example" "$ENV_FILE"
    echo "Created config: $ENV_FILE"
fi

# If caller already exported BRIDGE_DEBUG, keep it; otherwise this dev wrapper defaults to ON
# after .env is loaded (direct AppImage / .env alone default to BRIDGE_DEBUG=0).
_iyagi_bridge_debug_from_caller=0
if [ -n "${BRIDGE_DEBUG+x}" ]; then
    _iyagi_bridge_debug_from_caller=1
fi

# shellcheck source=/dev/null
source "$ENV_FILE"
IYAGI_PREPARED_DIR="${IYAGI_PREPARED_DIR:-$(python3 "$REPO_ROOT/scripts/prepare_iyagi_source.py")}"
IYAGI_SYNC_CONFIG_ON_START="${IYAGI_SYNC_CONFIG_ON_START:-0}"
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
BRIDGE_CONNECT_TIMEOUT_SEC="${BRIDGE_CONNECT_TIMEOUT_SEC:-5}"
BRIDGE_CTRL_C_HANGUP="${BRIDGE_CTRL_C_HANGUP:-1}"
BRIDGE_BUSY_REPEAT="${BRIDGE_BUSY_REPEAT:-5}"
BRIDGE_BUSY_GAP_MS="${BRIDGE_BUSY_GAP_MS:-0}"
BRIDGE_DTMF_GAP_MS="${BRIDGE_DTMF_GAP_MS:-320}"
BRIDGE_POST_DTMF_DELAY_MS="${BRIDGE_POST_DTMF_DELAY_MS:-500}"
BRIDGE_DEBUG="${BRIDGE_DEBUG:-0}"
BRIDGE_DEBUG_RENDER_SERVER="${BRIDGE_DEBUG_RENDER_SERVER:-0}"
BRIDGE_SSH_ANNOUNCE_IYAGI="${BRIDGE_SSH_ANNOUNCE_IYAGI:-1}"
if [ "$_iyagi_bridge_debug_from_caller" = 0 ]; then
    BRIDGE_DEBUG=1
fi
DOSBOX_VIDEO_BACKEND="${DOSBOX_VIDEO_BACKEND:-auto}"
DOSBOX_WAYLAND_STRICT="${DOSBOX_WAYLAND_STRICT:-0}"
DOSBOX_SCANLINES="${DOSBOX_SCANLINES:-1}"
DOSBOX_GLSHADER="${DOSBOX_GLSHADER:-crt/vga-1080p-fake-double-scan}"
DOSBOX_SCANLINE_WINDOWRES="${DOSBOX_SCANLINE_WINDOWRES:-1280x960}"
DOSBOX_CPU_CORE="${DOSBOX_CPU_CORE:-simple}"
DOSBOX_CPU_CPUTYPE="${DOSBOX_CPU_CPUTYPE:-386}"
DOSBOX_CPU_CYCLES="${DOSBOX_CPU_CYCLES:-2000}"
DOSBOX_FRAMESKIP="${DOSBOX_FRAMESKIP:-1}"
if [[ ! "$DOSBOX_FRAMESKIP" =~ ^[0-9]+$ ]] || [ "$DOSBOX_FRAMESKIP" -lt 0 ] || [ "$DOSBOX_FRAMESKIP" -gt 10 ]; then
    DOSBOX_FRAMESKIP=1
fi
if [[ "$DOSBOX_CPU_CYCLES" =~ ^[0-9]+$ ]]; then
    # DOSBox-Staging cpu_cycles expects a raw numeric value (not "fixed N").
    DOSBOX_CPU_CYCLES_SET="$DOSBOX_CPU_CYCLES"
else
    DOSBOX_CPU_CYCLES_SET="$DOSBOX_CPU_CYCLES"
fi

if [ "${BRIDGE_PORT:-}" = "auto" ] || [ -z "${BRIDGE_PORT:-}" ]; then
    BRIDGE_PORT="$(pick_unused_tcp_port)"
    echo "Selected bridge port automatically: $BRIDGE_PORT"
elif ! is_port_available "$BRIDGE_PORT"; then
    old_port="$BRIDGE_PORT"
    BRIDGE_PORT="$(pick_unused_tcp_port)"
    echo "Configured BRIDGE_PORT=$old_port is in use; switched to free port: $BRIDGE_PORT"
fi

echo "Loaded environment values:"
echo "  ENV_FILE=$ENV_FILE"
echo "  USER_DATA_ROOT=$USER_DATA_ROOT"
echo "  IYAGI_USER=$IYAGI_USER"
echo "  IYAGI_PREPARED_DIR=$IYAGI_PREPARED_DIR"
echo "  IYAGI_SYNC_CONFIG_ON_START=$IYAGI_SYNC_CONFIG_ON_START"
echo "  IYAGI_SSH_PORT=$IYAGI_SSH_PORT"
echo "  SSH_AUTH_MODE=$SSH_AUTH_MODE"
echo "  BRIDGE_PORT=$BRIDGE_PORT"
echo "  BRIDGE_CLIENT_ENCODING=$BRIDGE_CLIENT_ENCODING"
echo "  BRIDGE_SERVER_ENCODING=$BRIDGE_SERVER_ENCODING"
echo "  BRIDGE_SERVER_REPAIR_MOJIBAKE=$BRIDGE_SERVER_REPAIR_MOJIBAKE"
echo "  BRIDGE_ANSI_RESET_HACK=$BRIDGE_ANSI_RESET_HACK"
echo "  BRIDGE_ANSI_COLOR_COMPAT_HACK=$BRIDGE_ANSI_COLOR_COMPAT_HACK"
echo "  BRIDGE_ANSI_DEFAULT_FG=$BRIDGE_ANSI_DEFAULT_FG"
echo "  BRIDGE_ANSI_DEFAULT_BG=$BRIDGE_ANSI_DEFAULT_BG"
echo "  BRIDGE_ANSI_DEFAULT_MODE=$BRIDGE_ANSI_DEFAULT_MODE"
echo "  BRIDGE_CONNECT_TIMEOUT_SEC=$BRIDGE_CONNECT_TIMEOUT_SEC"
echo "  BRIDGE_CTRL_C_HANGUP=$BRIDGE_CTRL_C_HANGUP"
echo "  BRIDGE_BUSY_REPEAT=$BRIDGE_BUSY_REPEAT"
echo "  BRIDGE_BUSY_GAP_MS=$BRIDGE_BUSY_GAP_MS"
echo "  BRIDGE_DTMF_GAP_MS=$BRIDGE_DTMF_GAP_MS"
echo "  BRIDGE_POST_DTMF_DELAY_MS=$BRIDGE_POST_DTMF_DELAY_MS"
echo "  BRIDGE_DEBUG=$BRIDGE_DEBUG"
echo "  BRIDGE_DEBUG_RENDER_SERVER=$BRIDGE_DEBUG_RENDER_SERVER"
echo "  BRIDGE_SSH_ANNOUNCE_IYAGI=$BRIDGE_SSH_ANNOUNCE_IYAGI"
echo "  DOSBOX_VIDEO_BACKEND=$DOSBOX_VIDEO_BACKEND"
echo "  DOSBOX_WAYLAND_STRICT=$DOSBOX_WAYLAND_STRICT"
echo "  DOSBOX_SCANLINES=$DOSBOX_SCANLINES"
echo "  DOSBOX_GLSHADER=$DOSBOX_GLSHADER"
echo "  DOSBOX_SCANLINE_WINDOWRES=$DOSBOX_SCANLINE_WINDOWRES"
echo "  DOSBOX_CPU_CORE=$DOSBOX_CPU_CORE"
echo "  DOSBOX_CPU_CPUTYPE=$DOSBOX_CPU_CPUTYPE"
echo "  DOSBOX_CPU_CYCLES=$DOSBOX_CPU_CYCLES"
echo "  DOSBOX_CPU_CYCLES_SET=$DOSBOX_CPU_CYCLES_SET"
echo "  DOSBOX_FRAMESKIP=$DOSBOX_FRAMESKIP"

# Flat app/ layout matches AppImage launch.sh (C:\ = user app/, I.CNF at C:\I.CNF).
if [ ! -f "$APP_DIR/I.EXE" ]; then
    mkdir -p "$APP_DIR"
    if [ -f "$APP_DIR/IYAGI/I.EXE" ]; then
        echo "Migrating legacy app/IYAGI/* into flat app/ (cross-launcher parity)..."
        cp -a "$APP_DIR/IYAGI/." "$APP_DIR/"
    else
        cp -a "$IYAGI_PREPARED_DIR/." "$APP_DIR/"
    fi
fi
if [[ "${IYAGI_SYNC_CONFIG_ON_START,,}" =~ ^(1|true|yes|on)$ ]]; then
    # Optional refresh from canonical defaults for reproducibility.
    sync_iyagi_runtime_config "$IYAGI_PREPARED_DIR" "$APP_DIR"
fi

ensure_portable_dosbox

if bridge_needs_rebuild; then
    echo "Building bridge..."
    (cd "$REPO_ROOT/bridge" && go run ./cmd/embed-sounds && go build -o "$BRIDGE_BIN")
fi

mkdir -p "$KEYS_DIR"
if [ "$SSH_AUTH_MODE" = "key" ] && [ ! -f "$KEY_FILE" ]; then
    ssh-keygen -t rsa -b 4096 -N "" -f "$KEY_FILE" >/dev/null
    chmod 600 "$KEY_FILE"
fi

RUNTIME_CONF="$RUN_DIR/dosbox.runtime.conf"
cp "$REPO_ROOT/resources/common/dosbox.conf" "$RUNTIME_CONF"
ln -sfn "$APP_DIR" "$RUN_DIR/app"
ln -sfn "$DOWNLOADS_DIR" "$RUN_DIR/downloads"

python3 - "$RUNTIME_CONF" "$BRIDGE_PORT" "$DOSBOX_CPU_CORE" "$DOSBOX_CPU_CPUTYPE" "$DOSBOX_CPU_CYCLES_SET" "$DOSBOX_FRAMESKIP" <<'PY'
import re
import sys
from pathlib import Path

cfg = Path(sys.argv[1])
bridge_port = sys.argv[2]
core = sys.argv[3]
cputype = sys.argv[4]
cycles_set = sys.argv[5]
frameskip = sys.argv[6]
text = cfg.read_text(encoding="utf-8", errors="ignore")

cycles_conf = f"fixed {cycles_set}" if cycles_set.isdigit() else cycles_set

patterns = [
    (r'(?im)^serial4\s*=.*$', f'serial4=nullmodem server:127.0.0.1 port:{bridge_port} transparent:1'),
    (r'(?im)^serial1\s*=.*$', 'serial1=disabled'),
    (r'(?im)^output\s*=.*$', 'output=texture'),
    (r'(?im)^texture_renderer\s*=.*$', 'texture_renderer=auto'),
    (r'(?im)^mididevice\s*=.*$', 'mididevice=none'),
    (r'(?im)^mouse_capture\s*=.*$', 'mouse_capture=nomouse'),
    (r'(?im)^mouse_middle_release\s*=.*$', 'mouse_middle_release=false'),
    (r'(?im)^dos_mouse_driver\s*=.*$', 'dos_mouse_driver=false'),
]
for pat, repl in patterns:
    if re.search(pat, text):
        text = re.sub(pat, repl, text)
    else:
        text += "\n" + repl + "\n"

# cycles= before cpu_cycles= — avoid appending orphan cpu_cycles at EOF then duplicating.
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

cfg.write_text(text, encoding="utf-8")
PY

SSH_ARGS_COMMON="-o BatchMode=no -o PreferredAuthentications=keyboard-interactive,password,publickey -o PubkeyAuthentication=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
if [ "$SSH_AUTH_MODE" = "key" ]; then
    SSH_TEMPLATE="ssh $SSH_ARGS_COMMON -i \"$KEY_FILE\" -p {port} {userhost}"
else
    SSH_TEMPLATE="ssh $SSH_ARGS_COMMON -p {port} {userhost}"
fi

echo "Starting bridge on 127.0.0.1:$BRIDGE_PORT..."
echo "Bridge env: client=$BRIDGE_CLIENT_ENCODING server=$BRIDGE_SERVER_ENCODING timeout=${BRIDGE_CONNECT_TIMEOUT_SEC}s busy=$BRIDGE_BUSY_REPEAT busy_gap_ms=$BRIDGE_BUSY_GAP_MS dtmf_gap_ms=$BRIDGE_DTMF_GAP_MS post_dtmf_delay_ms=$BRIDGE_POST_DTMF_DELAY_MS ctrl_c_hangup=$BRIDGE_CTRL_C_HANGUP repair_mojibake=$BRIDGE_SERVER_REPAIR_MOJIBAKE debug=$BRIDGE_DEBUG"

# IYAGI_DEBUG_LOG: optional file redirect for bridge stdout/stderr (uncomment to use)
# IYAGI_DEBUG_LOG="${IYAGI_DEBUG_LOG:-0}"
# IYAGI_DEBUG_LOG_FILE="${IYAGI_DEBUG_LOG_FILE:-}"
# BRIDGE_LOG_PATH=""
# if [[ "${IYAGI_DEBUG_LOG,,}" =~ ^(1|true|yes|on)$ ]] || [ -n "${IYAGI_DEBUG_LOG_FILE:-}" ]; then
#     LOG_DIR="$USER_DATA_ROOT/logs"
#     mkdir -p "$LOG_DIR"
#     if [ -n "${IYAGI_DEBUG_LOG_FILE:-}" ]; then
#         BRIDGE_LOG_PATH="$IYAGI_DEBUG_LOG_FILE"
#     else
#         BRIDGE_LOG_PATH="$LOG_DIR/bridge-$(date +%Y%m%d-%H%M%S).log"
#     fi
#     mkdir -p "$(dirname "$BRIDGE_LOG_PATH")"
#     case "$BRIDGE_LOG_PATH" in
#     /*) ;;
#     *) BRIDGE_LOG_PATH="$(cd "$(dirname "$BRIDGE_LOG_PATH")" && pwd)/$(basename "$BRIDGE_LOG_PATH")" ;;
#     esac
#     echo "" >&2
#     echo "========== IYAGI bridge: logs are written to a FILE (nothing below is from the bridge) ==========" >&2
#     echo "  $BRIDGE_LOG_PATH" >&2
#     echo "  Live: tail -f $(printf %q "$BRIDGE_LOG_PATH")" >&2
#     echo "============================================================================================" >&2
#     echo "" >&2
# fi
BRIDGE_LOG_PATH=""

bridge_cmd=(
    env
    BRIDGE_PORT="$BRIDGE_PORT"
    IYAGI_USER="$IYAGI_USER"
    IYAGI_SSH_PORT="$IYAGI_SSH_PORT"
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
    BRIDGE_CONNECT_TIMEOUT_SEC="$BRIDGE_CONNECT_TIMEOUT_SEC"
    BRIDGE_BUSY_REPEAT="$BRIDGE_BUSY_REPEAT"
    BRIDGE_BUSY_GAP_MS="$BRIDGE_BUSY_GAP_MS"
    BRIDGE_DTMF_GAP_MS="$BRIDGE_DTMF_GAP_MS"
    BRIDGE_POST_DTMF_DELAY_MS="$BRIDGE_POST_DTMF_DELAY_MS"
    BRIDGE_CTRL_C_HANGUP="$BRIDGE_CTRL_C_HANGUP"
    BRIDGE_DEBUG="$BRIDGE_DEBUG"
    BRIDGE_DEBUG_RENDER_SERVER="$BRIDGE_DEBUG_RENDER_SERVER"
    BRIDGE_SSH_ANNOUNCE_IYAGI="$BRIDGE_SSH_ANNOUNCE_IYAGI"
    "$BRIDGE_BIN"
)
# if [ -n "$BRIDGE_LOG_PATH" ]; then
#     "${bridge_cmd[@]}" >>"$BRIDGE_LOG_PATH" 2>&1 &
# else
    "${bridge_cmd[@]}" &
# fi
BRIDGE_PID=$!
sleep 0.2

if ! kill -0 "$BRIDGE_PID" 2>/dev/null; then
    echo "ERROR: bridge failed to start"
    exit 1
fi

selected_backend=""
if [ "$DOSBOX_VIDEO_BACKEND" = "auto" ]; then
    if [ "${XDG_SESSION_TYPE:-}" = "wayland" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
        if [ "$DOSBOX_WAYLAND_STRICT" = "1" ]; then
            selected_backend="wayland"
        elif [ -n "${DISPLAY:-}" ]; then
            # On many portable builds, Wayland lacks libdecor integration,
            # which causes a borderless/no-titlebar window. Prefer x11 when available.
            selected_backend="x11"
        else
            selected_backend="wayland"
        fi
    elif [ -n "${DISPLAY:-}" ]; then
        selected_backend="x11"
    fi
elif [ "$DOSBOX_VIDEO_BACKEND" = "wayland" ] || [ "$DOSBOX_VIDEO_BACKEND" = "x11" ]; then
    selected_backend="$DOSBOX_VIDEO_BACKEND"
else
    echo "ERROR: DOSBOX_VIDEO_BACKEND must be auto|wayland|x11"
    exit 1
fi

DOSBOX_VER="$("$DOSBOX_BIN" --version 2>/dev/null || true)"
DOSBOX_VER="${DOSBOX_VER%%$'\n'*}"
echo "Launching DOSBox-Staging ${DOSBOX_VER}..."
echo "DOSBox binary: $DOSBOX_BIN"
echo "Preferred SDL_VIDEODRIVER=${selected_backend:-auto-default}"
if [ "$DOSBOX_VIDEO_BACKEND" = "auto" ] && [ "${XDG_SESSION_TYPE:-}" = "wayland" -o -n "${WAYLAND_DISPLAY:-}" ]; then
    echo "Wayland session detected (strict=${DOSBOX_WAYLAND_STRICT})"
fi

run_dosbox_with_backend() {
    local backend="$1"
    local -a env_vars=(
        "SDL_RENDER_DRIVER=software"
        "SDL_FRAMEBUFFER_ACCELERATION=software"
        "LIBGL_ALWAYS_SOFTWARE=1"
    )
    if [ "$backend" = "wayland" ]; then
        env_vars+=(
            "SDL_VIDEODRIVER=wayland"
            "SDL_VIDEO_WAYLAND_ALLOW_LIBDECOR=1"
            "SDL_VIDEO_WAYLAND_PREFER_LIBDECOR=1"
        )
    elif [ "$backend" = "x11" ]; then
        env_vars+=(
            "SDL_VIDEODRIVER=x11"
            "SDL_VIDEO_X11_FORCE_EGL=1"
        )
    fi

    local output_mode="texture"
    local glshader_mode="none"
    local integer_scaling_mode="auto"
    local windowresolution_mode="1024x768"
    if [[ "${DOSBOX_SCANLINES,,}" =~ ^(1|true|yes|on)$ ]]; then
        output_mode="opengl"
        glshader_mode="$DOSBOX_GLSHADER"
        integer_scaling_mode="vertical"
        windowresolution_mode="$DOSBOX_SCANLINE_WINDOWRES"
    fi

    echo "Launching backend: ${backend:-default} (output=${output_mode}, glshader=${glshader_mode}, window=${windowresolution_mode})"
    (cd "$RUN_DIR" && env "${env_vars[@]}" "$DOSBOX_BIN" \
        --noprimaryconf \
        --nolocalconf \
        -conf "$RUNTIME_CONF" \
        -set "core=${DOSBOX_CPU_CORE}" \
        -set "cputype=${DOSBOX_CPU_CPUTYPE}" \
        -set "cpu_cycles=${DOSBOX_CPU_CYCLES_SET}" \
        -set "startup_verbosity=quiet" \
        -set "windowresolution=${windowresolution_mode}" \
        -set "output=${output_mode}" \
        -set "glshader=${glshader_mode}" \
        -set "integer_scaling=${integer_scaling_mode}" \
        -set "ne2000=false" \
        -set "texture_renderer=auto" \
        -set "mouse_capture=nomouse" \
        -set "mouse_middle_release=false" \
        -set "dos_mouse_driver=false" \
    )
}

fallback_backend=""
if [ "$DOSBOX_VIDEO_BACKEND" = "auto" ]; then
    if [ "$selected_backend" = "x11" ] && [ -n "${WAYLAND_DISPLAY:-}" ]; then
        fallback_backend="wayland"
    elif [ "$selected_backend" = "wayland" ] && [ -n "${DISPLAY:-}" ]; then
        fallback_backend="x11"
    fi
fi

set +e
run_dosbox_with_backend "$selected_backend"
DOSBOX_RC=$?
if [ "$DOSBOX_RC" -ne 0 ] && [ "$DOSBOX_RC" -ne 130 ] && [ "$DOSBOX_RC" -ne 143 ] && [ -n "$fallback_backend" ]; then
    echo "Primary backend failed (exit $DOSBOX_RC); trying fallback: $fallback_backend"
    run_dosbox_with_backend "$fallback_backend"
    DOSBOX_RC=$?
fi
set -e

if [ "$DOSBOX_RC" -ne 0 ]; then
    echo "WARNING: DOSBox exited with code $DOSBOX_RC"
fi
exit "$DOSBOX_RC"
