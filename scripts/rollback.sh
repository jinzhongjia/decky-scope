#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" == --help ]]; then
  echo 'Usage: DECK_HOST=user@host bash scripts/rollback.sh --confirm DeckScope-TIMESTAMP'
  echo 'Restores exactly one backup from homebrew/deckscope-backups and restarts plugin_loader.'
  exit 0
fi
[[ "$#" == 2 && "$1" == --confirm && "$2" =~ ^DeckScope-[0-9]+$ ]] || { echo 'Explicit --confirm and a DeckScope-TIMESTAMP backup name are required' >&2; exit 2; }
backup="$2"
source scripts/lib/ssh-common.sh
stage=$(scope_ssh "$DECK_HOST" 'mktemp -d /tmp/deckscope-deploy.XXXXXXXX')
[[ "$stage" =~ ^/tmp/deckscope-deploy\.[A-Za-z0-9]+$ ]] || exit 1
cleanup() { scope_ssh -o BatchMode=yes "$DECK_HOST" "rm -rf -- '$stage'" || echo "Staging cleanup unconfirmed: $stage" >&2; }
trap cleanup EXIT
root=$(scope_ssh "$DECK_HOST" 'printf "%s/homebrew/plugins" "$HOME"')
scope_scp scripts/install-remote.py "$DECK_HOST:$stage/"
remote=$(python3 - "$stage" "$root" "$backup" <<'PY'
import shlex,sys
stage,root,backup=sys.argv[1:]
print(shlex.join(['sudo','python3',stage+'/install-remote.py','--rollback',root,backup]))
PY
)
scope_ssh -t "$DECK_HOST" "$remote"
