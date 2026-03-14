#!/bin/bash
# launch.sh — Linux launcher / AppRun entry point for the IYAGI AppImage.
#
# When run as an AppRun script inside an AppImage, the AppImage runtime sets:
#   $APPIMAGE  — absolute path to the .AppImage file
#   $APPDIR    — absolute path to the squashfs mount (read-only)
#   $OWD       — original working directory
#
# User-writable data defaults to standard XDG user dirs when running as AppImage:
#   config: ${XDG_CONFIG_HOME:-~/.config}/iyagi-terminal
#   data:   ${XDG_DATA_HOME:-~/.local/share}/iyagi-terminal
# You can override both with USER_DATA_ROOT for portable/testing setups.
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

# User-writable data location:
# - If USER_DATA_ROOT is provided, use it directly (portable/testing).
# - AppImage default: XDG config/data directories.
# - Dev script fallback: repository-local iyagi-data.
if [ -n "${USER_DATA_ROOT:-}" ]; then
    USER_DATA_ROOT="$(readlink -f "$USER_DATA_ROOT")"
    CONFIG_ROOT="$USER_DATA_ROOT"
    DATA_ROOT="$USER_DATA_ROOT"
elif [ -n "${APPIMAGE:-}" ]; then
    CONFIG_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/iyagi-terminal"
    DATA_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/iyagi-terminal"
    USER_DATA_ROOT="$CONFIG_ROOT"
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

ensure_runtime_app_copy() {
    if [ -f "$RUNTIME_APP_DIR/I.EXE" ]; then
        return
    fi
    echo "Seeding writable app files to: $RUNTIME_APP_DIR"
    rm -rf "$RUNTIME_APP_DIR"
    mkdir -p "$RUNTIME_APP_DIR"
    cp -a "$BUNDLED_APP_DIR/." "$RUNTIME_APP_DIR/"
}


# ─── Load user config ────────────────────────────────────────────────────────

ENV_FILE="$USER_DATA_ROOT/.env"
if [ ! -f "$ENV_FILE" ]; then
    cp "$APPDIR/.env.example" "$ENV_FILE"
    echo ""
    echo "=== First run: created config file at $ENV_FILE"
    echo "    Edit it to set IYAGI_HOST and IYAGI_USER, then re-run."
    echo ""
    read -rp "Press ENTER to open it now (or Ctrl+C to exit and edit manually)..."
    "${EDITOR:-nano}" "$ENV_FILE"
fi

# shellcheck source=/dev/null
source "$ENV_FILE"

IYAGI_HOST="${IYAGI_HOST:-your-server.com}"
IYAGI_USER="${IYAGI_USER:-user}"
IYAGI_SSH_PORT="${IYAGI_SSH_PORT:-22}"
BRIDGE_PORT="${BRIDGE_PORT:-2323}"
SSH_AUTH_MODE="${SSH_AUTH_MODE:-bbs}"
BRIDGE_CLIENT_ENCODING="${BRIDGE_CLIENT_ENCODING:-euc-kr}"
BRIDGE_SERVER_ENCODING="${BRIDGE_SERVER_ENCODING:-euc-kr}"
BRIDGE_SERVER_REPAIR_MOJIBAKE="${BRIDGE_SERVER_REPAIR_MOJIBAKE:-1}"
BRIDGE_DEBUG="${BRIDGE_DEBUG:-0}"
BRIDGE_CTRL_C_HANGUP="${BRIDGE_CTRL_C_HANGUP:-1}"
BRIDGE_CONNECT_TIMEOUT_SEC="${BRIDGE_CONNECT_TIMEOUT_SEC:-5}"
BRIDGE_BUSY_REPEAT="${BRIDGE_BUSY_REPEAT:-5}"
BRIDGE_BUSY_GAP_MS="${BRIDGE_BUSY_GAP_MS:-0}"
BRIDGE_DTMF_GAP_MS="${BRIDGE_DTMF_GAP_MS:-320}"
BRIDGE_POST_DTMF_DELAY_MS="${BRIDGE_POST_DTMF_DELAY_MS:-500}"
DOSBOX_VIDEO_BACKEND="${DOSBOX_VIDEO_BACKEND:-auto}"
DOSBOX_WAYLAND_STRICT="${DOSBOX_WAYLAND_STRICT:-0}"
DOSBOX_SOURCE="${DOSBOX_SOURCE:-auto}"
DOSBOX_BIN="${DOSBOX_BIN:-}"
DOSBOX_X_WINDOWRES="${DOSBOX_X_WINDOWRES:-1024x768}"
DOSBOX_X_SCALER="${DOSBOX_X_SCALER:-hq2x forced}"
DOSBOX_X_SCANLINES="${DOSBOX_X_SCANLINES:-0}"
DOSBOX_X_SCANLINE_SCALER="${DOSBOX_X_SCANLINE_SCALER:-scan2x forced}"
DOSBOX_X_SCANLINE_OUTPUT="${DOSBOX_X_SCANLINE_OUTPUT:-openglnb}"
DOSBOX_SCANLINES="${DOSBOX_SCANLINES:-0}"
DOSBOX_GLSHADER="${DOSBOX_GLSHADER:-crt/vga-1080p-fake-double-scan}"
DOSBOX_CPU_CORE="${DOSBOX_CPU_CORE:-simple}"
DOSBOX_CPU_CPUTYPE="${DOSBOX_CPU_CPUTYPE:-386}"
DOSBOX_CPU_CYCLES="${DOSBOX_CPU_CYCLES:-2000}"

if [ "${BRIDGE_PORT:-}" = "auto" ] || [ -z "${BRIDGE_PORT:-}" ]; then
    BRIDGE_PORT="$(pick_unused_tcp_port)"
    echo "Selected bridge port automatically: $BRIDGE_PORT"
elif ! is_port_available "$BRIDGE_PORT"; then
    old_port="$BRIDGE_PORT"
    BRIDGE_PORT="$(pick_unused_tcp_port)"
    echo "Configured BRIDGE_PORT=$old_port is in use; switched to free port: $BRIDGE_PORT"
fi

if [[ "$DOSBOX_CPU_CYCLES" =~ ^[0-9]+$ ]]; then
    DOSBOX_CPU_CYCLES_SET="fixed ${DOSBOX_CPU_CYCLES}"
else
    DOSBOX_CPU_CYCLES_SET="$DOSBOX_CPU_CYCLES"
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
if [[ "${DOSBOX_SCANLINES,,}" =~ ^(1|true|yes|on)$ ]]; then
    DOSBOX_STAGING_OUTPUT="opengl"
    DOSBOX_STAGING_GLSHADER="$DOSBOX_GLSHADER"
    DOSBOX_STAGING_INTEGER_SCALING="vertical"
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
            echo ">>> Add the public key below to ~/.ssh/authorized_keys on $IYAGI_HOST:"
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

if [ "$SSH_AUTH_MODE" = "key" ]; then
    SSH_TEMPLATE="ssh -t -t -o StrictHostKeyChecking=no -i ${KEY_FILE} -p {port} {userhost}"
else
    SSH_TEMPLATE="ssh -t -t -o StrictHostKeyChecking=no -o PubkeyAuthentication=no -o PreferredAuthentications=none,password,keyboard-interactive -p {port} {userhost}"
fi
echo "Bridge listen (IYAGI dial target): 127.0.0.1:${BRIDGE_PORT}"
echo "Bridge debug logging: ${BRIDGE_DEBUG}"
echo "Bridge Ctrl+C hangup: ${BRIDGE_CTRL_C_HANGUP}"
echo "Bridge connect timeout: ${BRIDGE_CONNECT_TIMEOUT_SEC}s"
echo "Bridge busy repeat: ${BRIDGE_BUSY_REPEAT}"
echo "Bridge busy gap: ${BRIDGE_BUSY_GAP_MS}ms"
echo "Bridge DTMF gap: ${BRIDGE_DTMF_GAP_MS}ms"
echo "Bridge post-DTMF delay: ${BRIDGE_POST_DTMF_DELAY_MS}ms"
echo "Bridge ATDT target mode: enabled (example: ATDT${IYAGI_HOST}:${IYAGI_SSH_PORT})"

BRIDGE_PORT="$BRIDGE_PORT" \
BRIDGE_CMD="" \
BRIDGE_CMD_TEMPLATE="$SSH_TEMPLATE" \
BRIDGE_SSH_USER="$IYAGI_USER" \
BRIDGE_CLIENT_ENCODING="$BRIDGE_CLIENT_ENCODING" \
BRIDGE_SERVER_ENCODING="$BRIDGE_SERVER_ENCODING" \
BRIDGE_SERVER_REPAIR_MOJIBAKE="$BRIDGE_SERVER_REPAIR_MOJIBAKE" \
BRIDGE_DEBUG="$BRIDGE_DEBUG" \
BRIDGE_CTRL_C_HANGUP="$BRIDGE_CTRL_C_HANGUP" \
BRIDGE_CONNECT_TIMEOUT_SEC="$BRIDGE_CONNECT_TIMEOUT_SEC" \
BRIDGE_BUSY_REPEAT="$BRIDGE_BUSY_REPEAT" \
BRIDGE_BUSY_GAP_MS="$BRIDGE_BUSY_GAP_MS" \
BRIDGE_DTMF_GAP_MS="$BRIDGE_DTMF_GAP_MS" \
BRIDGE_POST_DTMF_DELAY_MS="$BRIDGE_POST_DTMF_DELAY_MS" \
"$BRIDGE" &

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
# Symlink writable app files into the staging area.
ln -sfn "$RUNTIME_APP_DIR" "$STAGING/app"
ln -sfn "$DOWNLOADS_DIR" "$STAGING/downloads"
# Always refresh dosbox.conf from the packaged version so updates take effect.
# (Users should customize via .env, not by editing staging/dosbox.conf.)
cp "$DOSBOX_CONF" "$STAGING/dosbox.conf"

# Route COM4 traffic to the local bridge (AT commands are parsed by bridge).
python3 - "$STAGING/dosbox.conf" "$BRIDGE_PORT" <<'PYEOF'
import pathlib
import re
import sys

conf_path = pathlib.Path(sys.argv[1])
bridge_port = sys.argv[2]
text = conf_path.read_text(encoding="utf-8", errors="ignore")
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

conf_path.write_text(text, encoding="utf-8")
PYEOF

set +e
run_dosbox_with_env() {
    local label="$1"
    local profile="$2"
    shift 2
    local -a extra_args=()
    local -a forced_env=(
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
        (cd "$STAGING" && env "${forced_env[@]}" "$@" "$DOSBOX" -conf dosbox.conf -set "core=${DOSBOX_CPU_CORE}" -set "cputype=${DOSBOX_CPU_CPUTYPE}" -set "cycles=${DOSBOX_CPU_CYCLES_SET}" -set "mouse_capture=nomouse" -set "mouse_middle_release=false" -set "dos_mouse_driver=false" "${extra_args[@]}")
    else
        (cd "$STAGING" && env "${forced_env[@]}" "$@" "$DOSBOX" -conf dosbox.conf -set "core=${DOSBOX_CPU_CORE}" -set "cputype=${DOSBOX_CPU_CPUTYPE}" -set "cpu_cycles=${DOSBOX_CPU_CYCLES_SET}" -set "startup_verbosity=quiet" -set "output=${DOSBOX_STAGING_OUTPUT}" -set "glshader=${DOSBOX_STAGING_GLSHADER}" -set "integer_scaling=${DOSBOX_STAGING_INTEGER_SCALING}" -set "ne2000=false" -set "texture_renderer=auto" -set "mouse_capture=nomouse" -set "mouse_middle_release=false" -set "dos_mouse_driver=false" "${extra_args[@]}")
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
        (cd "$STAGING" && SDL_FRAMEBUFFER_ACCELERATION=software LIBGL_ALWAYS_SOFTWARE=1 "$DOSBOX" -conf dosbox.conf -set "core=${DOSBOX_CPU_CORE}" -set "cputype=${DOSBOX_CPU_CPUTYPE}" -set "cycles=${DOSBOX_CPU_CYCLES_SET}" -set "mouse_capture=nomouse" -set "mouse_middle_release=false" -set "dos_mouse_driver=false" "${extra_args[@]}")
    else
        (cd "$STAGING" && SDL_FRAMEBUFFER_ACCELERATION=software LIBGL_ALWAYS_SOFTWARE=1 "$DOSBOX" -conf dosbox.conf -set "core=${DOSBOX_CPU_CORE}" -set "cputype=${DOSBOX_CPU_CPUTYPE}" -set "cpu_cycles=${DOSBOX_CPU_CYCLES_SET}" -set "startup_verbosity=quiet" -set "output=${DOSBOX_STAGING_OUTPUT}" -set "glshader=${DOSBOX_STAGING_GLSHADER}" -set "integer_scaling=${DOSBOX_STAGING_INTEGER_SCALING}" -set "ne2000=false" -set "texture_renderer=auto" -set "mouse_capture=nomouse" -set "mouse_middle_release=false" -set "dos_mouse_driver=false" "${extra_args[@]}")
    fi
}

DOSBOX_RC=1

# For DOSBox-X, prefer a plain launch (no forced SDL backend env vars) so
# behavior matches run-direct.sh and avoids backend-specific window quirks.
if [ "$IS_DOSBOX_X" -eq 1 ]; then
    run_dosbox_plain "dosbox-x direct" "primary"
    DOSBOX_RC=$?
    if [ "$DOSBOX_RC" -ne 0 ]; then
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
    if [ "$DOSBOX_RC" -ne 0 ] && [ "$IS_DOSBOX_X" -eq 1 ]; then
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
    if [ "$DOSBOX_RC" -ne 0 ] && [ "$IS_DOSBOX_X" -eq 1 ]; then
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
            if [ "$DOSBOX_RC" -ne 0 ] && [ "$IS_DOSBOX_X" -eq 1 ]; then
                echo "Wayland primary profile failed; trying DOSBox-X fallback profile..."
                run_dosbox_with_env "wayland (auto strict fallback profile)" "fallback" \
                    SDL_VIDEODRIVER=wayland \
                    SDL_RENDER_DRIVER=software \
                    SDL_VIDEO_WAYLAND_ALLOW_LIBDECOR=1 \
                    SDL_VIDEO_WAYLAND_PREFER_LIBDECOR=1 \
                    LIBGL_ALWAYS_SOFTWARE=1
                DOSBOX_RC=$?
            fi
            if [ "$DOSBOX_RC" -ne 0 ] && [ -n "${DISPLAY:-}" ]; then
                echo "Wayland backend failed; trying x11 fallback..."
                run_dosbox_with_env "x11 (fallback)" "primary" \
                    SDL_VIDEODRIVER=x11 \
                    SDL_RENDER_DRIVER=software \
                    LIBGL_ALWAYS_SOFTWARE=1
                DOSBOX_RC=$?
                if [ "$DOSBOX_RC" -ne 0 ] && [ "$IS_DOSBOX_X" -eq 1 ]; then
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
            if [ "$DOSBOX_RC" -ne 0 ]; then
                echo "x11 preferred backend failed; trying wayland fallback..."
                run_dosbox_with_env "wayland (auto fallback)" "primary" \
                    SDL_VIDEODRIVER=wayland \
                    SDL_RENDER_DRIVER=software \
                    SDL_VIDEO_WAYLAND_ALLOW_LIBDECOR=1 \
                    SDL_VIDEO_WAYLAND_PREFER_LIBDECOR=1 \
                    LIBGL_ALWAYS_SOFTWARE=1
                DOSBOX_RC=$?
            fi
            if [ "$DOSBOX_RC" -ne 0 ] && [ "$IS_DOSBOX_X" -eq 1 ]; then
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
        if [ "$DOSBOX_RC" -ne 0 ] && [ "$IS_DOSBOX_X" -eq 1 ]; then
            echo "X11 primary profile failed; trying DOSBox-X fallback profile..."
            run_dosbox_with_env "x11 (auto fallback profile)" "fallback" \
                SDL_VIDEODRIVER=x11 \
                SDL_RENDER_DRIVER=software \
                LIBGL_ALWAYS_SOFTWARE=1
            DOSBOX_RC=$?
        fi
        if [ "$DOSBOX_RC" -ne 0 ] && [ -n "${WAYLAND_DISPLAY:-}" ]; then
            echo "X11 backend failed; trying wayland fallback..."
            run_dosbox_with_env "wayland (fallback)" "primary" \
                SDL_VIDEODRIVER=wayland \
                SDL_RENDER_DRIVER=software \
                SDL_VIDEO_WAYLAND_ALLOW_LIBDECOR=1 \
                SDL_VIDEO_WAYLAND_PREFER_LIBDECOR=1 \
                LIBGL_ALWAYS_SOFTWARE=1
            DOSBOX_RC=$?
            if [ "$DOSBOX_RC" -ne 0 ] && [ "$IS_DOSBOX_X" -eq 1 ]; then
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
        if [ "$DOSBOX_RC" -ne 0 ] && [ "$IS_DOSBOX_X" -eq 1 ]; then
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
