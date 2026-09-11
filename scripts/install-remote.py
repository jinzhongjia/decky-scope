#!/usr/bin/env python3
"""Invoked only by deploy.sh after approval; requires root for Decky plugin installation."""
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import zipfile
from pathlib import Path


def main():
    if os.geteuid() != 0:
        raise SystemExit("Run via sudo after explicit deployment approval")
    archive_path, plugins = Path(sys.argv[1]), Path(sys.argv[2])
    if not plugins.is_absolute() or not plugins.is_dir():
        raise SystemExit("Existing Decky plugins directory required")
    destination = plugins / "DeckScope"
    if destination.is_symlink():
        raise SystemExit("Refusing symlink plugin destination")
    staging = Path(tempfile.mkdtemp(prefix=".deckscope-stage-", dir=plugins.parent))
    os.chmod(staging, 0o755)
    backups = plugins.parent / "deckscope-backups"
    backups.mkdir(mode=0o700, exist_ok=True)
    backup = backups / f"DeckScope-{time.time_ns()}"
    swapped = False
    try:
        with zipfile.ZipFile(archive_path) as archive:
            if archive.testzip() is not None:
                raise ValueError("Corrupt archive")
            for item in archive.infolist():
                path = Path(item.filename)
                if path.is_absolute() or ".." in path.parts or path.parts[0] != "DeckScope":
                    raise ValueError("Unsafe archive path")
                if stat.S_ISLNK(item.external_attr >> 16):
                    raise ValueError("Symlink archive entry")
                target = staging.joinpath(*path.parts[1:])
                if item.is_dir():
                    target.mkdir(parents=True, exist_ok=True)
                    continue
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(archive.read(item))
                os.chmod(target, 0o755 if path.parts[1] == "bin" else 0o644)
        required = ["main.py", "plugin.json", "dist/index.js", "bin/deckscope-monitor"]
        if not all((staging / name).is_file() for name in required):
            raise ValueError("Incomplete plugin package")
        (staging / "dev_mode").touch(mode=0o644)
        if destination.exists():
            destination.rename(backup)
        staging.rename(destination)
        swapped = True
        subprocess.run(["systemctl", "restart", "plugin_loader"], check=True)
        print("Installed DeckScope; previous plugin retained at", backup if backup.exists() else "(first install)")
    except BaseException:
        if swapped:
            destination.rename(backups / f"DeckScope-failed-{time.time_ns()}")
        if backup.exists():
            backup.rename(destination)
        raise
    finally:
        if staging.exists():
            shutil.rmtree(staging)


if __name__ == "__main__":
    main()
