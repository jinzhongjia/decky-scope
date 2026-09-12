#!/usr/bin/env python3
"""Install the pinned official Linux x86_64 Zig toolchain into a task-owned directory."""
import argparse
import hashlib
import json
import os
import platform
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def install(destination: Path):
    config = json.loads((ROOT / 'ci/toolchains.json').read_text())['zig']
    if platform.system() != 'Linux' or platform.machine() not in ('x86_64', 'AMD64'):
        raise ValueError('CI Zig installation supports Linux x86_64 only')
    destination = destination.resolve()
    if destination.exists():
        raise ValueError(f'Refusing to replace an existing directory: {destination}')
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='deckscope-zig-', dir=destination.parent) as temp:
        temp = Path(temp)
        archive = temp / 'zig.tar.xz'
        with urllib.request.urlopen(config['url'], timeout=90) as source, archive.open('wb') as target:
            shutil.copyfileobj(source, target)
        with archive.open('rb') as stream:
            digest = hashlib.file_digest(stream, 'sha256').hexdigest()
        if digest != config['sha256']:
            raise ValueError('Official Zig archive checksum mismatch')
        unpack = temp / 'unpack'
        unpack.mkdir()
        with tarfile.open(archive) as package:
            package.extractall(unpack, filter='data')
        folders = list(unpack.iterdir())
        if len(folders) != 1 or not (folders[0] / 'zig').is_file():
            raise ValueError('Unexpected Zig archive layout')
        version = subprocess.check_output([str(folders[0] / 'zig'), 'version'], text=True).strip()
        if version != config['version']:
            raise ValueError('Installed Zig reports an unexpected version')
        folders[0].rename(destination)
    if os.environ.get('GITHUB_PATH'):
        with open(os.environ['GITHUB_PATH'], 'a') as output:
            output.write(str(destination) + '\n')
    print(destination)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--destination', type=Path, required=True)
    install(parser.parse_args().destination)
