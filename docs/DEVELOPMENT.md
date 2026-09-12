# Development

**A checkout of this repository is the only project source required.** Use the pinned package manager and Zig compiler family, and do not depend on scripts outside this tree. The runtime architecture remains Zig sampling/history, a Python-standard-library control plane, and a React QAM UI.[1]

## Prerequisites

| Tool | Requirement and use |
| --- | --- |
| Host OS | Linux x86_64 is the supported development path |
| Zig | `0.16.x`; required by the native build and tests |
| Python | `3.10+`; standard library only for bridge and developer scripts |
| Node.js | `22+` with built-in `fetch` and `WebSocket`; a current maintained release is recommended |
| pnpm | `11.3.0`, as pinned by `package.json` |
| Native inspection | `file`, `readelf` from binutils, and GNU `stat` |
| Device workflows | OpenSSH client, an authorized SSH target and sudo rights for installation |
| Optional discovery | `getent`, `ip`, and `avahi-browse` for local hostname/neighbor discovery |

Check the actual versions with `zig version`, `python3 --version`, `node --version` and `pnpm --version`. The official Decky store template currently describes a different pnpm/backend build contract; this local toolchain is not a claim of store-CI compatibility.[2]

## Build and test

Run these commands from the repository root:

```bash
pnpm install --frozen-lockfile
bash scripts/check.sh
```

The unified check builds Zig tests and ReleaseSmall/ReleaseSafe binaries, verifies that the release ELF is static and below the current size ceiling, runs Python tests against both builds, runs TypeScript and Node tests, builds the frontend, validates documentation, and creates the development ZIP. It does not connect to a device, operate Steam UI, or install anything.

| Command | Result |
| --- | --- |
| `bash scripts/build-monitor.sh` | `bin/deckscope-monitor` and symbol-preserving `monitor/zig-debug/bin/deckscope-monitor` |
| `pnpm typecheck` | Frontend type checking without emitting a bundle |
| `pnpm test:ui` | Frontend contract/logic tests plus offline Node developer-tool tests |
| `python3 -m unittest discover -s tests -v` | Bridge, monitor integration and offline deployment-tool tests |
| `python3 scripts/check-docs.py` | Local Markdown links and repository-independent script checks |
| `bash scripts/package.sh` | Fresh Zig and frontend build, then `outputs/DeckScope-dev.zip` |
| `python3 scripts/package-candidate.py` | Version-named private candidate and checksum after successful preflight |

`package.py` packages already-built inputs; prefer `package.sh` or `check.sh` to avoid stale binaries. Neither the development ZIP nor the candidate includes developer tools, documentation, `.work/`, tests, credentials, settings, or a `dev_mode` marker. The sideload installer creates that marker on the device.[3]

## Source ownership

| Path | Responsibility |
| --- | --- |
| `monitor/src/` | Sampling, parsers, capability discovery, rtnetlink, history, persistence and native transport |
| `py_modules/deckscope_*.py` | Supervision, bounded RPC, private settings and redacted export |
| `main.py` | The six-method Decky callable facade |
| `src/api.ts` | The frontend's only bridge contract |
| `src/live.ts`, `src/trends.ts` | Consumer lifecycle and bounded time-series state |
| `src/*Pane.tsx`, `src/Controls.tsx` | QAM views and native focus groups |
| `scripts/` | Self-contained developer commands; never shipped into the runtime plugin |
| `tests/` | Fixtures, integration tests and offline helper tests |

Flat Python module names must retain the `deckscope_` prefix. Decky's frozen runtime can preload generic names such as `settings`; import-path ordering is not a safe isolation mechanism. Never put sampling, shell commands, credentials or network uploads into the frontend/bridge as a shortcut.[1]

The monitor takes `<uds_socket_path> <history_directory> [fixture_root]`. It is a UNIX-socket client; a compatible server must already exist. Use `tests/support.py` to launch it in a local fixture rather than connecting a second client to the installed plugin's private socket.

## UI and language conventions

Preserve the approved native rc.2 appearance. Use native `Field`, `PanelSection`, `PanelSectionRow` and `DialogButton` components. A visual flex row alone does not create horizontal gamepad navigation: action pairs must have a native horizontal `Focusable` parent. Every view and enabled action must remain reachable through directional and confirm input.

`src/i18n.ts` selects Simplified Chinese for CEF language tags beginning with `zh`, and English otherwise. There is no independent language selector. The existing crash-boundary fallback still has one fixed English sentence; do not claim complete translation coverage until it is addressed. Technical identifiers and units remain literal.

Touchscreen-specific investigation was stopped at the user's request. Preserve ordinary host scrolling, do not add interception or focus/scroll workarounds, and do not label the unresolved touch behavior as fixed. CEF key injection is useful evidence, but is not physical-controller or physical-finger certification.

## Contribution workflow

Read `AGENTS.md`, then the relevant current guide. Keep modules focused, update tests and protocol documentation with behavior changes, and commit verified stages on `main` using the repository's scoped Conventional Commit convention. Do not push, tag, publish or select a license without appropriate authorization. Debug-session and deployment commands require a currently authorized target; an old acceptance report is not permanent consent.[1]

## References

[1]: ../AGENTS.md "DeckScope development and safety rules"
[2]: RELEASE.md "Local toolchain versus official store release requirements"
[3]: ../scripts/package.py "Development ZIP allowlist and permissions"
