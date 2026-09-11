#!/usr/bin/env bash
set -euo pipefail
: "${DECK_HOST:?Set DECK_HOST=user@ip}"
[[ "$DECK_HOST" != -* && "$DECK_HOST" != *[[:space:]]* ]] || exit 2
ssh "$DECK_HOST" 'python3 -' <<'PY'
from pathlib import Path
logs = list((Path.home() / "homebrew/logs/DeckScope").glob("*.log"))
if not logs:
    raise SystemExit("No DeckScope logs found")
latest = max(logs, key=lambda p: p.stat().st_mtime)
print("\n".join(latest.read_text(errors="replace").splitlines()[-150:]))
PY
