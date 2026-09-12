# DeckScope development rules

## Product boundary

Target SteamOS, not only Steam Deck. Steam Deck LCD (Jupiter) and OLED (Galileo) are known profiles, never prerequisites. Discover CPU topology, DRM devices, hwmon and batteries by capabilities. Unknown hardware must degrade honestly: omit unavailable values; do not invent zero readings. A successful OLED test is not LCD or general SteamOS certification.

The user clarified on 2026-09-12 that the product is QAM-only: no independent fullscreen UI or navigation entry. Keep CPU/GPU/power trend charts and professional system information (kernel, SteamOS version/build, IP, hardware) inside QAM. Do not reduce it to a numbers-only widget.

On 2026-09-12 at 17:45 the user rejected the dense Monitor layout. Default to one selected metric and one clear chart; keep the full metric catalog accessible through progressive selection. Recording integrity and explanatory details should be collapsed by default. Do not replace density with smaller text or a wall of equally weighted controls.

The 18:21 direction adopts a two-level metric picker: category navigation and concrete metric options must never share a level. Open directly in the selected metric category, provide an explicit Back to categories action, and retain the single-chart Monitor default.

## Architecture

React UI communicates only through `src/api.ts` with the stdlib-only Python bridge. The Zig 0.16 monitor owns sampling and history. Use direct Linux syscalls, no libc, no shell execution or external network calls in the monitor. UI closed means live metrics disabled. Never collect credentials, MAC/SSID, Steam IDs, serial numbers or other processes' environment.

Name flat Python plugin modules with the `deckscope_` prefix. Decky's frozen runtime can preload generic names such as `settings`, `protocol` and `bridge`; never rely on sys.path order to override those modules. Keep the preloaded-host-module regression test.

## Self-contained developer workflow

Use this repository's `docs/README.md`, `docs/DEVELOPMENT.md`, `docs/DEPLOYMENT.md` and `docs/DEBUGGING.md`. Do not depend on a sibling checkout, external Agent Skill, or pre-existing `.work/` scripts. Operational documentation, tool help and diagnostics are English-first. Preserve the bilingual UI and original-language evidence rather than silently rewriting observation data.

Use `scripts/debug-session.py` for the owned loopback tunnel and bounded inhibitor; always stop it when finished. Use `scripts/cdp.mjs`, `scripts/check-dpad.mjs`, `scripts/device-check.sh` and `scripts/logs.sh` for scoped checks. Use `scripts/deploy.sh --confirm` or `scripts/rollback.sh --confirm` only with current authorization. Do not replace Decky's plugin event map through `connect(...)`, use CDP hacks in shipped code, or alter host security settings to make tests pass.

The user stopped touchscreen-specific investigation at 11:16 on 2026-09-12. Preserve the approved rc.2 native appearance and ensure directional-key access to all views and enabled controls. Do not resume touch diagnosis or add touch/scroll workarounds without a new request; no host root cause has been established. CEF synthetic input is not physical-control certification.

## Workflow

Read `docs/DESIGN.md` before implementation changes. Keep source modules focused (prefer <500 lines). Run Zig, Python and frontend tests after changes. Do not claim unrun device or performance tests. UI requires actual SteamOS/Decky validation before release; local builds are not visual acceptance.

The user authorizes local commits after each completed and verified stage, with meaningful rollback points on `main`. Use scoped Conventional Commits with Chinese subjects. Do not push without explicit permission. On 2026-09-12 the user temporarily pre-authorized sideloads and required `plugin_loader` restarts during the current idle-device debugging period; do not ask before every iteration. Attach a task-owned temporary sleep inhibitor during device debugging, bound its lifetime, and release it when finished. Reconfirm if the device is in use, the target changes, or unrelated device configuration changes are needed. Device addresses are discovered or passed via `DECK_HOST`, never embedded in reusable code. Passwords must never appear in source, settings, logs or Git; use an interactive SSH/sudo prompt or an external credential channel. Do not copy unrelated project-specific deployment cleanup commands.

Document deliberately deferred functionality and compatibility limits. Use English diagnostic logs with no sensitive payloads. Do not silently acknowledge unimplemented protocol operations as successful.

The user additionally authorized functional acceptance on 2026-09-12: Steam CEF plugin navigation, directional/confirm input, settings/clipboard checks, and bounded monitor-only exit injection are within scope for the current idle-device period. Keep original screenshots and distinguish synthetic input from physical-controller or suspend/network testing. Read `docs/VALIDATION.md` and the relevant dated record before repeating already-completed acceptance. Historical permission notes are not permanent authorization for a new target or session.

At 03:19 the user explicitly authorized continuing all sideload iterations autonomously while they sleep. Use the established sudo-backed full installer for root-owned plugin files, retain backups, and do not try direct unprivileged frontend writes. This does not authorize public publishing, pushing, or changing permanent system settings.

The user prefers repository-only delivery: make and verify changes in this Git checkout and report the outcome/commit concisely. Do not repeatedly attach source or installation ZIPs unless requested. Build ZIPs used internally for authorized sideloading are not user deliverables.
