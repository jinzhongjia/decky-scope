#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == --help ]]; then
  echo 'Usage: bash scripts/discover.sh [hostname]'
  echo 'Resolves a known IPv4 hostname, or shows cached neighbor addresses and optional SSH mDNS services.'
  echo 'No subnet scan, login attempt, or saved target. Verify device identity before deployment.'
  exit 0
fi
[[ "$#" -le 1 ]] || { echo 'Unexpected arguments; use --help' >&2; exit 2; }
if [[ -n "${1:-}" ]]; then
  [[ "$1" != -* && "$1" =~ ^[A-Za-z0-9_.:-]+$ ]] || { echo 'Invalid hostname' >&2; exit 2; }
  getent ahostsv4 "$1"
else
  echo 'Cached local neighbor addresses and interfaces (not a network scan):'
  ip -o neigh show | awk '{print $1, $3}'
  echo 'For a known hostname: bash scripts/discover.sh steamdeck.local'
  if command -v avahi-browse >/dev/null; then
    timeout 8 avahi-browse -rt _ssh._tcp || true
  fi
fi
