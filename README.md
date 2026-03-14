# IYAGI 5.3 SSH Wrapper (DOSBox)

Run the legacy DOS terminal program **IYAGI 5.3** over modern **SSH** by wrapping it with DOSBox-Staging and a local Go bridge that emulates modem behavior.

This project targets:
- Local Linux runs (`tools/run-dosbox.sh`, `tools/run-direct.sh`)
- Linux AppImage packaging
- Windows portable package/installer flow
- macOS app bundle/DMG flow

---

## What this project does

- Runs IYAGI 5.3 inside DOSBox
- Connects IYAGI COM port traffic to a local bridge (modem-like AT command parser)
- Converts `ATDT...` into SSH connection attempts
- Supports SSH-BBS style login flow (`SSH_AUTH_MODE=bbs`) or key-based mode (`SSH_AUTH_MODE=key`)
- Handles Korean encoding conversion between IYAGI and UTF-8 servers
- Plays modem-style dial/busy/ringing/connect sounds

---

## Runtime architecture

```text
IYAGI (DOS app)
  -> COM4 in DOSBox-Staging
  -> nullmodem tcp 127.0.0.1:<bridge_port>
  -> bridge (Go)
  -> ssh client process
  -> target SSH server / SSH-BBS
```

IYAGI still behaves like a dial-up terminal from the user perspective:
- `AT` / `ATDT...` / `ATH` / `ATO` style interactions
- modem-like response strings (`OK`, `CONNECT`, `NO CARRIER`, etc.)

---

## Quick start (Linux local)

From repository root:

```bash
task deps
./tools/run-dosbox.sh
```

What `task deps` does:
- extracts `software/iyagi53dos.zip` (only if not already extracted)
- downloads portable DOSBox-Staging into `third_party/dosbox-staging`

First run creates/uses:
- `iyagi-data/.env`
- `iyagi-data/app/IYAGI`
- `iyagi-data/downloads`

---

## ATDT dialing behavior

In IYAGI terminal:

- `ATDT<host>:<port>` -> dial exact target
- `ATDT<host>` -> defaults to SSH port 22
- `ATDT` (empty target) -> tone then `NO CARRIER`
- `ATDT;` -> tone then `OK`

The bridge parses ATDT target text directly and attempts outbound SSH accordingly.

---

## Configuration

Main config template:
- `resources/common/.env.example`

Local runtime config:
- `iyagi-data/.env`

### Important environment variables

- `SSH_AUTH_MODE`:
  - `bbs` (default): no local key required
  - `key`: use local keypair in `iyagi-data/keys`
- `BRIDGE_PORT`: local bridge listen port (`auto` supported)
- `BRIDGE_CONNECT_TIMEOUT_SEC`: outbound probe timeout
- `BRIDGE_BUSY_REPEAT`, `BRIDGE_BUSY_GAP_MS`
- `BRIDGE_DTMF_GAP_MS`
- `BRIDGE_POST_DTMF_DELAY_MS`
- `BRIDGE_CLIENT_ENCODING`, `BRIDGE_SERVER_ENCODING`
- `BRIDGE_SERVER_REPAIR_MOJIBAKE`
- `BRIDGE_DEBUG`

DOSBox timing/display:
- `DOSBOX_CPU_CORE` (default `simple`)
- `DOSBOX_CPU_CPUTYPE` (default `386`)
- `DOSBOX_CPU_CYCLES` (numeric for Staging path)
- `DOSBOX_VIDEO_BACKEND` (`auto|x11|wayland`)
- `DOSBOX_WAYLAND_STRICT`

Scanline shader toggle (DOSBox-Staging):
- `DOSBOX_SCANLINES=0|1`
- `DOSBOX_GLSHADER` (example: `crt/vga-1080p`)
- `DOSBOX_SCANLINE_WINDOWRES` (example: `1280x960`)

---

## Scanline presets (DOSBox-Staging)

When `DOSBOX_SCANLINES=1`, Staging switches to OpenGL shader mode.

Recommended shader presets:
- Sharp: `crt/vga-1080p-fake-double-scan`
- Balanced: `crt/vga-1080p`
- Soft: `crt/composite-1080p`

You can list available shaders:

```bash
third_party/dosbox-staging/unpacked/dosbox --list-glshaders
```

---

## Mouse, network, and MIDI defaults

Current project defaults are tuned for terminal use:

- Mouse input disabled in DOS guest:
  - `mouse_capture=nomouse`
  - `dos_mouse_driver=false`
- DOSBox ethernet/slirp disabled:
  - `[ethernet] ne2000=false`
- MIDI output disabled:
  - `mididevice=none`

These reduce irrelevant warnings/noise and avoid input interference in IYAGI.

---

## Build outputs

### Linux AppImage

```bash
bash tools/build-linux.sh
```

Output:
- `dist/IYAGI-linux-x86_64.AppImage`

### Run built AppImage locally

```bash
./tools/run-appimage.sh
```

---

## Launcher scripts

Local:
- `tools/run-dosbox.sh` (portable DOSBox-Staging-focused)
- `tools/run-direct.sh` (direct runtime script, fallback-capable)

Packaged launchers:
- Linux AppImage: `resources/linux/launch.sh`
- macOS: `resources/macos/launcher`
- Windows: `resources/windows/launch.bat`

Cross-platform parity for launch behavior is intentional and maintained.

---

## Taskfile

`Taskfile.yml` includes:

- `task deps` (extract IYAGI + download DOSBox)
- `task iyagi:extract`
- `task dosbox:download`
- `task keys:generate`
- `task bridge:embed-sounds`
- `task bridge:build`

---

## Data directories

### Local script mode
- Root: `iyagi-data/`
- App files: `iyagi-data/app/IYAGI`
- Downloads: `iyagi-data/downloads`
- Env: `iyagi-data/.env`

### AppImage mode (default)
- Config: `${XDG_CONFIG_HOME:-~/.config}/iyagi-terminal`
- Data: `${XDG_DATA_HOME:-~/.local/share}/iyagi-terminal`

Override both with:
- `USER_DATA_ROOT`

---

## Troubleshooting

- Cursor looks too fast:
  - lower `DOSBOX_CPU_CYCLES` (for example 1200 -> 1000 -> 800)
- Shader enabled but window looks too small:
  - use `DOSBOX_SCANLINE_WINDOWRES=1280x960` for 2x-like 640x480 presentation
- Dial sounds too fast:
  - increase `BRIDGE_DTMF_GAP_MS`
- Need visible post-dial pause:
  - increase `BRIDGE_POST_DTMF_DELAY_MS`

---

## Legal note

IYAGI is freeware but not open source.  
This project wraps and launches it; verify redistribution rights for your target distribution channel.

