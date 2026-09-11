#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" != --confirm ]]; then
  echo 'Deployment changes the plugin and restarts Decky Loader.' >&2
  echo 'After explicit approval: DECK_HOST=user@ip bash scripts/deploy.sh --confirm' >&2
  exit 2
fi
: "${DECK_HOST:?Set DECK_HOST=user@ip; no target is hardcoded}"
[[ "$DECK_HOST" != -* && "$DECK_HOST" != *[[:space:]]* ]] || exit 2
bash scripts/package.sh
stage=$(ssh "$DECK_HOST" 'mktemp -d /tmp/deckscope-deploy.XXXXXXXX')
[[ "$stage" =~ ^/tmp/deckscope-deploy\.[A-Za-z0-9]+$ ]] || { echo 'Invalid remote staging path' >&2; exit 1; }
plugin_root=$(ssh "$DECK_HOST" 'printf "%s/homebrew/plugins" "$HOME"')
scp outputs/DeckScope-dev.zip scripts/install-remote.py "$DECK_HOST:$stage/"
remote=$(python3 - "$stage" "$plugin_root" <<'PY'
import shlex, sys
stage, root = sys.argv[1:]
print(shlex.join(['sudo', 'python3', stage + '/install-remote.py', stage + '/DeckScope-dev.zip', root]))
PY
)
# SSH and sudo prompt interactively if necessary; no password enters code/argv/logs.
ssh -t "$DECK_HOST" "$remote"
echo 'Deployment completed. Verify the real SteamOS UI and capture current screenshots before release.'
