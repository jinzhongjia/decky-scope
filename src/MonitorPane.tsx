import { useEffect, useMemo, useState } from "react";
import { DialogButton } from "@decky/ui";
import { FaMicrochip, FaLayerGroup, FaBolt } from "react-icons/fa";
import { api, History, unwrap } from "./api";
import { useLive } from "./live";
import { mergeTrend, validateHistory } from "./trends";
import { MiniChart } from "./MiniChart";
import { Segments, Row } from "./Controls";
import { formatMetric as f, t, timeLabel } from "./i18n";
function Reading({ metric, value }: { metric: string; value?: number }) {
  const text = f(metric, value),
    parts = text.split(" ");
  return (
    <div className="ds-value">
      {parts[0]}
      {parts.length > 1 && (
        <span className="ds-unit">{parts.slice(1).join(" ")}</span>
      )}
    </div>
  );
}
export function MonitorPane() {
  const { latest, status, recent, error, refresh } = useLive();
  const [range, setRange] = useState(300000),
    [power, setPower] = useState("apu_power_mw"),
    [revision, setRevision] = useState(0);
  const [history, setHistory] = useState<Record<string, History>>({}),
    [until, setUntil] = useState(Date.now()),
    [historyError, setHistoryError] = useState(""),
    [loading, setLoading] = useState(true);
  useEffect(() => {
    let active = true;
    const to = Date.now();
    setLoading(true);
    setHistoryError("");
    const keys = ["cpu_pct_x10", "gpu_pct", power];
    Promise.all(
      keys.map(async (metric) =>
        validateHistory(
          unwrap(
            await api.query_history({
              from: to - range,
              to,
              max_points: 180,
              metric,
            }),
          ),
          metric,
        ),
      ),
    )
      .then((data) => {
        if (active) {
          setHistory(Object.fromEntries(data.map((h) => [h.metric, h])));
          setUntil(to);
          setLoading(false);
        }
      })
      .catch(() => {
        if (active) {
          setHistoryError(t("chartError"));
          setLoading(false);
        }
      });
    return () => {
      active = false;
    };
  }, [range, power, revision]);
  const to = Math.max(until, latest?.ts_wall_ms || 0),
    from = to - range;
  const series = useMemo(
    () =>
      Object.fromEntries(
        ["cpu_pct_x10", "gpu_pct", power].map((metric) => [
          metric,
          mergeTrend(history[metric] || null, recent, metric, from, to),
        ]),
      ),
    [history, recent, power, from, to],
  );
  const plot = (metric: string, color: string, compact = false) => (
    <MiniChart
      points={series[metric]}
      metric={metric}
      color={color}
      from={from}
      to={to}
      compact={compact}
      gapMs={Math.max(
        15000,
        (history[metric]?.resolution_ms || 1000) * 3,
        range / 60,
      )}
    />
  );
  const memory = latest?.mem_used_mb,
    total = latest?.mem_total_mb;
  const percent =
    memory !== undefined && total
      ? Math.max(0, Math.min(100, (memory / total) * 100))
      : 0;
  return (
    <div className="ds-monitor">
      <div className="ds-topline">
        <span className="ds-record">
          <i className="ds-dot" />
          {status ? t("recording") : t("loading")}
        </span>
        <span>
          {status ? `${status.interval_ms / 1000} s · ` : ""}
          {t("localOnly")}
        </span>
      </div>
      {error && (
        <div className="ds-error" role="alert">
          {t("nativeError")}
        </div>
      )}
      {status?.persistence_failed && (
        <div className="ds-error" role="alert">
          {t("storageError")}
        </div>
      )}
      <Segments
        label={t("history")}
        className="ds-ranges"
        value={range}
        onChange={setRange}
        options={[
          { value: 300000, label: t("fiveMin") },
          { value: 1800000, label: t("halfHour") },
          { value: 21600000, label: t("sixHour") },
          { value: 604800000, label: t("sevenDays") },
        ]}
      />
      <div className="ds-two">
        <section className="ds-card" aria-label="CPU">
          <div className="ds-card-title">
            <span>
              <FaMicrochip />
              CPU
            </span>
            <span className="ds-subvalue">{f("cpu_mhz", latest?.cpu_mhz)}</span>
          </div>
          <Reading metric="cpu_pct_x10" value={latest?.cpu_pct_x10} />
          {plot("cpu_pct_x10", "#4eafff", true)}
        </section>
        <section className="ds-card" aria-label="GPU">
          <div className="ds-card-title">
            <span>
              <FaLayerGroup />
              GPU
            </span>
            <span className="ds-subvalue">{f("gpu_mhz", latest?.gpu_mhz)}</span>
          </div>
          <Reading metric="gpu_pct" value={latest?.gpu_pct} />
          {plot("gpu_pct", "#54dbb5", true)}
        </section>
      </div>
      <section className="ds-card ds-power" aria-label={t("power")}>
        <div className="ds-power-head">
          <span className="ds-card-title">
            <FaBolt />
            {power === "apu_power_mw" ? t("power") : t("batteryRate")}
          </span>
          <Reading metric={power} value={latest?.[power]} />
        </div>
        <Segments
          label={t("power")}
          className="ds-power-modes"
          value={power}
          onChange={setPower}
          options={[
            { value: "apu_power_mw", label: "APU" },
            { value: "battery_rate_mw", label: t("battery") },
          ]}
        />
        {plot(power, "#f1be6b")}
        <div className="ds-note" style={{ margin: "4px 0 0", fontSize: 10 }}>
          {power === "apu_power_mw" ? t("powerNotSystem") : t("batterySigned")}
        </div>
      </section>
      <div className="ds-chart-caption">
        <span>{timeLabel(from, range > 86400000)}</span>
        <span>{loading ? t("loading") : timeLabel(to, range > 86400000)}</span>
      </div>
      {historyError && (
        <div className="ds-error" role="alert">
          {historyError}
        </div>
      )}
      <div className="ds-telemetry">
        <div>
          <Row
            label={t("memory")}
            value={
              memory !== undefined && total
                ? `${(memory / 1024).toFixed(1)} / ${(total / 1024).toFixed(1)} GiB`
                : "—"
            }
          />
        </div>
        <div
          className="ds-progress"
          role="meter"
          aria-label={t("memory")}
          aria-valuemin={0}
          aria-valuemax={100}
          aria-valuenow={percent}
        >
          <span style={{ width: `${percent}%` }} />
        </div>
        <div>
          <Row
            label={t("temperature")}
            value={f("cpu_temp_mc", latest?.cpu_temp_mc)}
          />
          <Row
            label={t("gpuTemp")}
            value={f("gpu_temp_mc", latest?.gpu_temp_mc)}
          />
          <Row label={t("fan")} value={f("fan_rpm", latest?.fan_rpm)} />
          <Row
            label={t("battery")}
            value={`${f("battery_pct", latest?.battery_pct)} · ${f("battery_rate_mw", latest?.battery_rate_mw)}`}
          />
          <Row
            label={t("pressure")}
            value={f("psi_cpu_some_x100", latest?.psi_cpu_some_x100)}
          />
          <Row
            label={t("networkIO")}
            value={`${f("net_rx_kbps", latest?.net_rx_kbps)} / ${f("net_tx_kbps", latest?.net_tx_kbps)}`}
          />
          <Row
            label={t("diskIO")}
            value={`${f("disk_read_kbps", latest?.disk_read_kbps)} / ${f("disk_write_kbps", latest?.disk_write_kbps)}`}
          />
        </div>
      </div>
      <p className="ds-note">
        {Object.values(history).some(
          (h) => h.resolution_ms > (status?.interval_ms || 1000),
        )
          ? t("sampleMean")
          : t("sampleRaw")}
      </p>
      <DialogButton
        className="ds-action"
        onClick={() => {
          refresh();
          setRevision((n) => n + 1);
        }}
      >
        {t("refreshHistory")}
      </DialogButton>
    </div>
  );
}
