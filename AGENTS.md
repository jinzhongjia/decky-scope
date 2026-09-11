# DeckScope development rules

## Product boundary

Target SteamOS, not only Steam Deck. Steam Deck LCD (Jupiter) and OLED (Galileo) are known profiles, never prerequisites. Discover CPU topology, DRM devices, hwmon and batteries by capabilities. Unknown hardware must degrade honestly: omit unavailable values; do not invent zero readings. A successful OLED test is not LCD or general SteamOS certification.

## Architecture

React UI communicates only through `src/api.ts` with the stdlib-only Python bridge. The Zig 0.16 monitor owns sampling and history. Use direct Linux syscalls, no libc, no shell execution or external network calls in the monitor. UI closed means live metrics disabled. Never collect credentials, MAC/SSID, Steam IDs, serial numbers or other processes' environment.

Name flat Python plugin modules with the `deckscope_` prefix. Decky's frozen runtime can preload generic names such as `settings`, `protocol` and `bridge`; never rely on sys.path order to override those modules. Keep the preloaded-host-module regression test.

## Workflow

Read `docs/DESIGN.md` before implementation changes. Keep source modules focused (prefer <500 lines). Run Zig, Python and frontend tests after changes. Do not claim unrun device or performance tests. UI requires actual SteamOS/Decky validation before release; local builds are not visual acceptance.

The user authorizes local commits after each completed and verified stage, with meaningful rollback points on `main`. Use scoped Conventional Commits with Chinese subjects. Do not push without explicit permission. On 2026-09-12 the user temporarily pre-authorized sideloads and required `plugin_loader` restarts during the current idle-device debugging period; do not ask before every iteration. Attach a task-owned temporary sleep inhibitor during device debugging, bound its lifetime, and release it when finished. Reconfirm if the device is in use, the target changes, or unrelated device configuration changes are needed. Device addresses are discovered or passed via `DECK_HOST`, never embedded in reusable code. Passwords must never appear in source, settings, logs or Git; use an interactive SSH/sudo prompt or an external credential channel. Do not copy unrelated project-specific deployment cleanup commands.

Document deliberately deferred functionality and compatibility limits. Use English diagnostic logs with no sensitive payloads. Do not silently acknowledge unimplemented protocol operations as successful.

The user additionally authorized functional acceptance on 2026-09-12: Steam CEF plugin navigation, directional/confirm input, settings/clipboard checks, and bounded monitor-only exit injection are within scope for the current idle-device period. Keep original screenshots and distinguish synthetic input from physical-controller or suspend/network testing. Read `docs/DEVICE-ACCEPTANCE.md` before repeating already-completed acceptance.
