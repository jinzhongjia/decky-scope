#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build-monitor.sh
pnpm typecheck
pnpm build
python3 scripts/package.py
