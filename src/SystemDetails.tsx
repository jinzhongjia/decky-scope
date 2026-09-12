import { DeviceInfo } from "./api";
import { Row, Section } from "./Controls";
import { t, bytes, kib, duration } from "./i18n";
export type DetailPane = "device" | "storage" | "battery" | "runtime";
const elapsed = (v?: number | null) => (v == null ? "—" : duration(v));
const capacity = (v?: number | null, unit?: string | null) =>
  v == null || !unit
    ? "—"
    : `${(v / 1000).toFixed(2)} ${unit === "mWh" ? "Wh" : "Ah"}`;
export function SystemDetails({
  device,
  pane,
}: {
  device: DeviceInfo | null;
  pane: DetailPane;
}) {
  if (pane === "storage") {
    const s = device?.storage;
    return (
      <Section title={t("storageCapacity")}>
        {s?.filesystems.map((v, i) => (
          <div key={`${v.kind}-${i}`}>
            <Row
              label={`${t(v.kind === "home" ? "homeVolume" : v.kind === "system" ? "systemVolume" : "removableVolume")} ${v.kind === "removable" ? i + 1 : ""}`}
              value={`${v.filesystem} · ${t("mounted")}`}
              long
            />
            <Row label={t("capacityTotal")} value={bytes(v.total_bytes)} />
            <Row
              label={t("capacityAvailable")}
              value={bytes(v.available_bytes)}
            />
          </div>
        ))}
        {!s?.filesystems.some((v) => v.kind === "removable") && (
          <p className="ds-note">
            {s?.removable_present ? t("unmounted") : t("noRemovable")}
          </p>
        )}
        {s?.truncated && <p className="ds-note">{t("limitedEvents")}</p>}
        <p className="ds-note">{t("storageCapacityNote")}</p>
      </Section>
    );
  }
  if (pane === "battery") {
    const b = device?.battery;
    const state = b?.status;
    const label =
      state === "Charging"
        ? t("charging")
        : state === "Discharging"
          ? t("discharging")
          : state === "Full"
            ? t("full")
            : state === "Not charging"
              ? t("notCharging")
              : t("unknown");
    return (
      <Section title={t("batteryDetails")}>
        <div>
          <Row
            label={t("batteryStatus")}
            value={b?.present === false || !b ? "—" : label}
          />
          <Row
            label={t("fullCapacity")}
            value={capacity(b?.full_capacity, b?.capacity_unit)}
          />
          <Row
            label={t("designCapacity")}
            value={capacity(b?.design_capacity, b?.capacity_unit)}
          />
          <Row
            label={t("batteryHealth")}
            value={
              b?.health_pct_x10 == null
                ? "—"
                : `${(b.health_pct_x10 / 10).toFixed(1)}%`
            }
          />
          <Row label={t("cycleCount")} value={b?.cycle_count} />
          <Row
            label={t("voltage")}
            value={
              b?.voltage_mv == null
                ? "—"
                : `${(b.voltage_mv / 1000).toFixed(3)} V`
            }
          />
        </div>
        <p className="ds-note">{t("healthNote")}</p>
      </Section>
    );
  }
  const s = device?.system,
    m = s?.memory,
    z = s?.zram;
  return (
    <>
      <Section title={t("systemRuntime")}>
        <div>
          <Row label={t("systemElapsed")} value={elapsed(s?.boot_elapsed_ms)} />
          <Row label={t("systemAwake")} value={elapsed(s?.awake_ms)} />
          <Row label={t("systemSuspended")} value={elapsed(s?.suspended_ms)} />
          <Row
            label={t("loadAverage")}
            value={s?.load_x1000
              .map((v) => (v == null ? "—" : (v / 1000).toFixed(2)))
              .join(" / ")}
            long
          />
        </div>
        <p className="ds-note">{t("runtimeNote")}</p>
      </Section>
      <Section title={t("memory")}>
        <div>
          <Row label={t("memoryAvailable")} value={kib(m?.available_kib)} />
          <Row label={t("memoryCached")} value={kib(m?.cached_kib)} />
          <Row label={t("memoryReclaimable")} value={kib(m?.reclaimable_kib)} />
          <Row label={t("memoryDirty")} value={kib(m?.dirty_kib)} />
          <Row label={t("memoryWriteback")} value={kib(m?.writeback_kib)} />
          <Row label={t("swapTotal")} value={kib(m?.swap_total_kib)} />
          <Row label={t("swapFree")} value={kib(m?.swap_free_kib)} />
          <Row
            label={t("zramOriginal")}
            value={
              z?.original_bytes == null ? "—" : kib(z.original_bytes / 1024)
            }
          />
          <Row
            label={t("zramCompressed")}
            value={
              z?.compressed_bytes == null ? "—" : kib(z.compressed_bytes / 1024)
            }
          />
          <Row
            label={t("zramMemory")}
            value={
              z?.memory_used_bytes == null
                ? "—"
                : kib(z.memory_used_bytes / 1024)
            }
          />
          <Row
            label={t("zswapEnabled")}
            value={
              s?.zswap_enabled == null
                ? "—"
                : t(s.zswap_enabled ? "enabled" : "disabled")
            }
          />
        </div>
      </Section>
    </>
  );
}
