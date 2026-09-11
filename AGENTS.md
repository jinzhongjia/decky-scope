# DeckScope development rules

## Product boundary

Target SteamOS, not only Steam Deck. Steam Deck LCD (Jupiter) and OLED (Galileo) are known profiles, never prerequisites. Discover CPU topology, DRM devices, hwmon and batteries by capabilities. Unknown hardware must degrade honestly: omit unavailable values; do not invent zero readings. A successful OLED test is not LCD or general SteamOS certification.

## Architecture

React UI communicates only through `src/api.ts` with the stdlib-only Python bridge. The Zig 0.16 monitor owns sampling and history. Use direct Linux syscalls, no libc, no shell execution or external network calls in the monitor. UI closed means live metrics disabled. Never collect credentials, MAC/SSID, Steam IDs, serial numbers or other processes' environment.

## Workflow

Read `docs/DESIGN.md` before implementation changes. Keep source modules focused (prefer <500 lines). Run Zig, Python and frontend tests after changes. Do not claim unrun device or performance tests. UI requires actual SteamOS/Decky validation before release; local builds are not visual acceptance.

The user authorizes local commits after each completed and verified stage, with meaningful rollback points on `main`. Use scoped Conventional Commits with Chinese subjects. Do not push without explicit permission. Ask before deployment, service restart or device configuration changes. Device addresses are discovered or passed via `DECK_HOST`, never embedded in reusable code. Passwords must never appear in source, settings, logs or Git; use an interactive SSH/sudo prompt or an external credential channel. Do not copy unrelated project-specific deployment cleanup commands.

Document deliberately deferred functionality and compatibility limits. Use English diagnostic logs with no sensitive payloads. Do not silently acknowledge unimplemented protocol operations as successful.
