import { History, Status } from "./api";
import { Row, Section } from "./Controls";
import { t, duration, timeLabel } from "./i18n";
export function HistoryIntegrity({
  history,
  status,
  metricLabel,
}: {
  history?: History;
  status: Status | null;
  metricLabel: string;
}) {
  const c = history?.coverage,
    r = status?.recording;
  const stamp = (v?: number | null) => (v == null ? "—" : timeLabel(v, true));
  const events = (history?.events || []).slice(-8).reverse();
  return (
    <Section title={t("integrity")}>
      <div>
        <Row label={t("source")} value={metricLabel} />
        <Row
          label={t("coverageEstimate")}
          value={c ? duration(c.estimated_covered_ms) : "—"}
        />
        <Row
          label={t("noDataTime")}
          value={c ? duration(c.uncovered_ms) : "—"}
        />
        <Row label={t("coverageAsOf")} value={stamp(c?.to_ms)} />
        <Row
          label={t("lastPersisted")}
          value={stamp(r?.last_persisted_sample_ms)}
        />
        <Row label={t("lastSync")} value={stamp(r?.last_sync_ms)} />
        <Row label={t("pendingRecords")} value={r?.pending_records} />
        {c?.gaps
          .slice(-6)
          .reverse()
          .map((g, i) => (
            <Row
              key={`gap-${i}`}
              label={t("noDataGap")}
              value={`${stamp(g.from_ms)} → ${stamp(g.to_ms)} · ${duration(g.to_ms - g.from_ms)}`}
              long
            />
          ))}
        {events.map((e, i) => (
          <Row
            key={`event-${i}`}
            label={t(
              e.kind === "suspend_resume" ? "suspendResume" : "clockChange",
            )}
            value={`${stamp(e.from_ms)} → ${stamp(e.to_ms)}`}
            long
          />
        ))}
      </div>
      <p className="ds-note">{t("coverageNote")}</p>
      <p className="ds-note">{t("gapLegend")}</p>
      <p className="ds-note">{t("eventNote")}</p>
      {(c?.truncated ||
        (c?.gaps.length || 0) > 6 ||
        (history?.events?.length || 0) > 8 ||
        history?.events_truncated) && (
        <p className="ds-note">{t("limitedEvents")}</p>
      )}
      {(history?.events_persistence_failed || r?.events_persistence_failed) && (
        <p className="ds-error">{t("eventStorageError")}</p>
      )}
    </Section>
  );
}
