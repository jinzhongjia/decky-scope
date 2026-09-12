#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" == --help ]]; then
  echo 'Usage: DECK_HOST=user@host bash scripts/deploy.sh --confirm'
  echo 'Rebuilds the full package, backs up DeckScope, installs via sudo, and restarts plugin_loader.'
  echo 'Uses the matching debug-session control socket when available. See docs/DEPLOYMENT.md.'
  exit 0
fi
if [[ "${1:-}" != --confirm || "$#" != 1 ]]; then
  echo 'Deployment changes the plugin and restarts Decky Loader.' >&2
  echo 'With current authorization: DECK_HOST=user@host bash scripts/deploy.sh --confirm' >&2
  exit 2
fi
source scripts/lib/ssh-common.sh
bash scripts/package.sh
stage=$(scope_ssh "$DECK_HOST" 'mktemp -d /tmp/deckscope-deploy.XXXXXXXX')
[[ "$stage" =~ ^/tmp/deckscope-deploy\.[A-Za-z0-9]+$ ]] || { echo 'Invalid remote staging path' >&2; exit 1; }
cleanup() {
  # Only our validated mktemp directory is removed. BatchMode avoids prompting from an EXIT trap.
  scope_ssh -o BatchMode=yes "$DECK_HOST" "rm -rf -- '$stage'" || echo "Could not clean owned remote staging directory: $stage" >&2
}
trap cleanup EXIT
plugin_root=$(scope_ssh "$DECK_HOST" 'printf "%s/homebrew/plugins" "$HOME"')
scope_scp outputs/DeckScope-dev.zip scripts/install-remote.py "$DECK_HOST:$stage/"
remote=$(python3 - "$stage" "$plugin_root" <<'PY'
import shlex, sys
stage, root = sys.argv[1:]
print(shlex.join(['sudo', 'python3', stage + '/install-remote.py', stage + '/DeckScope-dev.zip', root]))
PY
)
# SSH and sudo prompt interactively when needed; passwords are never script arguments.
scope_ssh -t "$DECK_HOST" "$remote"
echo 'Deployment completed. Use scripts/device-check.sh and the scoped UI acceptance in docs/DEBUGGING.md.'
