#!/usr/bin/env python3
"""Own one private SSH/CDP tunnel and bounded sleep inhibitor; never enable CEF."""
import argparse
import json
import os
import re
import shlex
import subprocess
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_STATE = ROOT / '.work/debug/session.json'


def target(value):
    if not value or value.startswith('-') or not re.fullmatch(r'[A-Za-z0-9_.:@%\[\]-]+', value):
        raise argparse.ArgumentTypeError('Use an SSH alias or user@host; shell syntax is not allowed')
    return value


def port(value):
    value = int(value)
    if not 1024 <= value <= 65535:
        raise argparse.ArgumentTypeError('Local port must be 1024..65535')
    return value


def lifetime(value):
    value = int(value)
    if not 60 <= value <= 7200:
        raise argparse.ArgumentTypeError('Lifetime must be 60..7200 seconds')
    return value


def load(path):
    if path.is_symlink():
        raise ValueError('Refusing symlink session state')
    data = json.loads(path.read_text())
    target(data['host'])
    port(str(data['port']))
    if not re.fullmatch(r'deckscope-debug-[0-9a-f]+', data['unit']):
        raise ValueError('Invalid owned unit name')
    directory = Path(data['directory'])
    if directory.is_symlink() or not directory.name.startswith('deckscope-debug-'):
        raise ValueError('Invalid control directory')
    if Path(data['control']) != directory / 'control':
        raise ValueError('Invalid control socket')
    if directory.exists() and directory.stat().st_uid != os.getuid():
        raise ValueError('Control directory belongs to another user')
    return data


def save(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_symlink():
        raise ValueError('Refusing symlink session state')
    fd, temporary = tempfile.mkstemp(prefix='.session-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as f:
            json.dump(data, f, indent=2)
            f.write('\n')
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def ssh(data, *args, capture=False, reconnect=False):
    options = ['ssh', '-o', 'ConnectTimeout=8', '-o', 'ServerAliveInterval=15', '-o', 'ServerAliveCountMax=2']
    if not reconnect:
        options += ['-S', data['control']]
    return subprocess.run(options + list(args), check=True, text=True, capture_output=capture)


def remote(data, argv, capture=False, reconnect=False):
    return ssh(data, data['host'], shlex.join(argv), capture=capture, reconnect=reconnect)


def start(args):
    if args.state.exists():
        raise ValueError('A recorded session exists; inspect status or stop it before starting another')
    host = target(args.host or os.environ.get('DECK_HOST', ''))
    directory = Path(tempfile.mkdtemp(prefix='deckscope-debug-'))
    data = {'host': host, 'port': args.port, 'directory': str(directory), 'control': str(directory / 'control'),
            'unit': 'deckscope-debug-' + os.urandom(6).hex(), 'ttl': args.ttl,
            'created_at': int(time.time()), 'expires_at': int(time.time()) + args.ttl}
    save(args.state, data)
    try:
        ssh(data, '-M', '-o', 'ControlPersist=600', '-o', 'ExitOnForwardFailure=yes', '-fNT',
            '-L', f'127.0.0.1:{args.port}:127.0.0.1:8080', host)
        remote(data, ['systemd-run', '--user', '--unit=' + data['unit'], '--collect',
                      '--property=RuntimeMaxSec=' + str(args.ttl), 'systemd-inhibit', '--what=idle:sleep',
                      '--mode=block', '--who=' + data['unit'], '--why=DeckScope development', 'sleep', str(args.ttl)])
        print(f'Session recorded: {args.state}')
        print(f'export DECK_CDP_URL=http://127.0.0.1:{args.port}')
        print('Run status once to verify the inhibitor; use stop when finished.')
    except BaseException:
        print(f'Start was incomplete. State preserved at {args.state}; run stop to clean up.')
        raise


def status(args):
    data = load(args.state)
    ssh(data, '-O', 'check', data['host'])
    remote(data, ['systemctl', '--user', 'show', data['unit'] + '.service', '-p', 'ActiveState', '-p', 'SubState'])
    result = remote(data, ['env', 'COLUMNS=400', 'systemd-inhibit', '--list', '--no-pager'], capture=True)
    owned = [line for line in result.stdout.splitlines() if data['unit'] in line]
    print('\n'.join(owned) if owned else 'Owned inhibitor not present (it may have expired).')
    print('Local CDP URL:', f'http://127.0.0.1:{data["port"]}')
    print('Bounded inhibitor expiry (Unix UTC):', data['expires_at'])
    if not owned:
        raise RuntimeError('No owned inhibitor; do not assume the device will stay awake')


def stop(args):
    if not args.state.exists():
        print('No recorded session; nothing to stop.')
        return
    data = load(args.state)
    # A dead tunnel may reconnect through normal SSH authentication; never change host-key policy.
    reconnect = not Path(data['control']).exists()
    try:
        unit = data['unit'] + '.service'
        command = ('if systemctl --user show ' + shlex.quote(unit) + ' -p LoadState --value | grep -qx not-found; '
                   'then :; else systemctl --user stop ' + shlex.quote(unit) + '; fi')
        ssh(data, data['host'], command, reconnect=reconnect)
        result = remote(data, ['env', 'COLUMNS=400', 'systemd-inhibit', '--list', '--no-pager'], capture=True, reconnect=reconnect)
        if data['unit'] in result.stdout:
            raise RuntimeError('Owned inhibitor is still present')
    except BaseException:
        # Keep the state/control socket so stop is retryable. The remote unit still has its hard TTL.
        print(f'Remote cleanup not confirmed; state retained at {args.state}. The inhibitor has a bounded lifetime.')
        raise
    if Path(data['control']).exists():
        ssh(data, '-O', 'exit', data['host'])
    # The private directory holds only this task's control socket; do not remove arbitrary trees.
    directory = Path(data['directory'])
    if directory.exists():
        leftovers = list(directory.iterdir())
        if leftovers:
            raise RuntimeError('Control directory not empty; state retained for inspection')
        directory.rmdir()
    args.state.unlink()
    print('Owned inhibitor released, tunnel closed, session state removed.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--state', type=Path, default=Path(os.environ.get('DECK_DEBUG_STATE', DEFAULT_STATE)))
    sub = parser.add_subparsers(dest='command', required=True)
    begin = sub.add_parser('start', help='Start an explicitly requested local debug session')
    begin.add_argument('--host')
    begin.add_argument('--port', type=port, default=8080)
    begin.add_argument('--ttl', type=lifetime, default=1800)
    sub.add_parser('status', help='One-shot ownership and inhibitor check')
    sub.add_parser('stop', help='Release only the recorded session resources')
    socket = sub.add_parser('socket', help='Print matching control path for project shell scripts')
    socket.add_argument('--host', required=True, type=target)
    args = parser.parse_args()
    if args.command == 'socket':
        if args.state.exists():
            data = load(args.state)
            if data['host'] != args.host:
                raise ValueError('DECK_HOST does not match the recorded debug session')
            if Path(data['control']).exists():
                print(data['control'])
        return
    {'start': start, 'status': status, 'stop': stop}[args.command](args)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, RuntimeError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error))
