#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(zig version)" == 0.16.* ]] || { echo 'Zig 0.16.x is required' >&2; exit 2; }
(cd monitor && zig build test && zig build -Doptimize=ReleaseSmall && zig build -Doptimize=ReleaseSafe --prefix zig-debug)
file monitor/zig-out/bin/deckscope-monitor
if readelf -d monitor/zig-out/bin/deckscope-monitor | grep -q NEEDED; then
  echo 'Unexpected dynamic dependency' >&2; exit 1
fi
if readelf -l monitor/zig-out/bin/deckscope-monitor | grep -q INTERP; then
  echo 'Unexpected ELF interpreter' >&2; exit 1
fi
test "$(stat -c %s monitor/zig-out/bin/deckscope-monitor)" -lt 262144
mkdir -p bin
install -m 755 monitor/zig-out/bin/deckscope-monitor bin/deckscope-monitor
