#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" == --help ]]; then
  echo 'Usage: DECK_HOST=user@host bash scripts/logs.sh'
  echo 'Prints the last 150 lines of the newest DeckScope log. Review before sharing.'
  exit 0
fi
[[ "$#" == 0 ]] || { echo 'Unexpected arguments; use --help' >&2; exit 2; }
source scripts/lib/ssh-common.sh
scope_ssh "$DECK_HOST" 'python3 -' <<'PY'
from collections import deque
from pathlib import Path
logs = list((Path.home() / 'homebrew/logs/DeckScope').glob('*.log'))
if not logs:
    raise SystemExit('No DeckScope logs found')
latest = max(logs, key=lambda p: p.stat().st_mtime)
with latest.open(errors='replace') as stream:
    print(''.join(deque(stream, maxlen=150)), end='')
PY
