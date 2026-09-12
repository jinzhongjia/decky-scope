# DeckScope protocol v1

## Transport and security

The bridge listens on `<DECKY_PLUGIN_RUNTIME_DIR>/ipc/deckscope.sock` in a mode-0700 directory. The socket is mode 0600. An accepted connection must have the spawned monitor's PID and the bridge user's UID according to `SO_PEERCRED`. The native monitor is a UNIX client and does not open TCP connections. There is no authentication password in the protocol or repository.

Every message is one UTF-8 JSON line, including its terminating newline, with an upper limit of 256 KiB. An overlong incoming frame closes the connection. An invalid JSON envelope may receive an error with a null ID; malformed arguments in an otherwise valid envelope retain the numeric request ID. Python correlates at most 32 in-flight requests. The monitor has a fixed 512 KiB nonblocking output queue and disconnects a persistently non-reading peer instead of blocking collection.

```json
{"type":"request","id":1,"method":"get_status","args":{}}
{"type":"response","id":1,"ok":true,"data":{}}
{"type":"response","id":1,"ok":false,"error":{"code":"invalid_request","message":"Request could not be completed"}}
{"type":"event","name":"metrics","data":{"ts_wall_ms":1789140000000,"available":1,"cpu_pct_x10":123}}
```

Request IDs are unsigned 32-bit integers. Unknown fields and invalid numeric types are rejected. The implementation intentionally uses Zig's standard typed JSON parser with a fixed 32 KiB arena rather than adopting the demo's permissive hand-written scanner. There is no heap allocation on the sampling path. Valid JSON string escapes are decoded, duplicate keys are rejected, and unknown methods return `unsupported_method`.

## Methods

| Native method | Arguments | Result |
| --- | --- | --- |
| `get_status` | `{}` | Latest sample, topology, per-thread current CPU values, source names, RRD lengths, sample costs, error counters and recording persistence status |
| `get_device_info` | `{}` | OS/build/kernel/BIOS/profile, battery details, mounted local filesystem capacity and OS runtime snapshot |
| `get_connectivity` | `{}` | Best-effort main-table address/interface selection and local SSH/CEF listener state |
| `set_config` | Optional `interval_ms` 500–5000 and `live_push` boolean | Empty success object |
| `query_history` | `from`, `to` UTC milliseconds; `metric`; `max_points` 1–1200 | Chosen base resolution, bounded single-metric samples, estimated coverage, gaps and detected events |
| `flush` | `{}` | Flush current partial aggregate and pending records; reports write failure |
| `export_summary` | `{}` | Native environment object; the public bridge export applies a narrower whitelist |

The public Decky API contains six methods: all of the above except `flush`. The bridge's `set_config` additionally accepts `privacy_mask`. The bridge's `export_summary` returns a redacted text object rather than the native environment object. The whitelist excludes board names, BIOS strings, hostname, IP, username, serial numbers and user paths. `query_sessions` and `session_mark` are deliberately **not advertised** until session recording is implemented.

The metrics event is enabled by UI reference counting, rate limited to at most 1 Hz, and suppressed inside metric-specific deadbands except for a ten-second live heartbeat. The bridge retains current live-subscription intent in memory across monitor restarts, but never persists it to settings; closing the last consumer during recovery keeps it disabled. Device details query on entry or explicit refresh. Open Monitor history also refreshes from incoming live events at most once per minute, without a polling timer. The native network cache is refreshed by rtnetlink events; the initial UI connection card refreshes on entry or with its Refresh button. Network-change push events are not yet part of the exposed implementation.

## Metrics and units

The authoritative order of the 25 availability bits is the `Metric` enum in `monitor/src/model.zig`. Unavailable properties are omitted from samples and become `null` in single-metric history queries. A genuine zero remains zero. CPU utilization is percentage times ten; PSI is percentage times one hundred; temperatures are milli-degrees Celsius; power is milliwatts. Memory and throughput use binary units (MiB and KiB/s). `battery_rate_mw` is positive while discharging and negative while charging; it is **not wall power or total system consumption**.

CPU total excludes guest counters already included in user/nice. Counter resets and first observations establish a baseline rather than generating spikes. Current per-thread values support IDs 0–255 and report truncation explicitly beyond that bound. No eight-thread assumption remains. Per-thread history is deferred.

CPU and GPU aggregate records retain min/max plus mean. Other metrics retain their valid-sample arithmetic mean. Means are sample-weighted, not duration-weighted; changing the interval inside an active window can change its weighting. Query reduction currently uses bounded stride selection; it does not promise preservation of every spike when reducing many windows. Cursor navigation and extrema-preserving display decimation remain future work.

## Sensor freshness and battery power sources

`get_status.sources.battery_power` reports `power_now`, `current_x_voltage`, `status_only` or `unavailable`. When `power_now` is absent, the selected battery's `current_now` and `voltage_now` provide estimated milliwatts: `abs(microamp) * microvolt / 1e9`. Charging is negative, discharging positive; known Full/Not charging states report zero. Unknown state, missing operands or overflowing results remain unavailable. This is battery electrical power, not total system or wall power.

NVMe temperature can require a slow synchronous hardware read on SteamOS. It is refreshed every 30 seconds of monotonic time, and its cached value is included between refreshes. `get_status.sensor_cache` exposes `nvme_period_ms` (30000) and `nvme_age_ms` (null when unavailable). History thus includes held temperature values, not independent per-second sensor conversions. A failed refresh clears the cached value, and suspend/reprobe resets the cache. Other metrics keep the configured sampling cadence; single-threaded slow refreshes can still produce latency spikes, so this is not a P99 guarantee.

## On-disk schema

Files are named by UTC epoch day, `<day>.dscp`, rather than locale-dependent calendar strings. The directory is private to the plugin. A nonblocking exclusive `.monitor.lock` prevents simultaneous writers. The schema uses explicit little-endian encoding, not raw Zig struct memory.

| Offset | Length | Header field |
| --- | --- | --- |
| 0 | 4 | ASCII `DSCP` |
| 4 | 2 | Schema version: 1 |
| 6 | 2 | Record size: 128 |
| 8 | 8 | UTC epoch day |
| 16 | 4 | Metric mask |
| 20 | 8 | Reserved zeros |
| 28 | 4 | CRC32 of the preceding 28 bytes |

Each 128-byte record contains an 8-byte timestamp, 4-byte availability mask, 25 signed 32-bit metric means, four 16-bit CPU/GPU extrema, a 32-bit sample count and a CRC32 of the preceding 124 bytes. The header and record layout are unit-tested. Ten completed minute records trigger a flush; explicit flush and normal socket close also persist partial aggregates. A batch is synced, not every sample. Abrupt kill or power failure may lose the unflushed batch.

Only the current UTC day and six preceding UTC day files are retained; files outside this window are removed (including future-dated files after a backwards clock correction), so day-granularity cleanup is not an exact sliding 168-hour window. A hard cap of 2,880 records per day also bounds repeated short-session flushes. Invalid schema files are preserved and refused. Invalid tails stop restore; opening that known-schema file for append truncates only to the last valid record. Write/sync failure disables further persistence for that monitor lifetime while collection remains in memory.

The initial implementation reads the bounded seven-day archive into the Low ring at startup. Lazy range reads and tail indexes described in the reference proposal are not implemented. Subsequent appends reuse the open daily descriptor and append offset. These are explicit first-version tradeoffs, not claims that the entire original production proposal has been completed.

## rc.3 response additions

`get_device_info` includes nested `battery`, `storage` and `system` objects. Their exact TypeScript contract is in [src/api.ts](../src/api.ts); the native writers are [device_details.zig](../monitor/src/device_details.zig), [battery_details.zig](../monitor/src/battery_details.zig), [storage_details.zig](../monitor/src/storage_details.zig) and [system_details.zig](../monitor/src/system_details.zig). These are bounded on-demand snapshots, not new periodic sampling loops. Missing fields are null. Battery presence can be null for an unreadable presence attribute; cycle count zero remains a real reported zero. Charge/energy use mAh/mWh internally and Ah/Wh in the UI. Filesystem capacity is bytes, memory is KiB, zram counters are bytes, load is x1000 and OS durations are milliseconds.

`get_status.recording` contains `last_persisted_sample_ms`, `last_sync_ms`, `pending_records` and `events_persistence_failed`. The persisted timestamp is the latest aggregate's first sample, not its write time. The sync timestamp is known only after a successful write/sync in the current process; restore does not invent a previous fsync time.

`query_history` adds `coverage` with `estimated:true`, UTC `from_ms`/`to_ms`, source/valid record counts, `estimated_covered_ms`, `uncovered_ms`, first/last valid timestamps, `truncated`, and up to 256 `gaps` with `kind:"no_data"`. Coverage uses the entire selected ring before point reduction, sorts support intervals, and unions their clipped coverage. Mid/Low coverage also includes recent valid raw samples at the configured sampling interval. `live_records` reports their count separately from the selected tier, preventing pending aggregates from becoming false trailing gaps. Windows overlapping the query start contribute their in-range portion. It is not an exact duty-cycle measurement: partial aggregate windows, sampling-interval changes and unavailable samples affect precision. Raw `resolution_ms` follows the current configured sampling interval.

Queries also return `events`, `events_truncated` and `events_persistence_failed`. Event kinds are `suspend_resume` and `clock_change`, with UTC `from_ms`/`to_ms` and `estimated:true`. Only newly observed clock relationships are classified. No historical gap is automatically labeled suspend. The first metric displayed in a monitoring group is explicitly named as the coverage source.

The private `events.v1` sidecar is separate from DSCP v1. Each 32-byte little-endian record contains `DSE1` at 0–3, kind at 4 (1 suspend/resume; 2 clock change), reserved zeros at 5–7, from/to uint64 timestamps at 8 and 16, reserved zeros at 24–27, and CRC32 over bytes 0–27 at 28. At most 128 events are retained. Writes use a temporary file, file sync, atomic rename and directory fsync. Seven-day pruning runs during minute processing. Invalid event data is reported separately from metric persistence failure; unknown/corrupt sidecar data is not represented as authoritative events. Existing metric headers and records do not change.
