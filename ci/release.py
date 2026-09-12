#!/usr/bin/env python3
"""Validate release identity and create assets from the fully tested development ZIP."""
import argparse
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSION = re.compile(r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?')
BASE_FILES = {'main.py', 'plugin.json', 'package.json', 'dist/index.js', 'bin/deckscope-monitor'}


def identity(root=ROOT, tag=''):
    package = json.loads((root / 'package.json').read_text())
    version = package['version']
    if not VERSION.fullmatch(version):
        raise ValueError('Expected X.Y.Z or X.Y.Z-prerelease version')
    if '-' in version and any(x.isdigit() and len(x) > 1 and x.startswith('0') for x in version.split('-', 1)[1].split('.')):
        raise ValueError('Numeric prerelease identifiers cannot have leading zeroes')
    if tag and tag != 'v' + version:
        raise ValueError(f'Tag {tag!r} must equal v{version}')
    native = re.search(r'pub const version = "([^"]+)";', (root / 'monitor/src/model.zig').read_text())
    if not native or native[1] != version:
        raise ValueError('Native and package versions differ')
    tools = json.loads((root / 'ci/toolchains.json').read_text())
    if package['packageManager'] != 'pnpm@' + tools['pnpm']:
        raise ValueError('Pinned pnpm and packageManager differ')
    return {'version': version, 'tag': tag, 'prerelease': '-' in version,
            'node': tools['node'], 'python': tools['python'], 'pnpm': tools['pnpm'], 'zig': tools['zig']['version']}


def tracked_tag(tag, root=ROOT):
    if not tag:
        return
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
    target = subprocess.check_output(['git', 'rev-parse', '--verify', f'refs/tags/{tag}^{{commit}}'], cwd=root, text=True).strip()
    if head != target:
        raise ValueError('Checked-out commit does not match the release tag')


def allowed_files(root):
    result = BASE_FILES | {p.relative_to(root).as_posix() for p in (root / 'py_modules').glob('*.py')}
    for name in ('LICENSE', 'LICENSE.md', 'LICENSE.txt', 'THIRD-PARTY-NOTICES.md'):
        if (root / name).is_file():
            result.add(name)
    if (root / 'licenses').exists():
        result |= {p.relative_to(root).as_posix() for p in (root / 'licenses').glob('*.txt') if p.is_file()}
    return result


def validate_package(archive, root=ROOT):
    expected = {'DeckScope/' + name for name in allowed_files(root)}
    with zipfile.ZipFile(archive) as package:
        names = package.namelist()
        if len(set(names)) != len(names) or set(names) != expected:
            raise ValueError('ZIP entries do not match the release allowlist')
        if package.testzip():
            raise ValueError('ZIP CRC verification failed')
        for entry in package.infolist():
            mode = entry.external_attr >> 16
            if not stat.S_ISREG(mode):
                raise ValueError('ZIP contains a non-regular file')
            relative = entry.filename.removeprefix('DeckScope/')
            payload = package.read(entry)
            if not payload or payload != (root / relative).read_bytes():
                raise ValueError(f'Stale or empty ZIP member: {relative}')
            required = 0o755 if relative == 'bin/deckscope-monitor' else 0o644
            if stat.S_IMODE(mode) != required:
                raise ValueError(f'Incorrect ZIP permissions: {relative}')
        native = package.read('DeckScope/bin/deckscope-monitor')
        if native[:6] != b'\x7fELF\x02\x01' or native[18:20] != b'\x3e\x00' or len(native) >= 262144:
            raise ValueError('Expected a <256 KiB Linux x86_64 ELF64 monitor')


def make_assets(root=ROOT, tag='', output=None):
    meta = identity(root, tag)
    tracked_tag(tag, root)
    source = root / 'outputs/DeckScope-dev.zip'
    validate_package(source, root)
    output = output or root / 'outputs/ci'
    output.mkdir(parents=True, exist_ok=True)
    if any(output.iterdir()):
        raise ValueError('Release output directory must be empty; use a fresh directory')
    name = f'DeckScope-{meta["version"]}-linux-x86_64.zip'
    target = output / name
    shutil.copyfile(source, target)
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    manifest = {'schema': 1, 'name': 'DeckScope', 'version': meta['version'], 'tag': tag,
                'source_commit': commit, 'target': 'x86_64-linux',
                'toolchains': {k: meta[k] for k in ('zig', 'node', 'python', 'pnpm')},
                'assets': {name: {'sha256': digest, 'bytes': target.stat().st_size}},
                'runtime_sha256': {p: hashlib.sha256((root / p).read_bytes()).hexdigest() for p in sorted(BASE_FILES)},
                'main_license_present': any((root / p).is_file() for p in ('LICENSE', 'LICENSE.md', 'LICENSE.txt'))}
    manifest_path = output / 'build-manifest.json'
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
    (output / 'SHA256SUMS').write_text(f'{digest}  {name}\n{hashlib.sha256(manifest_path.read_bytes()).hexdigest()}  build-manifest.json\n')
    print(output)
    return manifest


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('metadata', 'package'))
    parser.add_argument('--tag', default=os.environ.get('RELEASE_TAG', ''))
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    meta = identity(tag=args.tag)
    if args.command == 'metadata':
        tracked_tag(args.tag)
        print(json.dumps(meta, indent=2))
        if os.environ.get('GITHUB_OUTPUT'):
            with open(os.environ['GITHUB_OUTPUT'], 'a') as out:
                for key, value in meta.items():
                    out.write(f'{key}={str(value).lower() if isinstance(value, bool) else value}\n')
                out.write('commit=' + subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip() + '\n')
    else:
        make_assets(tag=args.tag, output=args.output)
