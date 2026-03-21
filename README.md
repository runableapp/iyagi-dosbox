# IYAGI 5.3 SSH Wrapper (DOSBox)

Run the legacy DOS terminal program **IYAGI 5.3** over modern **SSH** by wrapping it with DOSBox-Staging and a local Go bridge that emulates modem behavior.

This project targets:
- Local Linux runs (`tools/run-dosbox.sh`)
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
- `ATDT=<host>:<port>` -> same as above (`=` prefix supported)
- `ATDT<host>` -> defaults to SSH port 22
- `ATDT=<user>@<host>:<port>` -> override SSH user from dial string
  - example: `ATDT=ssh@localhost:40000` -> runs SSH with `{userhost}=ssh@localhost`, `-p 40000`
- `ATDT` (empty target) -> tone then `NO CARRIER`
- `ATDT;` -> tone then `OK`
- `ATDT-<target>` -> fast dial (skip dial/ring sounds)

DTMF playback mapping:
- Digits `0-9`, `*`, `#` play their own tones
- Letters in dial target are converted by phone keypad mapping:
  - `ABC->2`, `DEF->3`, `GHI->4`, `JKL->5`, `MNO->6`, `PQRS->7`, `TUV->8`, `WXYZ->9`
  - example: `ATDT=bbs.runable.app:40000` plays DTMF using mapped digits for `bbsrunableapp`

Additional modem command:
- `CLS` / `CLEAR` -> prints 28 blank lines in command mode

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
- `DOSBOX_FRAMESKIP` (`0-10`, default `1`)
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

By default this helper sets `USER_DATA_ROOT` to `iyagi-data/` (same `.env` as `run-dosbox.sh`). To test the packaged default user directory instead, run `RUN_APPIMAGE_XDG=1 ./tools/run-appimage.sh` (uses `~/.local/share/iyagi-terminal/`, same single-tree layout as `iyagi-data/`).

---

## Launcher scripts

Local:
- `tools/run-dosbox.sh` (portable DOSBox-Staging-focused)

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

### Keeping first-run `.env` in sync with dev

`resources/common/.env.example` is what ships inside packages and becomes a new user’s `.env` on first copy. It is **not** auto-filled from `iyagi-data/.env` at build time (that tree is local and often gitignored).

After you settle on good `DOSBOX_*` / `BRIDGE_*` values in `iyagi-data/.env`, **port those lines into `.env.example`** (e.g. `diff -u resources/common/.env.example iyagi-data/.env`) so AppImage and other installs get the same defaults—without copying secrets or personal `IYAGI_USER` / port choices unless they are meant for everyone.

**Existing installs:** the launcher copies `.env.example` → `.env` **only when `.env` is missing**. Updating the repo or rebuilding the AppImage does **not** overwrite `~/.local/share/iyagi-terminal/.env`. No Python step rewrites it. To refresh defaults, remove or rename that `.env` (or merge changes by hand). Verify what shipped inside the AppImage: `./dist/IYAGI-linux-x86_64.AppImage --appimage-extract` then `head squashfs-root/.env.example` (or inspect `AppDir/.env.example` mid-build before `appimagetool` runs).

### Local script mode
- Root: `iyagi-data/`
- App files: `iyagi-data/app/IYAGI`
- Downloads: `iyagi-data/downloads`
- Env: `iyagi-data/.env`

### AppImage mode (default)
- User data (`.env`, `keys/`, `app/`, `downloads/`, `staging/`): `${XDG_DATA_HOME:-~/.local/share}/iyagi-terminal/` (same layout as `iyagi-data/` from `run-dosbox.sh`)

Override both with:
- `USER_DATA_ROOT`

---

## Troubleshooting

- **AppImage still behaves differently from `./tools/run-appimage.sh`**
  - Rebuild after launcher changes: `bash tools/build-linux.sh` (running `dist/*.AppImage` uses whatever was baked into that file).
  - `run-appimage.sh` sets `USER_DATA_ROOT` to `iyagi-data/`; double‑clicking the AppImage uses `~/.local/share/iyagi-terminal/` — compare the two `.env` files if timing differs.
  - A **`DOSBOX_BIN` exported in your desktop session** (e.g. from a dev profile) used to override even `DOSBOX_SOURCE=bundled`; the AppImage launcher now drops inherited `DOSBOX_BIN` unless you set it on the same command line as the AppImage.
  - On start, the launcher prints `DOSBox profile:` with `cpu_cycles`, `frameskip`, and `output` — confirm they match what you expect.
  - Run `env | grep -E '^DOSBOX_'` before launching: values like `DOSBOX_CPU_CYCLES=max` are **ignored** by the AppImage launcher unless they are plain integers (otherwise defaults apply).
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

This project is licensed under **PolyForm Noncommercial 1.0.0**.  
IYAGI is freeware but not open source; verify redistribution rights for your target distribution channel.

