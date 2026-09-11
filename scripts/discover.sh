#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${1:-}" ]]; then
  [[ "$1" != -* && "$1" != *[[:space:]]* ]] || exit 2
  getent ahostsv4 "$1"
else
  echo 'Known local neighbors (not a network scan):'
  ip neigh
  echo 'For a known hostname: bash scripts/discover.sh steamdeck.local'
  if command -v avahi-browse >/dev/null; then
    timeout 8 avahi-browse -rt _ssh._tcp || true
  fi
fi
