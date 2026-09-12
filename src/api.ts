import { callable, addEventListener, removeEventListener } from "@decky/api";
export type Result<T> =
  | { ok: true; data: T }
  | { ok: false; error: { code: string; message: string } };
export type Sample = {
  ts_wall_ms: number;
  available: number;
  [key: string]: number;
};
export interface Status {
  version: string;
  interval_ms: number;
  live_push: boolean;
  uptime_ms: number;
  samples: number;
  sample_total_us: number;
  sample_max_us: number;
  protocol_errors: number;
  hi_len: number;
  mid_len: number;
  lo_len: number;
  persistence_failed: boolean;
  cpu_online: number;
  topology_truncated: boolean;
  recording?: {
    last_persisted_sample_ms: number | null;
    last_sync_ms: number | null;
    pending_records: number;
    events_persistence_failed: boolean;
  };
  latest: Sample;
  settings: { privacy_mask: boolean; interval_ms: number };
  sources: {
    cpu_temperature: string;
    gpu: string;
    battery: string;
    battery_power: string;
  };
  sensor_cache: { nvme_period_ms: number; nvme_age_ms: number | null };
}
export interface Connectivity {
  ready: boolean;
  failed: boolean;
  recommended_ip: string | null;
  interface: string | null;
  ssh: string;
  cef: string;
  reachability_verified: false;
}
export interface BatteryDetails {
  present: boolean | null;
  source: string | null;
  status: string | null;
  capacity_basis: "energy" | "charge" | null;
  full_capacity: number | null;
  design_capacity: number | null;
  capacity_unit: "mWh" | "mAh" | null;
  health_pct_x10: number | null;
  cycle_count: number | null;
  voltage_mv: number | null;
}
export interface StorageDetails {
  filesystems: {
    kind: "system" | "home" | "removable";
    filesystem: string;
    mounted: boolean;
    total_bytes: number | null;
    available_bytes: number | null;
  }[];
  removable_present: boolean;
  detected_removable?: boolean;
  truncated: boolean;
}
export interface SystemDetails {
  boot_elapsed_ms: number | null;
  awake_ms: number | null;
  suspended_ms: number | null;
  load_x1000: (number | null)[];
  memory: {
    available_kib: number | null;
    cached_kib: number | null;
    reclaimable_kib: number | null;
    dirty_kib: number | null;
    writeback_kib: number | null;
    swap_total_kib: number | null;
    swap_free_kib: number | null;
  };
  zram: {
    devices: number;
    original_bytes: number | null;
    compressed_bytes: number | null;
    memory_used_bytes: number | null;
  };
  zswap_enabled: boolean | null;
}
export interface DeviceInfo {
  [key: string]: unknown;
  battery?: BatteryDetails;
  storage?: StorageDetails;
  system?: SystemDetails;
}
export interface Coverage {
  estimated: true;
  from_ms: number;
  to_ms: number;
  source_records: number;
  valid_records: number;
  live_records?: number;
  estimated_covered_ms: number;
  uncovered_ms: number;
  truncated: boolean;
  first_ms: number | null;
  last_ms: number | null;
  gaps: { from_ms: number; to_ms: number; kind: "no_data" }[];
}
export interface HistoryEvent {
  kind: "suspend_resume" | "clock_change";
  from_ms: number;
  to_ms: number;
  estimated: true;
}
export interface History {
  coverage?: Coverage;
  events?: HistoryEvent[];
  events_truncated?: boolean;
  events_persistence_failed?: boolean;
  metric: string;
  resolution_ms: number;
  samples: {
    ts_wall_ms: number;
    value: number | null;
    min?: number;
    max?: number;
  }[];
}
export const api = {
  get_status: callable<[], Result<Status>>("get_status"),
  get_device_info: callable<[], Result<DeviceInfo>>("get_device_info"),
  get_connectivity: callable<[], Result<Connectivity>>("get_connectivity"),
  query_history: callable<
    [{ from: number; to: number; max_points: number; metric: string }],
    Result<History>
  >("query_history"),
  set_config: callable<
    [{ interval_ms?: number; live_push?: boolean; privacy_mask?: boolean }],
    Result<Record<string, never>>
  >("set_config"),
  export_summary: callable<[], Result<{ text: string }>>("export_summary"),
};
export function unwrap<T>(result: Result<T>): T {
  if (!result.ok) throw new Error(result.error.code);
  return result.data;
}
export function isSample(value: unknown): value is Sample {
  if (!value || typeof value !== "object") return false;
  const data = value as Record<string, unknown>;
  return (
    typeof data.ts_wall_ms === "number" &&
    Number.isFinite(data.ts_wall_ms) &&
    typeof data.available === "number" &&
    Object.values(data).every(
      (v) => typeof v === "number" && Number.isFinite(v),
    )
  );
}
export function onMetrics(callback: (data: Sample) => void): () => void {
  const listener = addEventListener<[unknown]>("metrics", (value) => {
    if (isSample(value)) callback(value);
  });
  return () => removeEventListener("metrics", listener);
}
