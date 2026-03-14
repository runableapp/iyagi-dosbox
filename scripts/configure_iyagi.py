#!/usr/bin/env python3
r"""
configure_iyagi.py  —  Patch IYAGI 5.3 config files for the SSH bridge setup.

Usage:
    python3 configure_iyagi.py <path-to-app-dir>

The script makes two changes inside the IYAGI program directory:

  1. I.CNF  — replaces the hardcoded download path (C:\COMM\TALK53\DOWN)
              with D:\\ so that received files land in the DOSBox D: drive,
              which the launcher maps to the host-side downloads/ folder.

  2. I.TEL  — removes legacy bridge phone-book entries that dial
              127.0.0.1:2323. ATDT target parsing now happens in bridge,
              so hardcoding bridge dial targets in I.TEL is no longer needed.

I.TEL binary format (IYAGI 5.3, Borland C++ 16-bit DOS, no padding):
    Header : 39 bytes  (ASCII header string terminated by 0x1A / DOS EOF)
    Entries: N × 103 bytes each

    Per-entry struct (C, little-endian ints, no alignment padding):
        char  name[21]     — display name (EUC-KR or ASCII, null-terminated)
        char  telnum[17]   — dial string (IP:port accepted by DOSBox modem)
        int   brate (2B)   — speed index: 0=1200 1=2400 2=4800 3=9600
                                          4=19200 5=38400 6=57600 7=115200
        char  parity (1B)  — 'E', 'O', or 'N'
        int   dbit  (2B)   — actual bit count: 7 or 8
        int   sbit  (2B)   — actual stop-bit count: 1 or 2
        int   han   (2B)   — Korean mode: 0=완성 1=조합 3=구KS 4=삼성
                                          5=7bit 6=KS5601 7=영문(ASCII)
        char  hlp[56]      — description / auto-connect script (null for us)
"""

import os
import struct
import sys
import shutil

# ─── constants ───────────────────────────────────────────────────────────────

ICNF_FILENAME = "I.CNF"
ITEL_FILENAME = "I.TEL"

# I.CNF: the original download path string to find and replace
ICNF_OLD_PATH = b"C:\\COMM\\TALK53\\DOWN"
ICNF_NEW_PATH = b"D:\\"          # maps to downloads/ folder in DOSBox
# Offsets accidentally forced by older patch logic; restore from .orig when present.
ICNF_LEGACY_RESTORE_OFFSETS = (57, 61)

# I.TEL: header is 39 bytes (ends with 0x1A DOS EOF sentinel)
ITEL_HEADER_SENTINEL = 0x1A
ITEL_ENTRY_SIZE = 103
ITEL_ENTRY_FMT = "<21s17shchhh56s"   # little-endian, no padding — 103 bytes

assert struct.calcsize(ITEL_ENTRY_FMT) == ITEL_ENTRY_SIZE, (
    f"Entry format size mismatch: {struct.calcsize(ITEL_ENTRY_FMT)} != {ITEL_ENTRY_SIZE}"
)

# Legacy bridge phone-book target to remove from I.TEL.
LEGACY_BRIDGE_TELNUM = "127.0.0.1:2323"
HANGUL_MODE_WANSUNG = 0

# ─── helpers ─────────────────────────────────────────────────────────────────

def pad(s: str, length: int) -> bytes:
    """Encode ASCII string, null-pad or truncate to exactly `length` bytes."""
    b = s.encode("ascii", errors="replace")
    return b[:length].ljust(length, b"\x00")


# ─── I.CNF patcher ───────────────────────────────────────────────────────────

def patch_icnf(path: str) -> None:
    with open(path, "rb") as f:
        data = bytearray(f.read())

    legacy_restored = 0
    backup_path = path + ".orig"
    if os.path.isfile(backup_path):
        with open(backup_path, "rb") as f:
            orig = f.read()
        for off in ICNF_LEGACY_RESTORE_OFFSETS:
            if off < len(data) and off < len(orig) and data[off] != orig[off]:
                data[off] = orig[off]
                legacy_restored += 1

    idx = data.find(ICNF_OLD_PATH)
    path_updated = False
    if idx != -1:
        # The down_area field is 58 bytes; overwrite from idx onward
        new_bytes = ICNF_NEW_PATH.ljust(58, b"\x00")
        data[idx : idx + 58] = new_bytes
        path_updated = True

    if not path_updated and legacy_restored == 0:
        print("  [I.CNF] No updates needed — skipping")
        return

    with open(path, "wb") as f:
        f.write(data)

    if path_updated:
        print(f"  [I.CNF] Replaced download path: {ICNF_OLD_PATH.decode()} → D:\\")
    else:
        print("  [I.CNF] Download path not found — left as-is")
    if legacy_restored > 0:
        print(
            f"  [I.CNF] Restored {legacy_restored} legacy-touched "
            f"offset{'s' if legacy_restored != 1 else ''} from .orig"
        )


# ─── I.TEL patcher ───────────────────────────────────────────────────────────

def patch_itel(path: str) -> None:
    with open(path, "rb") as f:
        data = f.read()

    # Locate the header sentinel (0x1A) to find where entries begin
    sentinel_idx = data.find(bytes([ITEL_HEADER_SENTINEL]))
    if sentinel_idx == -1:
        print(f"  [I.TEL] Header sentinel 0x1A not found — cannot patch")
        return

    header = data[: sentinel_idx + 1]          # bytes 0..sentinel (inclusive)
    body   = data[sentinel_idx + 1 :]           # entry data

    entry_count = len(body) // ITEL_ENTRY_SIZE
    remainder   = body[entry_count * ITEL_ENTRY_SIZE :]  # trailing bytes if any

    # Remove old hardcoded bridge entries (127.0.0.1:2323).
    legacy_telnum = pad(LEGACY_BRIDGE_TELNUM, 17)
    kept_entries = []
    removed = 0
    han_updated = 0
    for i in range(entry_count):
        chunk = body[i * ITEL_ENTRY_SIZE : (i + 1) * ITEL_ENTRY_SIZE]
        fields = struct.unpack(ITEL_ENTRY_FMT, chunk)
        if fields[1] == legacy_telnum:
            removed += 1
            continue
        # Force Hangul mode to 완성형 (0) so terminal text matches bridge EUC-KR handling.
        # fields: name, telnum, brate, parity, dbit, sbit, han, hlp
        if fields[6] != HANGUL_MODE_WANSUNG:
            fields = fields[:6] + (HANGUL_MODE_WANSUNG,) + fields[7:]
            han_updated += 1
        kept_entries.append(struct.pack(ITEL_ENTRY_FMT, *fields))

    if removed == 0 and han_updated == 0:
        print(
            f"  [I.TEL] No legacy bridge entry ({LEGACY_BRIDGE_TELNUM}) and "
            "all entries already 완성형 — skipping"
        )
        return

    new_body = b"".join(kept_entries)

    with open(path, "wb") as f:
        f.write(header + new_body + remainder)

    print(
        f"  [I.TEL] Removed {removed} legacy bridge entr"
        f"{'y' if removed == 1 else 'ies'} "
        f"({LEGACY_BRIDGE_TELNUM}); forced 완성형 on {han_updated} "
        f"entr{'y' if han_updated == 1 else 'ies'}; total entries: {entry_count - removed}"
    )


# ─── main ────────────────────────────────────────────────────────────────────

def main() -> None:
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <path-to-iyagi-app-dir>")
        sys.exit(1)

    app_dir = sys.argv[1]
    if not os.path.isdir(app_dir):
        print(f"Error: {app_dir!r} is not a directory")
        sys.exit(1)

    icnf_path = os.path.join(app_dir, ICNF_FILENAME)
    itel_path = os.path.join(app_dir, ITEL_FILENAME)

    print(f"Configuring IYAGI in: {app_dir}")

    if os.path.isfile(icnf_path):
        # Back up original before patching
        backup = icnf_path + ".orig"
        if not os.path.exists(backup):
            shutil.copy2(icnf_path, backup)
        patch_icnf(icnf_path)
    else:
        print(f"  [I.CNF] Not found at {icnf_path} — skipping")

    if os.path.isfile(itel_path):
        backup = itel_path + ".orig"
        if not os.path.exists(backup):
            shutil.copy2(itel_path, backup)
        patch_itel(itel_path)
    else:
        print(f"  [I.TEL] Not found at {itel_path} — skipping")

    print("Done.")


if __name__ == "__main__":
    main()
