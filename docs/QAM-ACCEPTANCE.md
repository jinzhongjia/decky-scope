# DeckScope QAM-only Candidate Acceptance

> **Historical status — 2026-09-12:** This document records a historical candidate acceptance exercise, not current release approval, production certification, or store approval. The approved **rc.2 UI** is retained as the accepted UI direction. The self-contained current procedure is maintained in [DEBUGGING.md](DEBUGGING.md); this historical record must not be treated as a substitute for that procedure.

**Date:** 2026-09-12, UTC+8. **Version recorded by this acceptance run:** `0.1.0-rc.1`. **Conclusion:** The QAM revision was sideloaded and passed this round of functional acceptance; it was not publicly released.

## Results overview

This round narrowed the product to QAM-only. The former `Page.tsx`, `Timeline.tsx`, and `/deckscope` route were removed. Monitoring, system information, and settings are all handled within the Decky sidebar. The side-by-side CPU/GPU charts, APU/battery power charts, system version, and kernel information were checked in the actual Steam CEF interface; they were not static designs or simulated data.

The device was a Steam Deck OLED (Galileo) running SteamOS 3.8.16, system build `20260716.1`, with Decky Loader v3.2.8. Other hardware models and system channels did not receive real-device validation in this round. Machine-readable observations and original screenshot hashes are stored in [acceptance evidence](qam/evidence.json).[1]

![Actual QAM monitoring interface, with only empty space cropped from the right side of the original](qam/monitor-preview.png)

## Local regression

| Check | Result |
| --- | --- |
| Zig unit tests | 22 passed |
| Python regression against the ReleaseSmall binary | 26 passed |
| ReleaseSafe binary regression with runtime checks | 26 passed |
| Frontend pure-logic and contract tests | 10 passed |
| TypeScript and Rollup | Passed |
| Candidate package consistency | Passed; byte-for-byte identical to the development package |
| Public-release preflight | Failed as expected; missing items such as the license, repository, store build, and showcase images were not ignored |

The unified command was `bash scripts/check.sh`. New coverage included CPU model parsing, exclusion of sensitive identifiers, boundedness of live traces, same-timestamp replacement, clock rollback, real time ranges, missing points, percentage scaling, negative battery power, and detection of stale release packages and version mismatches. These results are not equivalent to a real-world performance benchmark.

## Actual QAM acceptance

| Area | Observation and conclusion |
| --- | --- |
| Three charts | CPU, GPU, and power charts rendered simultaneously. During interval reads, all three Canvas elements changed, and the native sample count continued to increase. |
| Time range | Switched to 7 days and back to 5 minutes on the device. The charts remained present, and no dates for which the device had no records were fabricated. |
| Power source | APU and battery buttons could be switched. The labels clearly distinguished package power, charge/discharge power, and whole-system power. |
| System information | SteamOS version, build, complete kernel string, architecture, CPU model, logical CPU count, memory, manufacturer, model, and BIOS were all readable. |
| Privacy and copying | The IP was displayed and then hidden again in the actual UI. Copying the system summary succeeded. Archived screenshots retain the mask and do not record the actual address. |
| Settings | The actual QAM control was switched 1 second → 2 seconds → 1 second, with confirmation by reading the value back from the backend. The privacy mask was enabled at the end. |
| Native focus | Directional and confirm input switched views. Focus was walked item by item through OS, version, build, kernel, architecture, CPU, logical CPU, memory, manufacturer, model, and BIOS; the long page scrolled with focus. |
| Monitor recovery | A single TERM was sent to this plugin's monitor. The native process restarted, `live_push` returned to `true`, and the UI text continued to change. |
| Closing QAM | `live_push` became `false`, while the background sample count continued to increase. |
| Device artifacts | The installed binary and frontend SHA-256 values matched the local artifacts; the current log showed `monitor ready`. |

Directional and confirm operations were performed through CEF synthetic keyboard input and must not be described as physical-controller testing. Native exit injection affected only this plugin; it does not represent a power failure, kernel crash, or real suspend/resume test. The IP check proves only that the local field can display an address; it does not prove that an external client can connect over SSH/CEF.[1]

In the later 11:16 scope update, touchscreen investigation was stopped because other plugins were reportedly showing similar behavior. That report is not proof of a host-level root cause, and this document makes no such claim. D-pad access to all views and controls is the accepted interaction requirement.

## Issues fixed during acceptance

| Observed issue | Fix |
| --- | --- |
| The power-switch buttons retained the native default full width, causing the second button to overflow | Applied the QAM-local segmented-button style with explicit width constraints |
| The first-screen timeline was clipped at the bottom | Adjusted the heights of both chart types so all three charts and the shared timeline remained fully visible on the first screen |
| The native Dropdown opened options in the main window and hid QAM | Replaced the sampling interval control with four segmented buttons inside QAM |
| An ordinary Focusable container did not actually enter the focus tree | Based on real-device component behavior, explicitly passed native `focusable: true` to read-only information rows; no ineffective click action was added |
| The default minimum width of action buttons caused horizontal scrolling | Applied shrinkable and minimum-width constraints to plugin action buttons while retaining native focus highlighting |
| Direct frontend replacement was blocked by root-owned file permissions | Stopped direct writes; after the user authorized continued sideloading, used the established complete sudo installation and backup workflow without loosening file permissions |

![Actual system information and kernel version](qam/system.png)

![Actual hardware and privacy-mask card](qam/network.png)

## Artifact identity

| File | Size | SHA-256 |
| --- | ---: | --- |
| `bin/deckscope-monitor` | 128,000 bytes | `d8156e01d2c53ec9b1d116de0b3ea8cc3ee814e710940ac9a985ad9c4d8916bb` |
| `dist/index.js` | 49,142 bytes | `b044d7bcf8c1c4f33119150b8e4726614b83e3e76101d9bdcce83c787581cb09` |
| `DeckScope-0.1.0-rc.1.zip` | As recorded for the archive | `63afb51aa31acf2be59dbc4adbed2f75202038e7b679786e99b12eca28b62c61` |

The monitoring preview only removes empty space on the right side of the original, where there was no UI content; no values or curves were redrawn. The original full screenshots and other views are retained in `docs/qam/`.

## Closeout and remaining boundaries

The plugin panel was closed, and the backend was confirmed to continue recording without live pushing. The ending configuration was a 1-second sampling interval with the IP privacy mask enabled. At 03:35:14, the temporary sleep inhibitor for this round was deliberately stopped and the task-specific SSH/CEF tunnel was closed; no background debugging task dependent on this session remained. The device could return to normal suspend behavior.[1]

This round did not test LCD, non-Deck SteamOS, real suspend/resume, network switching, a physical controller, synchronized electrical-power accuracy, long-duration stability, or effects on game frame timing. No public repository was created, Git was not pushed, no tag was created, no public release was uploaded, and no store submission was made. **The remaining formal-release requirements are listed in [Release preparation](RELEASE.md); this candidate acceptance must not be treated as store approval or production certification.**

The sibling music project was used only as historical provenance for earlier work, if referenced by the surrounding project record. It is not a prerequisite or a future-developer dependency for this procedure.

## References

[1]: qam/evidence.json "DeckScope QAM-only device observations, lifecycle checks and screenshot hashes, 2026-09-12"
