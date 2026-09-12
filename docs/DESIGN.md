# DeckScope architecture

## Scope and source of truth

DeckScope is a read-only SteamOS diagnostics and history plugin. The user's September 12 scope correction supersedes the attached proposal's Steam-Deck-only boundary. Jupiter and Galileo are named profiles, not admission checks. Other SteamOS hardware is capability-probed and must report unsupported data as unavailable. Generic Linux development is useful but does not constitute SteamOS compatibility certification.

The supplied final package is a feasibility demo, not production code or a performance guarantee. Its no-libc syscall approach is reused; its permissive JSON parser, sample-count timing assumptions, fixed eight-CPU/BAT1 assumptions and unknown-command success behavior are not retained.

## Runtime

The native Zig 0.16 process owns all samples and aggregation. Linux timerfd and epoll provide the event loop. Proc/sysfs descriptors are reused. The bridge creates a private UNIX socket, starts the monitor and correlates bounded request IDs. No TCP listener, root requirement, external network calls, shell commands or Python sampling loop is introduced.

The frontend uses Decky controls and a single typed API. Live pushes are enabled only while a consumer is mounted. The bridge retains this transient intent across native restarts under its configuration lock, including unsubscribe requests during recovery. Settings are atomic and private. Unknown or unavailable functions return structured errors rather than fake success.

All flat Python modules use a plugin-specific prefix: `deckscope_bridge`, `deckscope_protocol` and `deckscope_settings`. A host-preloaded module in `sys.modules` wins over a plugin file with the same generic name. The first authorized device install exposed this for `settings`, resolving `load` to `json.load` and failing before monitor spawn. An isolated test now preloads conflicting host modules and imports the actual plugin facade without modifying those host modules.

## Hardware capabilities

CPU topology is discovered from proc/stat and cpu sysfs, not inferred from model. Up to 256 logical CPU IDs are sampled for current per-thread values, with explicit truncation reporting for larger systems. Historical CPU records store total CPU only in the initial version. GPU busy/frequency/power sources are supported when readable; lack of a vendor-specific source is an honest missing capability, not zero load. Temperature source names are exposed because differently labelled sensors are not interchangeable. Battery devices are discovered by their type and presence; the initial version uses one selected battery and reports that source rather than claiming multi-battery totals.

Battery power uses readable `power_now` first, then an overflow-safe current/voltage estimate with explicit source metadata. Slow NVMe temperature reads have a 30-second monotonic cadence and reported cache age; cached values are intentionally held in history. This avoids treating every archived temperature as a fresh hardware conversion.

The product is QAM-only per the user's 02:55 direction. It registers no independent fullscreen route. The native QAM scroller contains Monitor, System and Settings views; real CPU/GPU/power history charts and system identity remain first-class features. Clipboard writes use the rendered element's owner document, not the unfocused SharedJSContext navigator; the summary remains visible when the clipboard fails.

## History and budgets

High holds at most 1,800 total-metric samples, Mid 2,160 ten-second windows, Low 10,080 minute windows. All windows are based on elapsed monotonic time rather than number of samples. Gaps are not backfilled. Wall time timestamps are UTC; clock discontinuities reset active aggregation. Each metric has its own valid-sample denominator. Only CPU/GPU retain min/max in the compact first-version aggregate; other fields are means. This intentional reduction keeps the fixed data region below 2 MiB.

Minute aggregates use a versioned little-endian checksum-protected format. Truncated or corrupt tails are ignored/repaired at the last valid record; unknown schemas are preserved and rejected. Retention and write failure behavior must be tested. No unmeasured latency, RSS or gaming-impact claim is a release criterion marked passed.

## Compatibility and acceptance

Initial device discovery confirmed one Galileo SteamOS 3.8.16 host and readable PSI/hwmon sources. No plugin deployment, service restart or UI acceptance is authorized by that read-only probe. LCD, non-Deck SteamOS, suspend/resume, multi-GPU, network switching and long-run behavior need their own evidence. Features omitted from the first working slice must be listed in README rather than represented by dummy data.

The first authorized sideload on September 12 installed successfully but failed at plugin startup due to the Python module collision above. The namespace correction at `4740fbf` was then redeployed under user authorization. At 02:01 the loader was active, the installed native hash matched, the monitor process existed, its private socket was mode 0600, and the current plugin log reported `monitor ready`. This is startup acceptance only, not UI, metric-accuracy, historical durability or cross-device acceptance. See `VALIDATION.md` for package identities and evidence.

The subsequent authorized functional acceptance exercised actual Overview/History/Device/QAM rendering, directional-key controls, settings, privacy, clipboard, persistent records and monitor crash recovery. See `DEVICE-ACCEPTANCE.md`; suspend/network fault testing and long-run or cross-model certification remain separate.

## QAM-only release candidate

The QAM charts seed bounded history on mount/range change and merge live samples without polling. All series retain UTC millisecond x-coordinates, explicit units and missing-value gaps. CPU/GPU use a shared 0–100% scale. Power distinguishes APU package from signed battery electrical power; unavailable whole-device power is never inferred from APU power. System information includes kernel, SteamOS build, CPU model, architecture, firmware, interface and masked IP. The plugin does not add desktop/fullscreen routes.

## Native QAM input contract

Prefer native Field/PanelSection/PanelSectionRow and DialogButton styling. Do not replace gamepad focus styles. Side-by-side action pairs require an explicit horizontal Focusable, not CSS flex alone. The host owns scrolling; avoid nested overflow containers, touch-action overrides, gesture interception and forced scroll positioning. rc.2 synthetic swipes pass, but the original physical-touch complaint remains unconfirmed; see UI-INPUT-ACCEPTANCE.md.

At 11:16 on 2026-09-12, the user stopped touchscreen-specific investigation after observing similar behavior in other plugins. Current acceptance prioritizes directional-key access to all QAM views and controls; preserve the approved rc.2 appearance and do not add touch workarounds without a new request. No host root cause is asserted.
