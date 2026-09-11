#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build-monitor.sh
python3 -m unittest discover -s tests -v
MONITOR_BINARY="$PWD/monitor/zig-debug/bin/deckscope-monitor" python3 -m unittest discover -s tests -v
pnpm typecheck
pnpm test:ui
pnpm build
python3 scripts/package.py
