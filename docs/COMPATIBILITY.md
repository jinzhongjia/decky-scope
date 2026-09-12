# Compatibility and Limitations

**DeckScope targets SteamOS capabilities, not a hard-coded Steam Deck topology.** A successful run on one Galileo device does not certify all SteamOS devices or a production release. Missing readings remain unavailable instead of being fabricated as zero.[1]

## Evidence by platform

| Platform | Implementation | Evidence |
| --- | --- | --- |
| Steam Deck LCD / Jupiter | Dynamic CPU, DRM and battery discovery with known APU interpretation | Synthetic fixtures; no LCD device acceptance |
| Steam Deck OLED / Galileo | The same capability discovery without fixed sensor indices | Private candidate startup, QAM, state, history and recovery checks on one device |
| Other SteamOS hardware | Generic CPU, memory, PSI, storage/network I/O and readable sensors | 16/24-thread, alternative battery names and missing-GPU fixtures; no other-device certification |
| Ordinary Linux development host | Honest degradation for protocol and parser testing | Local regressions; not SteamOS acceptance |
| Intel/NVIDIA GPU, special EC fans, multiple GPUs/batteries | Unavailable fields are omitted; one readable GPU and battery are currently selected | Dedicated collectors, explicit selection and multi-device aggregation are deferred |

Current CPU snapshots support logical IDs 0–255 and report truncation beyond that limit. History retains overall CPU values, not per-thread history. GPU load, temperature, frequency and power must belong to the same selected DRM device. Arbitrary discrete-GPU power is not reclassified as APU package power.[1]

## Data semantics

The native monitor is a static x86_64 Linux ELF without libc dependencies. It uses a single `timerfd`/`epoll` loop and bounded history rings: 1,800 high-frequency points, 2,160 ten-second windows and 10,080 minute windows. Missing metrics have independent valid counts. CPU/GPU aggregates retain extrema and means; other metrics retain means. Query reduction uses bounded stride selection and does not guarantee that every spike survives decimation.[2]

Battery power is positive for discharge and negative for charge. Where `power_now` is absent, the current-times-voltage fallback reports its source. Neither battery electrical power nor APU package power is wall power or total-system power. NVMe temperature uses a 30-second cache, whose age is exposed; repeated history values may be held samples. A slow refresh still runs on the sampling thread, so no P99 guarantee follows from caching.

Persistence uses DSCP schema v1, explicit 128-byte records, CRC32, private file permissions, a single-writer lock and batched writes. Retention covers the current UTC day and the preceding six days, not an exact sliding 168-hour window. Clock rollback can make future-dated files fall outside retention. Invalid schemas are preserved/refused; invalid tails are recovered only to the last valid record. Abrupt termination may lose the unflushed batch.[2]

The plugin does not collect credentials, MAC/SSID, Steam IDs, serial numbers, other processes' environments or full command lines. Export uses a whitelist. Runtime sampling does not upload data. Development SSH/CDP tools are separate, operator-invoked utilities and may expose diagnostic data locally.

## Known limits and deferred work

Automatic game-session detection and summaries, PSI threshold events, timeline events, full gamepad chart cursors/zoom, storage-capacity/display information, and Intel/NVIDIA-specific collectors are not implemented. Network selection covers the main routing table; VPN exclusion is heuristic. Complex policy routing and interrupted multipart dumps need further testing. The network card refreshes on entry or explicit refresh, not frontend network-change events. Hot-plug reprobe largely depends on restart or resume. Startup recovery reads the bounded seven-day archive; lazy range indexes remain deferred.

The normal UI supports Simplified Chinese and English through CEF language detection, with one fixed-English crash-boundary sentence still outstanding. The user-approved rc.2 appearance and D-pad reachability remain the interaction baseline. Touchscreen obstruction was also reportedly seen in other plugins, but no host root cause was proven; investigation was stopped at the user's request.[3]

Actual suspend/resume, network switching, physical-controller testing, synchronized charge/discharge accuracy, multi-device compatibility, 48-hour endurance, seven-day retention, game-frametime A/B measurements and a real P99 budget remain separate acceptance work. Neither a local build nor a single successful device startup substitutes for these tests.

## References

[1]: DESIGN.md "SteamOS capability-first architecture"
[2]: PROTOCOL.md "Metric semantics and persistence format"
[3]: UI-INPUT-ACCEPTANCE.md "rc.2 input results and touchscreen scope decision"
