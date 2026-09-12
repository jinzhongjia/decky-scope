#!/usr/bin/env bash
# Source from project scripts after processing --help. Never source session JSON.
SCOPE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
: "${DECK_HOST:?Set DECK_HOST to an SSH alias or user@host}"
# This command validates the target even when no session state exists.
SCOPE_CONTROL="$(python3 "$SCOPE_ROOT/scripts/debug-session.py" socket --host "$DECK_HOST")"
SCOPE_SSH_OPTIONS=(-o ConnectTimeout=8 -o ServerAliveInterval=15 -o ServerAliveCountMax=2)
SCOPE_SCP_OPTIONS=(-o ConnectTimeout=8)
if [[ -n "$SCOPE_CONTROL" ]]; then
  SCOPE_SSH_OPTIONS+=(-S "$SCOPE_CONTROL")
  SCOPE_SCP_OPTIONS+=(-o "ControlPath=$SCOPE_CONTROL")
fi
scope_ssh() { ssh "${SCOPE_SSH_OPTIONS[@]}" "$@"; }
scope_scp() { scp "${SCOPE_SCP_OPTIONS[@]}" "$@"; }
