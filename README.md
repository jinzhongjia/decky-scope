# DeckScope / decky-scope

**rc.3:** grouped monitoring curves, recording coverage, storage capacity, battery details and OS runtime are implemented. Local regression and an isolated native device snapshot pass; installed rc.3 QAM acceptance is pending. See [feature notes](docs/FEATURES-RC3.md).

**Read-only SteamOS diagnostics and performance history, entirely inside Decky QAM.** The current private candidate is `0.1.0-rc.3`. A static Zig 0.16 monitor owns collection and history, a Python-standard-library bridge owns lifecycle/RPC, and a React/TypeScript UI presents Monitor, System and Settings views. There is no separate fullscreen route.[1]

The approved native UI and directional-key navigation are retained. Touchscreen investigation was stopped at the user's request; the reported obstruction is not claimed to be fixed. Device evidence is limited to one Steam Deck OLED plus local fixtures. **This is not a public release or cross-device production certification.**

## Start here

| Goal | Guide |
| --- | --- |
| Build and contribute | [Development](docs/DEVELOPMENT.md) |
| Install or roll back on an authorized device | [Deployment](docs/DEPLOYMENT.md) |
| Inspect logs, operate QAM or verify D-pad access | [Debugging](docs/DEBUGGING.md) |
| Understand the protocol and stored data | [Protocol](docs/PROTOCOL.md) |
| Check known hardware and feature limits | [Compatibility](docs/COMPATIBILITY.md) |
| Review release blockers | [Release preparation](docs/RELEASE.md) |
| Browse all current guides and historical evidence | [Documentation index](docs/README.md) |

All required developer scripts now live in this repository. No sibling checkout, external Agent Skill, or pre-existing `.work/` content is needed. Documentation and tool help are English-first; the UI has Simplified Chinese and English strings.

## Local quick start

Use Linux x86_64, Zig `0.16.x`, Python `3.10+`, Node `22+`, pnpm `11.3.0`, `file` and binutils. Open a terminal in this repository, then run:

```bash
pnpm install --frozen-lockfile
bash scripts/check.sh
```

This builds and tests the project and writes `outputs/DeckScope-dev.zip`. It does not connect to a device or deploy. The complete command performs both ReleaseSmall and ReleaseSafe regressions, frontend/tool tests, type checking and documentation validation. See [Development](docs/DEVELOPMENT.md) for individual commands and generated paths.

## Device workflow

The target must be explicit and currently authorized. `user@host` is a placeholder:

```bash
export DECK_HOST=user@host
python3 scripts/debug-session.py start --ttl 1800
python3 scripts/debug-session.py status
node scripts/cdp.mjs targets
# Only when installation and a Loader restart are authorized:
bash scripts/deploy.sh --confirm
bash scripts/device-check.sh
bash scripts/logs.sh
python3 scripts/debug-session.py stop
```

The session owns a loopback-only SSH/CDP tunnel and a bounded sleep inhibitor. The deployer always rebuilds, installs via sudo, and keeps the previous plugin outside Decky's scan directory. It does not change permanent SSH/CEF, power or fan settings. Read [Deployment](docs/DEPLOYMENT.md) and [Debugging](docs/DEBUGGING.md) before using the mutation or UI commands.

## Features and boundaries

The QAM contains real CPU/GPU and APU-or-battery power charts, SteamOS/kernel/hardware information, local SSH/CEF listener state, masked IP and summary copying, and sampling settings. Closing the UI stops live pushing, not background collection. The monitor records available CPU, memory, sensor, battery, PSI and I/O metrics with explicit missing-value handling. Battery and package power are not total-system consumption.[1] [2]

Seven-day, day-granularity persistence uses checksummed schema-v1 records and batched writes; abrupt loss can discard unflushed data. Dedicated non-AMD collectors, automatic game sessions, full chart cursor/zoom and broader device/performance certification remain deferred. The [compatibility guide](docs/COMPATIBILITY.md) preserves the detailed implementation and evidence limits.

## Source map and provenance

`monitor/src/` owns native collection and storage; `py_modules/` and `main.py` own the bridge; `src/` owns the QAM; `scripts/` and `tests/` own development workflows. `docs/` separates current guides from immutable historical evidence. Generated binaries, packages, local session state and scratch files are ignored by Git.

The original user-supplied technical proposal and demo informed the low-level runtime and monitor baseline. Earlier local projects informed the bridge, Decky controls and CDP development helpers. The adapted helpers are now maintained locally under `scripts/lib/` and `scripts/probes/`; historical provenance is not a runtime/build dependency. License and reference-code redistribution rights still require review before public distribution.[3]

## References

[1]: docs/DESIGN.md "DeckScope architecture and product boundaries"
[2]: docs/PROTOCOL.md "Protocol, units, persistence and privacy semantics"
[3]: docs/RELEASE.md "Private candidate and unresolved public-release requirements"
