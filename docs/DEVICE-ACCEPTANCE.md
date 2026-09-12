# DeckScope Historical Device Acceptance Record

> **Historical-status notice:** This document records a functional acceptance run performed on 2026-09-12. It is not current release certification and must not be treated as production acceptance. The approved **rc.2 UI is retained**. The touchscreen investigation is stopped because other plugins have reportedly shown similar behavior; this is not a proven host-level root cause. D-pad navigation must remain available for all views and controls. For the current self-contained debugging procedure, see [DEBUGGING.md](DEBUGGING.md).

**Date:** 2026-09-12, UTC+8, 02:11–02:47. **Code version:** `2bb2daa`. **Author:** Manus AI.

## Conclusion

**The development preview passed this functional acceptance round on this Steam Deck OLED.** The run exercised the real metrics interface, historical queries, disk persistence, settings, privacy masking, overview, history, device page, QAM entry, and monitor-failure recovery. Five issues found during acceptance were fixed and the plugin was sideloaded again. The final complete regression passed 21 Zig tests, 23 Python tests for each of ReleaseSmall and ReleaseSafe, and 5 frontend tests. Type checking and the build also passed.[1] [2]

This conclusion is not production-release certification. The run did not test actual suspend/resume, network interruption or interface switching, physical gamepad hardware, other hardware models, or long-duration operation. Metric sources and some units were checked, but not every value was compared individually with an independently synchronized benchmark.[1]

The approved rc.2 UI is retained. Directional-pad navigation is a continuing requirement for every view and control. The checks below document only the directional-input coverage demonstrated during this historical run; they do not claim that exhaustive coverage was proven.

## Environment and Method

| Item | Actual environment and scope |
| --- | --- |
| Hardware | Steam Deck OLED, DMI Galileo, 8 logical CPUs |
| System | SteamOS 3.8.16, Build 20260716.1 |
| Kernel | `6.16.12-valve24.5-1-neptune-616-gb2f7cfe85e45` |
| Decky | v3.2.8 |
| Backend acceptance | The real Decky RPC with the installed plugin; no fake bridge was started to impersonate the production path |
| UI acceptance | Steam CEF large-screen and QuickAccess windows; DOM operations and directional-pad/confirm-button events |
| Fault injection | Only this plugin's monitor was terminated; the network was not disabled, system power settings were not changed, and other plugins were not killed |
| Historical reference tools | The adjacent `decky-music` project's `decky-dev`, `steam-cdp` skill, and CDP scripts were reused for this run; that project was not modified. This is historical provenance only and is not a future-development dependency. |

UDS means UNIX domain socket, the local communication channel between the bridge and the Zig monitor. CRC32 is the checksum used by this project's historical files. Backend queries used the existing `DeckyBackend.call` route and did not call the reconnect interface that would replace the plugin event-listener table.[3]

## Functional Acceptance Results

| Check | Result | Evidence and limitations |
| --- | --- | --- |
| Real metrics | Passed read and dynamic-update checks | CPU, GPU, memory, temperature, APU power, PSI, disk, network, and other fields were readable; sample counts and UTC timestamps advanced |
| Sources and units | Partially cross-checked | Temperature, frequency, APU power, battery state, and proc/sysfs sources were checked; memory was converted using binary MiB; synchronized-precision verification was not completed for every dynamic value |
| Battery power | Current power state passed | BAT1 had no `power_now`, but had `current_now` and `voltage_now`; current state was Not charging at 0 µA, and after the fix the UI displayed 0.0 W; positive and negative charge/discharge branches were covered by local tests |
| Historical queries | Passed | Real CPU and memory records were available, `max_points` was bounded, and the UI switched successfully to memory and the 7 d range |
| Meaning of the seven-day range | Query control only passed | The chart displayed only the approximately tens of minutes of records already present. This does not mean that seven days were filled or that seven-day retention was accepted |
| Historical persistence | Passed current-file inspection | `20707.dscp` was 5,280 bytes with 41 records; the header, CRC32 for every record, and 0600 permissions passed independent read-back checks |
| Restart recovery | Passed for persisted data | Old minute records were recovered after the fault. In the final injection, 29 disk records were restored from 30 in-memory records; the one unflushed record was not misrepresented as persisted successfully |
| Live subscription | Passed | The overview and QAM enabled live pushes. Closing QAM, entering history, or closing all UI disabled pushes while sampling counts continued to advance |
| Process-failure recovery | Passed after the fix | About three seconds after the monitor exited, backend sampling resumed, `live_push=true`, and actual page values changed without re-entering the page |
| Sampling settings | Passed through RPC and UI | Directional input opened the menu and selected 2 s; backend and persisted settings read back consistently; a zero interval returned `invalid_request`; the final setting was restored to 1 s |
| Privacy masking | Passed in the UI | After confirm disabled masking, the address appeared. After enabling it again, the mask returned. Masking remained enabled at the end |
| Summary copy | Passed after the fix | The button used its document's clipboard; the UI displayed “Copied”. Existing user clipboard contents were not read |
| Overview layout | Passed after the fix | Eight metrics, the refresh button, and explanatory text were visible on the large screen; the overview had no nested scrolling area |
| Device-page focus | Passed with simulated input | Directional input reached the switch, dropdown, copy control, and refresh control. The native scrolling area scrolled automatically, and native A/B prompts were visible |
| QAM entry | Passed with simulated input | Directional input reached “Open DeckScope”, and confirm entered the actual plugin large-screen view from the Steam home page |
| English and malformed events | Passed in local tests | The entire Steam system language was not changed, and local guard tests were not presented as real-device malformed-event injection |

The concise original fields, versions, record counts, file hashes, and screenshot hashes are stored in [machine-readable evidence](acceptance/evidence.json). The complete work log remains in the project `.work/` directory and was not included in the plugin ZIP.[1]

## Issues Found and Fixed During This Run

| Issue | Cause and fix | Verification |
| --- | --- | --- |
| Battery charge/discharge power missing | OLED did not provide `power_now`; an overflow-safe current-times-voltage fallback was added and its source was exposed | Real Not charging state plus unit and fixture tests |
| NVMe temperature reads too slowly | A single NVMe sysfs read measured approximately 8 ms; it was changed to a 30-second monotonic-time cache, with cache age exposed | Source-read timing, cache integration tests, and real state fields |
| Page stopped updating after restart | The bridge forcibly disabled live pushes on every start; it was changed to retain only the in-memory consumer intent | Comparable termination injection before and after the fix, comparing backend state and actual page text |
| Overview clipping and two-level scrolling | The outer page and Tabs both scrolled; the layout was changed to one native scrolling area under flex constraints, with a four-column overview | Original screenshots, DOM scroll dimensions, and directional-input operation |
| Summary copy failed | Plugin code ran in an unfocused SharedJSContext; it was changed to use the owner document of the actual rendered element | Main-window/shared-window focus and permission comparison, ending with the “Copied” state |

Battery estimation uses `abs(µA) × µV / 10^9` to obtain mW and chooses the sign from the charge/discharge state. It is not whole-device or wall power. Consecutive NVMe historical values may come from the same cached reading and must not be interpreted as a new temperature measurement every second. Slow refreshes still run on the single sampling thread and may still produce latency spikes.[3]

The three code rollback points are `e868c9a` (native collection), `4d8abed` (restart subscription), and `2bb2daa` (UI and clipboard). The fixed code was sideloaded. The documentation and evidence were submitted separately and did not change the deployed code.

## Performance Observations, Not Release-Budget Conclusions

| Observation window | Samples | Cumulative sampling time | Mean time | Maximum time |
| --- | ---: | ---: | ---: | ---: |
| Before NVMe caching | 698 | 11,938,183 µs | 17.10 ms | 26.932 ms |
| Short observation after NVMe caching | 39 | 74,526 µs | 1.91 ms | 17.865 ms |

The two windows differ in length and UI activity, so they cannot establish a strict A/B speedup ratio. These measurements are wall-clock time for one sample, not CPU utilization and not P99. Independent source timing showed that NVMe temperature reads were an important slow source, but did not fully attribute all sampling time.[1]

The final process snapshot was single-threaded, with RSS of 376 kB and virtual memory of 3,244 kB. The fixed-capacity history buffer was not yet full, so this short-run RSS must not be treated as the steady state for a full seven-day buffer. The native release file was 127,640 bytes, approximately 124.6 KiB, as a static x86_64 ELF.[1]

## Original Screenshots

The image below is the original CEF large-screen screenshot of the final overview. It was neither redrawn nor generated. The QAM file is the original screenshot of its own window, not a composited presentation with the main screen.

![Final overview with native focus prompts](acceptance/overview.png)

| Scenario | Original screenshot |
| --- | --- |
| CPU history | [history.png](acceptance/history.png) |
| Memory and seven-day query range | [history-memory-week.png](acceptance/history-memory-week.png) |
| Device page and privacy masking | [device.png](acceptance/device.png) |
| Successful copy and lower summary | [clipboard.png](acceptance/clipboard.png) |
| QAM large-screen entry focus | [qam.png](acceptance/qam.png) |

## Installation Identity and Cleanup

| Artifact | SHA-256 |
| --- | --- |
| `bin/deckscope-monitor` | `f5bbc4fb4382553e223f81afe05e94c6c0e0cafdb069ac3b822946ca44025cd0` |
| `dist/index.js` | `23d06ace2e0998c236336b2e7ad6250737f22708643c0e21e577910af86ba4f3` |
| `outputs/DeckScope-dev.zip` | `1dc51e9607c487702dceea9024ead8d5b2b18606659b76c40f9889ba704329a1` |

The remote native and frontend file hashes matched the local artifacts. The old-version backup retained by the final installation was on the device at `homebrew/deckscope-backups/DeckScope-1789151925790140983`. A rollback-restore drill was not performed.[1]

At 02:47, the plugin UI was closed and Steam returned to its home page. The final settings were 1,000 ms, privacy masking enabled, and live pushes disabled. Native collection did not stop when the page closed. The temporary sleep inhibitor and the SSH/CDP tunnel listening only on the development machine's loopback address were released. Permanent sleep, power, fan, SSH, and CEF settings were not changed, and no Git remote was pushed.

## Remaining Acceptance Boundaries

The next phase should independently schedule actual suspend/resume and network switching, and should add hardware-source validation on at least one LCD device and one non-Deck SteamOS device. Actual charge/discharge transitions, physical gamepad input, disk-write failure, 48-hour endurance, seven-day retention, game-frametime comparison, and a formal P99 budget remain incomplete. This run did not change the system clock, deliberately create a disk failure, disconnect the active debugging network, or force the machine to sleep.[1]

Full controller timeline cursors and zoom, automatic game sessions, and Intel/NVIDIA-specific collection remain unimplemented product work. They were not features accepted in this round. Deployment and local-check entry points are in the [project README](../README.md).[2]

## References

[1]: acceptance/evidence.json "Sanitized SteamOS functional acceptance observations and artifact hashes"
[2]: ../README.md "DeckScope build, validation and implementation boundaries"
[3]: PROTOCOL.md "DeckScope protocol, sensor freshness and on-disk semantics"
