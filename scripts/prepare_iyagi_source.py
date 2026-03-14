#!/usr/bin/env python3
"""
Prepare canonical patched IYAGI source once, then reuse everywhere.

Outputs the canonical directory path on stdout.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path


def run() -> None:
    repo_root = Path(__file__).resolve().parents[1]
    canonical_dir = Path(
        os.environ.get("IYAGI_CANONICAL_DIR", repo_root / "app" / "IYAGI")
    )
    if not canonical_dir.is_absolute():
        canonical_dir = (repo_root / canonical_dir).resolve()

    source_dir = subprocess.check_output(
        [sys.executable, str(repo_root / "scripts" / "resolve_iyagi_source.py")],
        text=True,
        cwd=repo_root,
    ).strip()
    source_path = Path(source_dir)

    if source_path.resolve() != canonical_dir.resolve():
        if canonical_dir.exists():
            shutil.rmtree(canonical_dir)
        canonical_dir.mkdir(parents=True, exist_ok=True)
        shutil.copytree(source_path, canonical_dir, dirs_exist_ok=True)
    else:
        canonical_dir.mkdir(parents=True, exist_ok=True)

    subprocess.run(
        [sys.executable, str(repo_root / "scripts" / "configure_iyagi.py"), str(canonical_dir)],
        check=True,
        cwd=repo_root,
        stdout=sys.stderr,
        stderr=sys.stderr,
    )

    print(str(canonical_dir))


if __name__ == "__main__":
    run()
