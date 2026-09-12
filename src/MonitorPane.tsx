import { useEffect, useMemo, useRef, useState } from "react";
import { DialogButton } from "@decky/ui";
import { api, History, unwrap } from "./api";
import { useLive } from "./live";
import { mergeTrend, validateHistory } from "./trends";
import { HistoryIntegrity } from "./HistoryIntegrity";
import { MiniChart } from "./MiniChart";
import { MonitorPicker, MonitorDisclosure, PickerMode } from "./MonitorPicker";
import { monitorGroups } from "./monitorMetrics";
import { formatMetric as f, t, timeLabel, duration } from "./i18n";
export function MonitorPane() {
  const { latest, status, recent, error, refresh } = useLive();
  const [metric, setMetric] = useState("cpu_pct_x10");
  const [picker, setPicker] = useState<PickerMode>(null);
  const [integrityOpen, setIntegrityOpen] = useState(false);
  const [infoOpen, setInfoOpen] = useState(false);
  const [range, setRange] = useState(300000),
    [revision, setRevision] = useState(0);
  const requestedAt = useRef(0);
  const selected = Object.values(monitorGroups())
    .flatMap((group) => group.items)
    .find((item) => item.metric === metric)!;
  const [history, setHistory] = useState<Record<string, History>>({}),
    [until, setUntil] = useState(Date.now()),
    [historyError, setHistoryError] = useState(""),
    [loading, setLoading] = useState(true);
  const metrics = [metric];
  const metricSignature = metrics.join(",");
  useEffect(() => {
    let active = true;
    const to = Date.now();
    requestedAt.current = to;
    refresh();
    setLoading(true);
    setHistoryError("");
    const keys = metricSignature.split(",");
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
  }, [range, metricSignature, revision, refresh]);
  // Only react to incoming live data, never add a background/frontend polling timer.
  useEffect(() => {
    if (
      !loading &&
      latest &&
      (latest.ts_wall_ms - requestedAt.current >= 60000 ||
        latest.ts_wall_ms < requestedAt.current - 10000)
    ) {
      requestedAt.current = latest.ts_wall_ms;
      setRevision((n) => n + 1);
    }
  }, [latest?.ts_wall_ms, loading]);
  const to = Math.max(until, latest?.ts_wall_ms || 0),
    from = to - range;
  const series = useMemo(
    () =>
      Object.fromEntries(
        metrics.map((metric) => [
          metric,
          mergeTrend(history[metric] || null, recent, metric, from, to),
        ]),
      ),
    [history, recent, metricSignature, from, to],
  );
  const plot = (metric: string, color: string) => (
    <MiniChart
      points={series[metric]}
      metric={metric}
      color={color}
      from={from}
      to={to}
      height={116}
      gaps={history[metric]?.coverage?.gaps}
      events={history[metric]?.events}
      gapMs={Math.max(
        15000,
        (history[metric]?.resolution_ms || 1000) * 3,
        range / 60,
      )}
    />
  );
  const coverage = history[metric]?.coverage;
  const reading = f(metric, latest?.[metric]);
  return (
    <div className="ds-monitor ds-monitor-focused">
      <MonitorPicker
        metric={metric}
        range={range}
        mode={picker}
        onMode={setPicker}
        onMetric={setMetric}
        onRange={setRange}
      />
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
      {!picker && (
        <>
          <section className="ds-primary-metric" aria-label={selected.label}>
            <div className="ds-primary-reading">
              <strong>{reading}</strong>
              <span>
                {selected.secondary
                  ? f(selected.secondary, latest?.[selected.secondary])
                  : t("now")}
              </span>
            </div>
            {plot(metric, "#4eafff")}
            <div className="ds-chart-caption">
              <span>{timeLabel(from, range > 86400000)}</span>
              <span>
                {loading ? t("loading") : timeLabel(to, range > 86400000)}
              </span>
            </div>
            {selected.note && (
              <p className="ds-note ds-metric-note">{selected.note}</p>
            )}
          </section>
          {historyError && (
            <div className="ds-error" role="alert">
              {historyError}
            </div>
          )}
          <div className="ds-monitor-status">
            <span className="ds-record">
              <i className="ds-dot" />
              {status ? t("recording") : t("loading")}
            </span>
            <span>{status ? `${status.interval_ms / 1000} s` : ""}</span>
          </div>
          <MonitorDisclosure
            label={t("integrity")}
            summary={
              coverage
                ? `${t("coverageShort")} ≈ ${duration(coverage.estimated_covered_ms)}`
                : undefined
            }
            open={integrityOpen}
            onToggle={() => setIntegrityOpen((v) => !v)}
          >
            <HistoryIntegrity
              history={history[metric]}
              status={status}
              metricLabel={selected.label}
              showTitle={false}
            />
          </MonitorDisclosure>
          <MonitorDisclosure
            label={t("chartDetails")}
            open={infoOpen}
            onToggle={() => setInfoOpen((v) => !v)}
          >
            <div className="ds-chart-details">
              <p className="ds-note">
                {history[metric]?.resolution_ms > (status?.interval_ms || 1000)
                  ? t("sampleMean")
                  : t("sampleRaw")}
              </p>
              <p className="ds-note">{t("backgroundNote")}</p>
            </div>
          </MonitorDisclosure>
          <DialogButton
            className="ds-action ds-monitor-refresh"
            onClick={() => {
              refresh();
              setRevision((n) => n + 1);
            }}
          >
            {t("refreshHistory")}
          </DialogButton>
        </>
      )}
    </div>
  );
}
