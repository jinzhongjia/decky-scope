# Validation Record

## Public alpha packaging — September 17, 2026

`0.1.0-alpha.1` changes the package/native version and release documentation, not the runtime behavior or UI. Frozen dependency installation and `bash scripts/check.sh` pass: Zig tests and ReleaseSmall/ReleaseSafe builds, 55 Python tests per build, 28 frontend/tooling tests, TypeScript, Rollup, ELF constraints, documentation, and ZIP creation. Package allowlist/content/permission verification also passes.

A local smoke run extracted the native executable from the alpha ZIP and exercised its UNIX-socket protocol against a synthetic Galileo fixture. `get_status` and `get_device_info` both reported `0.1.0-alpha.1`; live pushes remained disabled without a consumer, a bounded recent-history query returned recorded data, and flushing succeeded. This is packaged-runtime verification, not a new SteamOS/Decky UI acceptance run. Earlier device records below retain their original versions and hashes.

The public [prerelease](https://github.com/jinzhongjia/decky-scope/releases/tag/v0.1.0-alpha.1) points to `98f661b981af7b0d02700db2d039073826baabe8`. The [tag build](https://github.com/jinzhongjia/decky-scope/actions/runs/35192105710) passed testing and packaging, then exposed a draft lookup bug. Recovery used its original hosted artifacts, not a local rebuild. The public ZIP is 104,598 bytes with SHA-256 `0dc67f9d17b144b45ed4c9401ec0d4224c46a12691d2d37e6cb1f262bdd1377a`. All three public assets were downloaded again; `SHA256SUMS` passed, and an idempotent publisher run skipped every identical asset without overwriting. The hosted ZIP also passed the native smoke described above.

The subsequent [Release-event run](https://github.com/jinzhongjia/decky-scope/actions/runs/35192962047) passed both build and publication jobs. The initial tag run's failed-job-only rerun exposed a separate artifact-name/run-attempt mismatch. Both defects are fixed on `main`: drafts are found through the authenticated release list, and publication consumes the successful build's artifact ID. The existing alpha tag was not moved. After the source fix, full local checks pass with 54 Python tests per build and 28 frontend/tooling tests; one source-text-only workflow test was removed. The draft regression failed before the fix and passed afterward, and `actionlint` 1.7.12 validates the revised workflow. This does not claim that the revised failed-job-only path has itself been exercised in hosted CI.

## Earlier tooling and UI baseline

**Earlier tooling revision:** [GitHub packaging CI](CI-RELEASE.md) passed local official-Zig/frozen-lockfile checks, 46 Zig tests, 55 Python tests per native build and 28 frontend/tooling tests. At that stage, release network actions were mocked locally; the public alpha record above adds hosted publication evidence.

**Latest UI revision:** the two-level metric picker passes installed QAM checks and 28 frontend/tooling tests. The native monitor is unchanged. See [two-level picker acceptance](TWO-LEVEL-PICKER.md) for current screenshots and navigation results.

## rc.3 current development candidate

[rc.3 feature notes](FEATURES-RC3.md) supersede the older current-candidate label below. The new native snapshots were verified in an isolated temporary process on Galileo; the revised candidate subsequently passed installed QAM and CEF directional-key checks; see [rc.3 device acceptance](RC3-ACCEPTANCE.md). Full local regression passes with 46 Zig tests, 42 Python tests per native build and 22 frontend/tooling tests. Physical suspend/SD-card transitions remain untested. Earlier records below remain historical evidence.

**Current runtime candidate: `0.1.0-rc.2`. Latest maintenance verification: 2026-09-12, approximately 13:16–13:17 UTC+8.** The documentation/tooling consolidation did not change `src/`, `main.py`, `py_modules/`, `monitor/`, `plugin.json` or `package.json`. It did not sideload or restart Loader. This record distinguishes offline checks, read-only device checks and earlier UI acceptance.[1]

## Latest self-contained workflow verification

| Check | Observed result and scope |
| --- | --- |
| Zig unit tests/build | Passed; the existing 22-test native baseline is unchanged |
| Python tests / ReleaseSmall | 36 passed, including 10 developer-tool tests |
| Python tests / ReleaseSafe | The same 36 tests passed against the runtime-checked binary; not 36 additional distinct tests |
| Node tests | 16 passed: 12 frontend tests and 4 CDP/tool tests |
| TypeScript, Rollup and ELF checks | Passed |
| Documentation and source paths | Local links resolved; no sibling-project imports or developer-specific absolute paths in executable project source |
| Development ZIP | CRC and allowlist checks passed; developer tools, scratch files and credentials excluded |
| Source-only isolated copy | Six commands passed with no `node_modules/` or pre-existing `.work/`: docs check, three CLI help commands, Python developer-tool tests and Node tooling tests |
| Read-only device smoke | Galileo, Loader active, installed runtime hashes unchanged; local-port 8123 forwarding, CEF targets and `get_status` worked through the new project tools |
| Debug-session lifecycle | Owned block inhibitor was observed active; stop released it, closed the SSH master and removed session state |
| Installer and rollback logic | Successful/failed rollback, invalid archives and restart recovery exercised in temporary directories with mocked systemctl; no real-device install or rollback was performed in this maintenance run |

The source-only test proves that the developer helpers do not need a sibling checkout or saved work files. It does not claim that the full application builds without installing its declared dependencies. The real-device smoke did not operate QAM, change settings, write the clipboard, terminate the monitor or restart Loader. Its directory metadata describes Decky-managed containers, not a new permissions certification.

The local entry point is `bash scripts/check.sh`. New commands are documented in [Development](DEVELOPMENT.md), [Deployment](DEPLOYMENT.md) and [Debugging](DEBUGGING.md). A concise machine-readable maintenance record is retained in [tooling evidence](tooling/validation.json). Raw diagnostic logs stay local and are not distribution inputs.

## Historical milestones

| Stage | Evidence and interpretation |
| --- | --- |
| Initial sideload, 01:25–01:26 | `f748e87` installed, but no monitor started: frozen Python resolved the generic `settings` module incorrectly. `settings.load(Path)` reached `json.load` and raised `AttributeError: 'PosixPath' object has no attribute 'read'`. This was an import conflict, not a successful sampler with missing sensors. |
| Namespace fix, 02:01 | `4740fbf` renamed modules with `deckscope_` prefixes. Loader was active, the monitor existed, IPC/history directories were 0700 and socket/lock files 0600; the log reported `monitor ready`. Startup acceptance alone did not establish functional correctness. |
| Functional acceptance, 02:11–02:47 | `2bb2daa`; 21 Zig, 23 Python per build and 5 frontend tests. Actual RPC/history/persistence/old fullscreen/QAM behavior and monitor recovery were exercised. See [early device acceptance](DEVICE-ACCEPTANCE.md). |
| QAM-only candidate | `0.1.0-rc.1`; 22 Zig, 26 Python per build and 10 frontend tests. The old fullscreen route was removed. See [QAM acceptance](QAM-ACCEPTANCE.md). |
| Native appearance and D-pad scope | `0.1.0-rc.2`; 22 Zig, 26 Python per build and 12 frontend tests. Horizontal action groups and all-view/control directional reachability were checked. Touch investigation was subsequently stopped. See [native UI/input acceptance](UI-INPUT-ACCEPTANCE.md). |

Historical screenshot and artifact hashes remain unchanged in their associated reports and JSON. The older detailed combined record remains available through Git history, for example `git show 9c14429:docs/VALIDATION.md`. Historical startup backup paths and temporary unit names are provenance, never current command defaults.

For precise provenance, the initial sideload ZIP had SHA-256 `34a5d430e143de4a84a10bb0bbfc758e2e993c0a462ef7d0fb19273eb506a3b9`. The 02:47 native artifact was 127,640 bytes with SHA-256 `f5bbc4fb4382553e223f81afe05e94c6c0e0cafdb069ac3b822946ca44025cd0`; its 64,921-byte development ZIP had SHA-256 `1dc51e9607c487702dceea9024ead8d5b2b18606659b76c40f9889ba704329a1`. Those are not current rc.2 identities.

## Coverage and unverified boundaries

Fixtures cover Jupiter/Galileo profiles, 16/24-thread non-Deck layouts, alternative battery names, missing GPUs, CPU baseline/reset behavior, GPU-source association, signed battery charging, whole-disk de-duplication, PSI deltas, bounded history, persistence recovery/locking/retention, protocol framing, module-name conflicts and subscription recovery. They do not simulate every hardware, permission, routing, hot-plug or disk-failure branch.[2]

A seven-day range control is not seven days of retained data. CEF key injection is not physical-controller testing. Short-run RSS or mean sampling time is not steady-state memory, a P99 budget or a gaming-impact benchmark. Actual suspend/resume, network switching, synchronized power accuracy, LCD/non-Deck device acceptance, endurance, store installation and public-release approval remain separate work.[3]

The touchscreen issue is known and not claimed fixed. The user stopped that investigation; retain host-native scrolling and the approved UI while maintaining directional-key reachability. Do not use this record to authorize future disruptive tests.

## References

[1]: ../scripts/check.sh "Unified build and verification command"
[2]: ../tests/ "Monitor, bridge, UI and developer-tool tests"
[3]: COMPATIBILITY.md "Compatibility evidence and deferred acceptance"
