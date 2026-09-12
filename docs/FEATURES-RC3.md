# rc.3 Monitoring and System Details

**Version: `0.1.0-rc.3`.** All five requested feature groups are implemented. Local regression and an isolated native snapshot on the Galileo device pass. The revised candidate is now installed on Galileo; actual QAM rendering and directional-key acceptance pass. See [device acceptance](RC3-ACCEPTANCE.md) for exact installed hashes. Genuine suspend/resume event capture remains untested. This is a private candidate, not a public release.[1]

## User-visible changes

| Area | Implementation | Important distinction |
| --- | --- | --- |
| Monitoring | CPU/GPU/power overview plus Memory, Thermal, Disk/Network and PSI groups | Curves use existing sampled metrics; unavailable readings remain unavailable |
| Memory | Used RAM and used Swap history | Values are MiB, not percentages |
| Thermal | CPU, GPU, SSD temperature and fan-speed history | SSD temperature retains its documented 30-second source cache |
| I/O | Disk read/write and network receive/transmit history | Values are KiB/s; network history follows the selected route interface |
| Pressure | CPU some, memory some/full and I/O some/full history | PSI is stalled-time percentage, not utilization; the scale is 0–100% |
| Recording coverage | Estimated covered/uncovered duration, bounded gap list, latest persisted record, last successful sync this run, pending records and event markers | Coverage is a resolution-based estimate for the explicitly named metric, not proof of continuous sampling |
| Storage | Mounted local system/home/removable filesystems, total/available bytes, unmounted SD detection | Filesystem capacity is not physical SSD capacity; shared mounts are deduplicated |
| Battery | Full/design capacity, estimated health ratio, driver-reported cycle count, voltage and state | Charge and energy remain different units; absent attributes are not fabricated |
| Runtime | OS elapsed/awake/suspended time, load averages, memory/cache, Swap, zram and zswap | OS clocks count from boot, independently of collector uptime |

The Monitor view keeps native horizontal selectors and the approved SteamOS control styling. System details are divided into Device, Storage, Battery and Runtime subviews rather than placing every field in one long list. Existing IP and summary action pairs retain explicit horizontal focus groups. No fullscreen route, nested scroller, touch interception or system-control operation has been added.[2]

## Recording semantics

Coverage is computed from the selected tier's full bounded ring **before chart point reduction**. Mid/Low coverage also unions available recent raw samples, so pending aggregation does not create a false trailing gap. Windows overlapping the query start contribute only their clipped support. Valid metric timestamps are sorted and their resolution-sized support intervals are unioned, preventing clock rollback or duplicate timestamps from counting time twice. Coverage duration is retained even if the list of individual gaps exceeds its 256-entry response cap. Aggregate records can contain partial windows or mixed sampling intervals, so the estimate must not be presented as exact active duration. Raw support uses the current sampling interval; older raw samples collected at another interval can make this estimate less precise.[3]

Gray chart regions indicate uncovered intervals. Detected suspend/resume bounds appear as yellow markers and as labeled rows. Unknown gaps remain **No data**: shutdown, old suspends, process downtime and unavailable sensors cannot be distinguished retrospectively from the existing metric archive alone. Clock-change events are labeled separately. Real suspend/resume boundaries are estimated between observations, not imported from system journal records.[3]

The existing `DSCP` v1 header and 128-byte minute records are unchanged. A separate private `events.v1` sidecar stores up to 128 checksum-protected 32-byte events. It is atomically replaced, the file and directory are synchronized, and events older than seven days are pruned during normal minute processing. A sidecar failure is reported independently and does not disable metric collection. Full power-loss durability and actual suspend testing are not claimed.[3]

`last_persisted_sample_ms` is the timestamp of the latest successfully persisted aggregate, whose timestamp is its first sample. It is not the time the disk write occurred. `last_sync_ms` is the successful batch sync time in the **current monitor process**; after restart it remains null until a new sync. Recovering an archive does not invent a previous fsync time. Pending minute records are also exposed.[3]

While the Monitor view is open, incoming live events can refresh its history snapshot at most once per minute. A ten-second heartbeat prevents constant readings from leaving that view indefinitely stale. There is no frontend polling timer, and closing the last live consumer disables events while collection continues. Storage, battery and runtime details remain entry/manual-refresh snapshots, not additional sampling loops.[3]

## Capacity and availability

The battery module uses the sampler-selected battery only. A complete energy pair is preferred; a complete charge pair is used when energy is incomplete. Partial pairs retain their own unit and produce no health ratio without a positive design value. Voltage, charge and energy are converted from the kernel's micro-units without inventing watt-hours from amp-hours. Linux explicitly distinguishes charge, energy and percentage capacity, and drivers may omit individual attributes.[4]

Estimated health is `full / design × 100`. Values above 100% are preserved because this is a ratio of driver-reported thresholds, not a calibrated lifespan assessment. A reported cycle count of zero is displayed as zero, without claiming that the battery has never cycled. Missing or invalid presence is null when a source was selected; no selected battery is explicitly absent.[3]

Storage reads a bounded mountinfo snapshot, accepts only listed local filesystem types and excludes network/FUSE/pseudo filesystems before `statfs`. It deduplicates filesystem identity and never exposes labels, mount paths or device identifiers. Unmounted SD discovery accepts a readable removable flag or an SD device type; MMC is not automatically classified as removable SD. An unmounted card has no fabricated filesystem capacity. Uncommon filesystems and arbitrary custom mount layouts remain limitations.[3]

Zram totals become unavailable if a detected device cannot supply the required counters or enumeration exceeds the bound. OS suspended time is derived from BOOTTIME minus monotonic time. These are system-wide durations since the current OS boot, not evidence that DeckScope recorded every awake interval.[3]

## Device snapshot evidence

Before sideloading, an isolated rc.3 monitor was copied to a task-created temporary directory and connected to its own private test socket/history directory on the existing Galileo device. It did not replace the plugin, connect to the plugin's monitor socket, restart Decky, or touch the user's history. The temporary files were removed after the process exited. The raw non-identifying snapshot is archived separately.[1]

| Field | Observed result |
| --- | --- |
| Battery capacity basis | Charge, not energy |
| Full/design capacity | 6804 / 6470 mAh |
| Estimated ratio | 105.1% |
| Driver cycle count | 0 |
| Battery voltage | 8.435 V in the final snapshot; voltage varies between observations |
| System filesystem | Mounted btrfs |
| User-data filesystem | Mounted ext4 |
| Removable storage | SD/removable device detected; no supported mounted removable filesystem found |
| Runtime / load / cache / Swap | Available |
| zram / zswap | One readable zram device; zswap reported disabled |

## Validation and remaining acceptance

The final local suite runs **46 Zig unit tests**, **42 Python tests against both ReleaseSmall and ReleaseSafe**, and **22 frontend/tooling tests**, plus TypeScript, Rollup, documentation checks and package verification. Tests cover missing and zero-valued battery attributes, charge units, filesystem deduplication/redaction, unmounted SD discovery, fixture-root isolation, mixed readable/unreadable zram devices, persisted coverage before decimation, corrupt event sidecars, unknown gaps, PSI axes and rendered field formatting.[5]

The revised candidate passes installed QAM rendering and directional-key acceptance. Sub-minute durations display seconds rather than zero minutes. Actual card mount/unmount transitions, genuine suspend/resume marker capture, long-run performance and non-OLED hardware still need their own evidence. Neither the local tests nor the isolated native snapshot replaces those checks. Public publishing prerequisites remain documented in [Release Preparation](RELEASE.md).

[1]: features/rc3-native.json "Isolated native snapshot on Galileo"
[2]: ../src/SystemPane.tsx "Native system subview structure"
[3]: PROTOCOL.md "Protocol, storage and availability contracts"
[4]: https://docs.kernel.org/power/power_supply_class.html "Linux power supply class: units and full/design semantics"
[5]: ../tests/test_details_history.py "Cross-process details and history regression tests"
