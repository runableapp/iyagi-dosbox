#!/usr/bin/env python3
"""
Resolve the canonical IYAGI source directory for launch/build scripts.

Priority:
1) IYAGI_SOURCE_DIR environment variable (if valid)
2) app/IYAGI
3) app
4) software/iyagi53dos/IYAGI
"""

from __future__ import annotations

import os
import sys
from pathlib import Path


def is_valid_iyagi_dir(path: Path) -> bool:
    return path.is_dir() and (path / "I.EXE").is_file()


def resolve(repo_root: Path) -> Path:
    env_override = os.environ.get("IYAGI_SOURCE_DIR", "").strip()
    if env_override:
        env_path = Path(env_override)
        if not env_path.is_absolute():
            env_path = repo_root / env_path
        env_path = env_path.resolve()
        if is_valid_iyagi_dir(env_path):
            return env_path
        raise SystemExit(
            f"IYAGI_SOURCE_DIR is set but invalid (missing I.EXE): {env_path}"
        )

    candidates = [
        repo_root / "app" / "IYAGI",
        repo_root / "app",
        repo_root / "software" / "iyagi53dos" / "IYAGI",
    ]
    for candidate in candidates:
        if is_valid_iyagi_dir(candidate):
            return candidate

    raise SystemExit(
        "Could not find IYAGI source. Expected one of:\n"
        "  - app/IYAGI/I.EXE\n"
        "  - app/I.EXE\n"
        "  - software/iyagi53dos/IYAGI/I.EXE\n"
        "You can also set IYAGI_SOURCE_DIR to an explicit directory."
    )


def main() -> None:
    repo_root = Path(__file__).resolve().parents[1]
    print(resolve(repo_root))


if __name__ == "__main__":
    main()
