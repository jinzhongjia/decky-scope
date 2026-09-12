#!/usr/bin/env python3
"""Publish validated current-run assets only; never create/move tags or overwrite differing assets."""
import argparse
import hashlib
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path
from urllib.parse import quote


def gh(*args):
    return subprocess.check_output(['gh', *args], text=True)


def asset_decision(remote, digest):
    if remote is None:
        return 'upload'
    if remote.get('digest') == 'sha256:' + digest:
        return 'skip'
    if remote.get('digest'):
        raise ValueError('Existing release asset has different contents; use a new version')
    return 'verify-download'


def verify_assets(folder, tag, commit):
    manifest = json.loads((folder / 'build-manifest.json').read_text())
    if manifest.get('tag') != tag or manifest.get('source_commit') != commit or 'v' + manifest.get('version', '') != tag:
        raise ValueError('Release assets do not match the requested tag/commit')
    name = f'DeckScope-{manifest["version"]}-linux-x86_64.zip'
    if list(manifest['assets']) != [name] or set(p.name for p in folder.iterdir()) != {name, 'SHA256SUMS', 'build-manifest.json'}:
        raise ValueError('Unexpected release artifact contents')
    sums = []
    for filename in (name, 'build-manifest.json'):
        path = folder / filename
        if path.is_symlink() or not path.is_file():
            raise ValueError('Release asset must be a regular file')
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        sums.append(f'{digest}  {filename}\n')
        if filename == name and (manifest['assets'][name]['sha256'] != digest or manifest['assets'][name]['bytes'] != path.stat().st_size):
            raise ValueError('Package manifest checksum/size mismatch')
    if (folder / 'SHA256SUMS').read_text() != ''.join(sums):
        raise ValueError('Release checksums do not match')
    return manifest


def remote_commit(repo, tag):
    obj = json.loads(gh('api', f'repos/{repo}/git/ref/tags/{quote(tag, safe="")}'))['object']
    for _ in range(8):
        if obj['type'] == 'commit':
            return obj['sha']
        if obj['type'] != 'tag':
            break
        obj = json.loads(gh('api', f'repos/{repo}/git/tags/{obj["sha"]}'))['object']
    raise ValueError('Unable to resolve remote tag to a commit')


def publish(folder, repo, tag, commit):
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repo) or not re.fullmatch(r'v\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?', tag):
        raise ValueError('Invalid repository or tag')
    manifest = verify_assets(folder, tag, commit)
    if remote_commit(repo, tag) != commit:
        raise ValueError('Remote tag moved after the build; refusing publication')
    releases = json.loads(gh('api', '--paginate', '--slurp', f'repos/{repo}/releases?per_page=100'))
    release = next((r for page in releases for r in page if r['tag_name'] == tag), None)
    created = release is None
    marker = f'<!-- deckscope-ci:{commit} -->'
    owned_draft = bool(release and release.get('draft') and marker in (release.get('body') or ''))
    if created:
        notes = (f'Install **{next(iter(manifest["assets"]))}** with Decky Loader. '
                 'GitHub Source code archives are not installable plugin packages.\n\n'
                 f'Source commit: `{commit}`. SHA256SUMS and build-manifest.json accompany the package.\n\n'
                 'Read the repository compatibility and third-party notices before use. '
                 f'This is a GitHub sideload build, not Decky Store certification.\n\n{marker}')
        command = ['release', 'create', tag, '--repo', repo, '--verify-tag', '--draft', '--title', f'DeckScope {manifest["version"]}', '--notes', notes]
        if '-' in manifest['version']:
            command += ['--prerelease', '--latest=false']
        gh(*command)
        release = json.loads(gh('api', f'repos/{repo}/releases/tags/{quote(tag, safe="")}'))
    assets = {a['name']: a for a in release['assets']}
    for path in sorted(folder.iterdir()):
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        action = asset_decision(assets.get(path.name), digest)
        if action == 'verify-download':
            with tempfile.TemporaryDirectory(prefix='deckscope-asset-') as temp:
                gh('release', 'download', tag, '--repo', repo, '--pattern', path.name, '--dir', temp)
                if hashlib.sha256((Path(temp) / path.name).read_bytes()).hexdigest() != digest:
                    raise ValueError(f'Refusing to replace differing asset: {path.name}')
            action = 'skip'
        if action == 'upload':
            gh('release', 'upload', tag, str(path), '--repo', repo)
        print(f'{action}: {path.name}')
    if created or owned_draft:
        # Publishing only after all uploads also supports immutable-release repositories.
        command = ['release', 'edit', tag, '--repo', repo, '--draft=false']
        if '-' in manifest['version']:
            command += ['--prerelease', '--latest=false']
        gh(*command)
    elif release['draft']:
        print('Existing draft preserved; publish it when ready.')
    print(f'https://github.com/{repo}/releases/tag/{tag}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--assets', type=Path, required=True)
    parser.add_argument('--tag', required=True)
    parser.add_argument('--commit', required=True)
    parser.add_argument('--repo', default=os.environ.get('GITHUB_REPOSITORY'), required=not bool(os.environ.get('GITHUB_REPOSITORY')))
    args = parser.parse_args()
    publish(args.assets, args.repo, args.tag, args.commit)
