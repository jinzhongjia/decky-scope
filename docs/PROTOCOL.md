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
| `get_status` | `{}` | Latest sample, topology, per-thread current CPU values, source names, RRD lengths, sample costs and error counters |
| `get_device_info` | `{}` | OS, build, kernel, BIOS, board, detected profile and monitor version |
| `get_connectivity` | `{}` | Best-effort main-table address/interface selection and local SSH/CEF listener state |
| `set_config` | Optional `interval_ms` 500–5000 and `live_push` boolean | Empty success object |
| `query_history` | `from`, `to` UTC milliseconds; `metric`; `max_points` 1–1200 | Chosen base resolution and bounded single-metric samples |
| `flush` | `{}` | Flush current partial aggregate and pending records; reports write failure |
| `export_summary` | `{}` | Native environment object; the public bridge export applies a narrower whitelist |

The public Decky API contains six methods: all of the above except `flush`. The bridge's `set_config` additionally accepts `privacy_mask`. The bridge's `export_summary` returns a redacted text object rather than the native environment object. The whitelist excludes board names, BIOS strings, hostname, IP, username, serial numbers and user paths. `query_sessions` and `session_mark` are deliberately **not advertised** until session recording is implemented.

The metrics event is enabled by UI reference counting, rate limited to at most 1 Hz, and suppressed inside metric-specific deadbands. Device and history pages query on entry or explicit refresh, not on a timer. The native network cache is refreshed by rtnetlink events; the initial UI connection card refreshes on entry or with its Refresh button. Network-change push events are not yet part of the exposed implementation.

## Metrics and units

The authoritative order of the 25 availability bits is the `Metric` enum in `monitor/src/model.zig`. Unavailable properties are omitted from samples and become `null` in single-metric history queries. A genuine zero remains zero. CPU utilization is percentage times ten; PSI is percentage times one hundred; temperatures are milli-degrees Celsius; power is milliwatts. Memory and throughput use binary units (MiB and KiB/s). `battery_rate_mw` is positive while discharging and negative while charging; it is **not wall power or total system consumption**.

CPU total excludes guest counters already included in user/nice. Counter resets and first observations establish a baseline rather than generating spikes. Current per-thread values support IDs 0–255 and report truncation explicitly beyond that bound. No eight-thread assumption remains. Per-thread history is deferred.

CPU and GPU aggregate records retain min/max plus mean. Other metrics retain their valid-sample arithmetic mean. Means are sample-weighted, not duration-weighted; changing the interval inside an active window can change its weighting. Query reduction currently uses bounded stride selection; it does not promise preservation of every spike when reducing many windows. Cursor navigation and extrema-preserving display decimation remain future work.

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
