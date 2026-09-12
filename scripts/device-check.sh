#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" == --help ]]; then
  echo 'Usage: DECK_HOST=user@host bash scripts/device-check.sh'
  echo 'Reads model, OS, Loader state, installed hashes and Decky directory metadata. No restart or socket connection.'
  exit 0
fi
[[ "$#" == 0 ]] || { echo 'Unexpected arguments; use --help' >&2; exit 2; }
source scripts/lib/ssh-common.sh
scope_ssh "$DECK_HOST" python3 - <<'PY'
import hashlib, json, stat, subprocess
from pathlib import Path
home = Path.home()
plugin = home / 'homebrew/plugins/DeckScope'
def text(path):
    try: return path.read_text().strip()
    except OSError: return None
hashes = {}
for name in ('main.py', 'plugin.json', 'dist/index.js', 'bin/deckscope-monitor'):
    path = plugin / name
    hashes[name] = hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None
loader = subprocess.run(['systemctl', 'is-active', 'plugin_loader'], text=True, capture_output=True)
metadata = []
for base in (home / 'homebrew/data/DeckScope', home / 'homebrew/settings/DeckScope'):
    if base.exists():
        metadata.append({'path': str(base.relative_to(home)), 'mode': oct(stat.S_IMODE(base.stat().st_mode))})
print(json.dumps({'board': text(Path('/sys/class/dmi/id/board_name')), 'kernel': text(Path('/proc/sys/kernel/osrelease')),
                  'loader': loader.stdout.strip(), 'installed_sha256': hashes, 'decky_directory_modes': metadata}, indent=2))
if loader.returncode or not all(hashes.values()):
    raise SystemExit('Loader inactive or installed package incomplete')
PY
