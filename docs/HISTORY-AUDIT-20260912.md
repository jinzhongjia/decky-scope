# Recording and History Audit — 2026-09-12

**Conclusion: awake-time collection, history queries and normal batch persistence were functioning during this read-only audit. The sparse half-hour chart was explained by system suspend, not by a stopped collector.** Runtime version was `0.1.0-rc.2` on Galileo. All times below are UTC+8 unless explicitly marked UTC.[1]

## Why the half-hour chart was nearly empty

The system journal recorded suspend at **14:09:48** and resume at **16:06:07**. At the user's approximately 16:07 observation, the previous thirty wall-clock minutes contained only about one minute of awake sampling. The graph uses a wall-clock window; it does not concatenate thirty minutes of awake execution or invent values for suspended time.

At 16:10:01, a thirty-minute backend query returned 235 timestamps, all between 16:06:07.703 and 16:10:01.577. CPU had 234 valid values because the first post-resume sample established a fresh counter baseline. GPU and APU power each had 235 valid values. GPU's reported zero was a real supplied value, not an unavailable field replaced with zero. Six-hour queries contained earlier records and the expected sleep gaps.

| System suspend | System resume | Interpretation |
| --- | --- | --- |
| 12:15:48 | 12:49:58 | Journal interval aligns with the historical gap |
| 13:05:38 | 13:09:34 | Journal interval aligns with the historical gap |
| 14:09:48 | 16:06:07 | Explains the sparse half-hour chart |

The native monitor reported three resumes and zero clock changes. The actual QAM was later observed in its six-hour view, with 459 valid rendered points per chart spanning old and new data. That was a read of this plugin's chart props; no range, view, setting or focus was changed by this audit.

## Recording and durability checks

| Check | Result |
| --- | --- |
| Native sample count | Increased from 9,005 to 9,426 |
| Current metric availability | All 25 current metric bits were present |
| Protocol errors / invalid history files | Both remained zero |
| Persistence failure flag | Remained false |
| Existing disk records before the delayed check | 322 records across two UTC-day files; all CRCs valid |
| Disk records after the normal batch | 332 records; headers, record CRCs and record alignment all valid |
| New batch | 198 → 208 records in `20708.dscp` |
| Native bytes-written counter | 19,200 → 20,480 bytes |
| File/directory permissions | History directory 0700; history files 0600 |
| Plugin log | The latest log contained `monitor ready` at 11:04:44, with no later error in that log |

The post-resume records reached disk through the existing ten-minute-record batch policy. The audit used one bounded wait and one follow-up read. It did not force `flush`, restart the monitor, disconnect the bridge or change configuration. The newest persisted record in the changed file was **2026-09-12T16:14:44.577000+08:00**. Records newer than the last normal batch can still be memory-only; abrupt termination can lose that pending batch.[2]

The older UTC-day file contains 29 early records without battery-power values, consistent with the previously documented pre-fallback implementation. The current-day file had all 25 metrics available in every inspected aggregate. This is not a claim that every historical version recorded every field, or that sensor readings were independently calibrated.

## Scope and cleanup

Only reads and a bounded task-owned sleep inhibitor/tunnel were used. There was no sideload, Loader restart, fault injection, physical suspend test, touch investigation, UI input or clipboard operation. The user's open QAM and configuration were left untouched. The owned sleep inhibitor and SSH/CDP tunnel were released before this record was finalized. No permanent power or service setting changed.

This is evidence of the currently observed recording path, not a 48-hour endurance result, cross-device certification, full sensor-accuracy test or store approval. No runtime code fix was needed to explain the reported sparse half-hour window.

## References

[1]: tooling/history-audit-20260912.json "Sanitized real-device status, history coverage, journal intervals and persistence verification"
[2]: PROTOCOL.md "Minute aggregation, batched persistence and abrupt-loss boundaries"
