#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOSBOX_X_BIN_DEFAULT="$REPO_ROOT/third_party/dosbox-x/unpacked/usr/bin/dosbox-x"
DOSBOX_RUNTIME="${DOSBOX_RUNTIME:-portable}"
DOSBOX_PORTABLE_VERSION="${DOSBOX_PORTABLE_VERSION:-0.82.2}"
DOSBOX_PORTABLE_URL="${DOSBOX_PORTABLE_URL:-https://github.com/dosbox-staging/dosbox-staging/releases/download/v${DOSBOX_PORTABLE_VERSION}/dosbox-staging-linux-x86_64-v${DOSBOX_PORTABLE_VERSION}.tar.xz}"
DOSBOX_PORTABLE_ROOT="${DOSBOX_PORTABLE_ROOT:-$REPO_ROOT/third_party/dosbox-staging}"
DOSBOX_PORTABLE_BIN="${DOSBOX_PORTABLE_BIN:-$DOSBOX_PORTABLE_ROOT/unpacked/usr/bin/dosbox}"
DOSBOX_PORTABLE_STRICT="${DOSBOX_PORTABLE_STRICT:-0}"
DOSBOX_BIN="${DOSBOX_BIN:-}"
DOSBOX_X_WINDOWRES="${DOSBOX_X_WINDOWRES:-1024x768}"
DOSBOX_X_SCALER="${DOSBOX_X_SCALER:-hq2x forced}"
DOSBOX_X_SCANLINES="${DOSBOX_X_SCANLINES:-0}"
DOSBOX_X_SCANLINE_SCALER="${DOSBOX_X_SCANLINE_SCALER:-scan2x forced}"
DOSBOX_X_SCANLINE_OUTPUT="${DOSBOX_X_SCANLINE_OUTPUT:-openglnb}"
DOSBOX_CPU_CORE="${DOSBOX_CPU_CORE:-simple}"
DOSBOX_CPU_CPUTYPE="${DOSBOX_CPU_CPUTYPE:-386}"
DOSBOX_CPU_CYCLES="${DOSBOX_CPU_CYCLES:-2000}"
USER_DATA_ROOT="${USER_DATA_ROOT:-$REPO_ROOT/iyagi-data}"
RUN_DIR="$USER_DATA_ROOT/staging"
APP_DIR="$USER_DATA_ROOT/app/IYAGI"
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

resolve_dosbox_bin() {
    if [ -n "$DOSBOX_BIN" ]; then
        if [ -x "$DOSBOX_BIN" ]; then
            echo "$DOSBOX_BIN"
            return 0
        fi
        echo "ERROR: DOSBOX_BIN is set but not executable: $DOSBOX_BIN" >&2
        return 1
    fi

    case "$DOSBOX_RUNTIME" in
        dosbox-x)
            if [ ! -x "$DOSBOX_X_BIN_DEFAULT" ]; then
                echo "ERROR: DOSBOX_RUNTIME=dosbox-x but binary missing: $DOSBOX_X_BIN_DEFAULT" >&2
                return 1
            fi
            echo "$DOSBOX_X_BIN_DEFAULT"
            return 0
            ;;
        portable)
            if [ -x "$DOSBOX_PORTABLE_ROOT/unpacked/dosbox" ]; then
                DOSBOX_PORTABLE_BIN="$DOSBOX_PORTABLE_ROOT/unpacked/dosbox"
            fi
            if [ ! -x "$DOSBOX_PORTABLE_BIN" ]; then
                echo "Portable DOSBox not found at: $DOSBOX_PORTABLE_BIN" >&2
                echo "Downloading portable DOSBox-Staging ${DOSBOX_PORTABLE_VERSION}..." >&2
                mkdir -p "$DOSBOX_PORTABLE_ROOT/cache" "$DOSBOX_PORTABLE_ROOT/unpacked"
                archive="$DOSBOX_PORTABLE_ROOT/cache/dosbox-staging-linux-x86_64-v${DOSBOX_PORTABLE_VERSION}.tar.xz"
                if [ ! -f "$archive" ]; then
                    if ! wget -q --show-progress "$DOSBOX_PORTABLE_URL" -O "$archive"; then
                        # Older DOSBox-Staging tags used a legacy filename without x86_64.
                        legacy_url="https://github.com/dosbox-staging/dosbox-staging/releases/download/v${DOSBOX_PORTABLE_VERSION}/dosbox-staging-linux-v${DOSBOX_PORTABLE_VERSION}.tar.xz"
                        archive="$DOSBOX_PORTABLE_ROOT/cache/dosbox-staging-linux-v${DOSBOX_PORTABLE_VERSION}.tar.xz"
                        wget -q --show-progress "$legacy_url" -O "$archive"
                    fi
                fi
                rm -rf "$DOSBOX_PORTABLE_ROOT/unpacked"
                mkdir -p "$DOSBOX_PORTABLE_ROOT/unpacked"
                tar xf "$archive" -C "$DOSBOX_PORTABLE_ROOT/unpacked" --strip-components=1
                DOSBOX_PORTABLE_BIN="$(python3 - "$DOSBOX_PORTABLE_ROOT/unpacked" <<'PYEOF'
import pathlib
import sys
root = pathlib.Path(sys.argv[1])
candidates = [p for p in root.rglob("dosbox") if p.is_file()]
if not candidates:
    print("")
    raise SystemExit(1)
candidates.sort(key=lambda p: len(str(p)))
print(candidates[0])
PYEOF
)"
                if [ ! -x "$DOSBOX_PORTABLE_BIN" ]; then
                    echo "ERROR: downloaded portable dosbox binary not found/executable." >&2
                    return 1
                fi
            fi
            echo "$DOSBOX_PORTABLE_BIN"
            return 0
            ;;
        *)
            echo "ERROR: invalid DOSBOX_RUNTIME=$DOSBOX_RUNTIME (expected: dosbox-x or portable)" >&2
            return 1
            ;;
    esac
}

if [ ! -f "$REPO_ROOT/resources/common/.env.example" ]; then
    echo "ERROR: missing .env template at resources/common/.env.example"
    exit 1
fi

mkdir -p "$APP_DIR" "$DOWNLOADS_DIR" "$RUN_DIR" "$(dirname "$BRIDGE_BIN")"

if [ ! -f "$ENV_FILE" ]; then
    cp "$REPO_ROOT/resources/common/.env.example" "$ENV_FILE"
    echo "Created config: $ENV_FILE"
    echo "Set IYAGI_HOST and IYAGI_USER before connecting."
fi

# shellcheck source=/dev/null
source "$ENV_FILE"
IYAGI_PREPARED_DIR="${IYAGI_PREPARED_DIR:-$(python3 "$REPO_ROOT/scripts/prepare_iyagi_source.py")}"
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
DOSBOX_CPU_CORE="${DOSBOX_CPU_CORE:-simple}"
DOSBOX_CPU_CPUTYPE="${DOSBOX_CPU_CPUTYPE:-386}"
DOSBOX_CPU_CYCLES="${DOSBOX_CPU_CYCLES:-2000}"
DOSBOX_RUNTIME="${DOSBOX_RUNTIME:-portable}"
DOSBOX_PORTABLE_VERSION="${DOSBOX_PORTABLE_VERSION:-0.82.2}"
DOSBOX_PORTABLE_URL="${DOSBOX_PORTABLE_URL:-https://github.com/dosbox-staging/dosbox-staging/releases/download/v${DOSBOX_PORTABLE_VERSION}/dosbox-staging-linux-x86_64-v${DOSBOX_PORTABLE_VERSION}.tar.xz}"
DOSBOX_PORTABLE_ROOT="${DOSBOX_PORTABLE_ROOT:-$REPO_ROOT/third_party/dosbox-staging}"
DOSBOX_PORTABLE_BIN="${DOSBOX_PORTABLE_BIN:-$DOSBOX_PORTABLE_ROOT/unpacked/usr/bin/dosbox}"
DOSBOX_PORTABLE_STRICT="${DOSBOX_PORTABLE_STRICT:-0}"

DOSBOX_BIN="$(resolve_dosbox_bin)"
IS_DOSBOX_X=0
if [[ "$(basename "$DOSBOX_BIN")" == *dosbox-x* ]]; then
    IS_DOSBOX_X=1
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

if [[ "$DOSBOX_CPU_CYCLES" =~ ^[0-9]+$ ]]; then
    # DOSBox-X uses classic cycles syntax, DOSBox-Staging cpu_cycles wants raw numeric.
    DOSBOX_CPU_CYCLES_SET_X="fixed ${DOSBOX_CPU_CYCLES}"
    DOSBOX_CPU_CYCLES_SET_STAGING="$DOSBOX_CPU_CYCLES"
else
    DOSBOX_CPU_CYCLES_SET_X="$DOSBOX_CPU_CYCLES"
    DOSBOX_CPU_CYCLES_SET_STAGING="$DOSBOX_CPU_CYCLES"
fi

# Seed app files once from app/ or software/ archive.
if [ ! -f "$APP_DIR/I.EXE" ]; then
    echo "Seeding IYAGI files from $IYAGI_PREPARED_DIR"
    cp -r "$IYAGI_PREPARED_DIR/." "$APP_DIR/"
fi

case "$SSH_AUTH_MODE" in
    bbs)
        echo "SSH auth mode: bbs (no local keypair required)"
        ;;
    key)
        mkdir -p "$KEYS_DIR"
        if [ ! -f "$KEY_FILE" ]; then
            echo "Generating SSH key pair for bridge auth..."
            ssh-keygen -t rsa -b 4096 -f "$KEY_FILE" -N "" -C "iyagi-terminal"
            echo ""
            echo "Add this public key to ~/.ssh/authorized_keys on $IYAGI_HOST:"
            echo ""
            cat "${KEY_FILE}.pub"
            echo ""
            read -rp "Press ENTER after uploading the key..."
        fi
        ;;
    *)
        echo "ERROR: invalid SSH_AUTH_MODE=$SSH_AUTH_MODE (expected: bbs or key)"
        exit 1
        ;;
esac

echo "Building bridge binary..."
(
    cd "$REPO_ROOT/bridge"
    go run ./cmd/embed-sounds
    GOOS=linux GOARCH=amd64 go build -o "$BRIDGE_BIN" .
)
chmod +x "$BRIDGE_BIN"

# Keep runtime config fresh and patch IYAGI settings idempotently.
cp "$REPO_ROOT/resources/common/dosbox.conf" "$RUN_DIR/dosbox.conf"
# Route COM4 traffic to the local bridge (AT commands are parsed by bridge).
python3 - "$RUN_DIR/dosbox.conf" "$BRIDGE_PORT" <<'PYEOF'
import pathlib
import re
import sys

conf_path = pathlib.Path(sys.argv[1])
bridge_port = sys.argv[2]
text = conf_path.read_text(encoding="utf-8", errors="ignore")
serial4_line = f"serial4=nullmodem server:127.0.0.1 port:{bridge_port} transparent:1"
serial1_line = "serial1=disabled"

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

conf_path.write_text(text, encoding="utf-8")
PYEOF

ln -sfn "$APP_DIR" "$RUN_DIR/app"
ln -sfn "$DOWNLOADS_DIR" "$RUN_DIR/downloads"

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
"$BRIDGE_BIN" &
BRIDGE_PID=$!
echo "bridge started on 127.0.0.1:${BRIDGE_PORT} (pid $BRIDGE_PID)"
sleep 1
if ! kill -0 "$BRIDGE_PID" 2>/dev/null; then
    echo "ERROR: bridge failed to start"
    exit 1
fi

echo "Using DOSBox runtime: ${DOSBOX_RUNTIME}"
echo "Using DOSBox binary: $DOSBOX_BIN"
echo "Run directory: $RUN_DIR"
if [ "$IS_DOSBOX_X" -eq 1 ]; then
    echo "DOSBox-X scanlines: ${DOSBOX_X_SCANLINES} (output=${DOSBOX_X_EFFECTIVE_OUTPUT}, scaler=${DOSBOX_X_EFFECTIVE_SCALER})"
fi

cd "$RUN_DIR"
set +e
DOSBOX_RC=130
if [ "$IS_DOSBOX_X" -eq 1 ]; then
    "$DOSBOX_BIN" \
        -nomenu \
        -conf dosbox.conf \
        -set "core=${DOSBOX_CPU_CORE}" \
        -set "cputype=${DOSBOX_CPU_CPUTYPE}" \
        -set "cycles=${DOSBOX_CPU_CYCLES_SET_X}" \
        -set "mouse_capture=nomouse" \
        -set "mouse_middle_release=false" \
        -set "dos_mouse_driver=false" \
        -set "output=${DOSBOX_X_EFFECTIVE_OUTPUT}" \
        -set "doublescan=${DOSBOX_X_DOUBLESCAN}" \
        -set "showmenu=false" \
        -set "scaler=${DOSBOX_X_EFFECTIVE_SCALER}" \
        -set "windowresolution=${DOSBOX_X_WINDOWRES}"
    DOSBOX_RC=$?
else
    # DOSBox-Staging path: avoid DOSBox-X-only options (doublescan/showmenu/scaler).
    SDL_RENDER_DRIVER=software LIBGL_ALWAYS_SOFTWARE=1 \
    "$DOSBOX_BIN" \
        --noprimaryconf \
        --nolocalconf \
        -conf dosbox.conf \
        -set "core=${DOSBOX_CPU_CORE}" \
        -set "cputype=${DOSBOX_CPU_CPUTYPE}" \
        -set "cpu_cycles=${DOSBOX_CPU_CYCLES_SET_STAGING}" \
        -set "startup_verbosity=quiet" \
        -set "mouse_capture=nomouse" \
        -set "mouse_middle_release=false" \
        -set "dos_mouse_driver=false" \
        -set "output=texture"
    DOSBOX_RC=$?
    if [ "$DOSBOX_RC" -ne 0 ] && [ "$DOSBOX_PORTABLE_STRICT" != "1" ] && [ -x "$DOSBOX_X_BIN_DEFAULT" ]; then
        echo "Portable DOSBox failed with code $DOSBOX_RC; falling back to DOSBox-X."
        "$DOSBOX_X_BIN_DEFAULT" \
            -nomenu \
            -conf dosbox.conf \
            -set "core=${DOSBOX_CPU_CORE}" \
            -set "cputype=${DOSBOX_CPU_CPUTYPE}" \
            -set "cycles=${DOSBOX_CPU_CYCLES_SET_X}" \
            -set "mouse_capture=nomouse" \
            -set "mouse_middle_release=false" \
            -set "dos_mouse_driver=false" \
            -set "output=${DOSBOX_X_EFFECTIVE_OUTPUT}" \
            -set "doublescan=${DOSBOX_X_DOUBLESCAN}" \
            -set "showmenu=false" \
            -set "scaler=${DOSBOX_X_EFFECTIVE_SCALER}" \
            -set "windowresolution=${DOSBOX_X_WINDOWRES}"
        DOSBOX_RC=$?
    fi
fi
set -e

if [ "$DOSBOX_RC" -ne 0 ]; then
    echo "WARNING: DOSBox exited with code $DOSBOX_RC"
fi
