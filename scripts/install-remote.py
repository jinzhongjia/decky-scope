#!/usr/bin/env python3
"""Invoked only by deploy.sh after approval; requires root for Decky plugin installation."""
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import zipfile
from pathlib import Path


def restart_after_recovery():
    result = subprocess.run(['systemctl', 'restart', 'plugin_loader'], check=False)
    if result.returncode:
        print('Files restored, but Loader recovery failed; inspect service status before proceeding', file=sys.stderr)


def rollback(plugins, name):
    if not re.fullmatch(r'DeckScope-[0-9]+', name):
        raise ValueError('A single timestamped backup name is required')
    if not plugins.is_absolute() or not plugins.is_dir() or plugins.is_symlink():
        raise ValueError('Existing non-symlink plugins directory required')
    backups = plugins.parent / 'deckscope-backups'
    backup, destination = backups / name, plugins / 'DeckScope'
    if backups.is_symlink() or backup.is_symlink() or destination.is_symlink():
        raise ValueError('Refusing symlink rollback paths')
    if not all((backup / item).is_file() for item in ('main.py', 'plugin.json', 'dist/index.js', 'bin/deckscope-monitor')):
        raise ValueError('Backup is missing or incomplete')
    displaced = backups / f'DeckScope-{time.time_ns()}'
    if destination.exists():
        destination.rename(displaced)
    restored = False
    try:
        backup.rename(destination)
        restored = True
        subprocess.run(['systemctl', 'restart', 'plugin_loader'], check=True)
        print('Backup restored; displaced version retained at', displaced if displaced.exists() else '(none)')
    except BaseException:
        if restored:
            destination.rename(backup)
        if displaced.exists():
            displaced.rename(destination)
            restart_after_recovery()
        raise


def main():
    if os.geteuid() != 0:
        raise SystemExit("Run via sudo after explicit deployment approval")
    if len(sys.argv) == 4 and sys.argv[1] == '--rollback':
        return rollback(Path(sys.argv[2]), sys.argv[3])
    if len(sys.argv) != 3:
        raise SystemExit('Usage: install-remote.py ARCHIVE PLUGINS | --rollback PLUGINS DeckScope-TIMESTAMP')
    archive_path, plugins = Path(sys.argv[1]), Path(sys.argv[2])
    if not plugins.is_absolute() or not plugins.is_dir() or plugins.is_symlink():
        raise SystemExit("Existing Decky plugins directory required")
    destination = plugins / "DeckScope"
    if destination.is_symlink():
        raise SystemExit("Refusing symlink plugin destination")
    staging = Path(tempfile.mkdtemp(prefix=".deckscope-stage-", dir=plugins.parent))
    os.chmod(staging, 0o755)
    backups = plugins.parent / "deckscope-backups"
    if backups.is_symlink():
        staging.rmdir()
        raise ValueError('Refusing symlink backup directory')
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
                if len(path.parts) < 2 and not item.is_dir():
                    raise ValueError('Missing path below plugin root')
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
            restart_after_recovery()
        raise
    finally:
        if staging.exists():
            shutil.rmtree(staging)


if __name__ == "__main__":
    main()
