import { useEffect, useState } from "react";
import {
  DialogButton,
  Dropdown,
  PanelSection,
  PanelSectionRow,
  Tabs,
  ToggleField,
} from "@decky/ui";
import { api, Connectivity, DeviceInfo, History, Status, unwrap } from "./api";
import { formatMetric, t, TextKey } from "./i18n";
import { useLive } from "./live";
import { Timeline } from "./Timeline";
export const ROUTE = "/deckscope";
const metrics: { key: string; label: TextKey }[] = [
  { key: "cpu_pct_x10", label: "cpu" },
  { key: "gpu_pct", label: "gpu" },
  { key: "mem_used_mb", label: "memory" },
  { key: "cpu_temp_mc", label: "temperature" },
  { key: "apu_power_mw", label: "power" },
  { key: "battery_pct", label: "battery" },
  { key: "psi_cpu_some_x100", label: "pressure" },
];
export function ErrorMessage({ text }: { text: string }) {
  return text ? (
    <div
      role="alert"
      style={{ color: "#ffb7a9", padding: "8px 0", overflowWrap: "anywhere" }}
    >
      {text}
    </div>
  ) : null;
}
export function Overview({ compact = false }: { compact?: boolean }) {
  const { latest, error, refresh } = useLive();
  return (
    <PanelSection title={compact ? "DeckScope" : t("overview")}>
      <ErrorMessage text={error} />
      <div
        style={{
          display: "grid",
          gridTemplateColumns: compact ? "1fr" : "repeat(3, minmax(0, 1fr))",
          gap: 10,
        }}
      >
        {metrics.slice(0, compact ? 4 : metrics.length).map((metric) => (
          <div
            key={metric.key}
            style={{ padding: 12, borderRadius: 6, background: "#172b38" }}
          >
            <div style={{ color: "#a9bbca", fontSize: 13 }}>
              {t(metric.label)}
            </div>
            <div style={{ fontSize: compact ? 20 : 28, marginTop: 5 }}>
              {formatMetric(metric.key, latest?.[metric.key])}
            </div>
          </div>
        ))}
      </div>
      <PanelSectionRow>
        <DialogButton onClick={refresh}>{t("refresh")}</DialogButton>
      </PanelSectionRow>
      {!compact && (
        <p style={{ color: "#a9bbca", fontSize: 14 }}>{t("noSessions")}</p>
      )}
    </PanelSection>
  );
}
function HistoryPage() {
  const [metric, setMetric] = useState("cpu_pct_x10"),
    [minutes, setMinutes] = useState(30);
  const [data, setData] = useState<History | null>(null),
    [error, setError] = useState("");
  const [revision, refresh] = useState(0);
  useEffect(() => {
    let active = true;
    setData(null);
    setError("");
    const to = Date.now();
    api
      .query_history({
        from: to - minutes * 60000,
        to,
        metric,
        max_points: 600,
      })
      .then(unwrap)
      .then((value) => {
        if (active) setData(value);
      })
      .catch((reason) => {
        if (active) setError(String(reason));
      });
    return () => {
      active = false;
    };
  }, [metric, minutes, revision]);
  return (
    <PanelSection title={t("history")}>
      <div style={{ display: "flex", gap: 16 }}>
        <Dropdown
          menuLabel={t("metric")}
          selectedOption={metric}
          rgOptions={metrics.map((m) => ({ data: m.key, label: t(m.label) }))}
          onChange={(v) => setMetric(v.data)}
        />
        <Dropdown
          menuLabel={t("time")}
          selectedOption={minutes}
          rgOptions={[
            { data: 30, label: "30 min" },
            { data: 360, label: "6 h" },
            { data: 10080, label: "7 d" },
          ]}
          onChange={(v) => setMinutes(v.data)}
        />
        <DialogButton onClick={() => refresh((n) => n + 1)}>
          {t("refresh")}
        </DialogButton>
      </div>
      <ErrorMessage text={error} />
      <Timeline data={data} />
    </PanelSection>
  );
}
function DevicePage() {
  const [device, setDevice] = useState<DeviceInfo | null>(null),
    [status, setStatus] = useState<Status | null>(null);
  const [network, setNetwork] = useState<Connectivity | null>(null),
    [privacy, setPrivacy] = useState(true);
  const [error, setError] = useState(""),
    [summary, setSummary] = useState(""),
    [notice, setNotice] = useState("");
  const [revision, refresh] = useState(0);
  useEffect(() => {
    let active = true;
    Promise.all([
      api.get_device_info().then(unwrap),
      api.get_status().then(unwrap),
      api.get_connectivity().then(unwrap),
    ])
      .then(([d, s, n]) => {
        if (!active) return;
        setDevice(d);
        setStatus(s);
        setNetwork(n);
        setPrivacy(s.settings.privacy_mask);
        setError("");
      })
      .catch((reason) => {
        if (active) setError(String(reason));
      });
    return () => {
      active = false;
    };
  }, [revision]);
  const update = async (value: {
    privacy_mask?: boolean;
    interval_ms?: number;
  }) => {
    try {
      unwrap(await api.set_config(value));
      refresh((n) => n + 1);
    } catch (reason) {
      setError(String(reason));
    }
  };
  const copy = async () => {
    try {
      const result = unwrap(await api.export_summary());
      setSummary(result.text);
      try {
        await navigator.clipboard.writeText(result.text);
        setNotice(t("copied"));
      } catch {
        setNotice(t("copyFailed"));
      }
    } catch (reason) {
      setError(String(reason));
    }
  };
  return (
    <PanelSection title={t("device")}>
      <ErrorMessage text={error} />
      <ToggleField
        label={t("privacy")}
        checked={privacy}
        onChange={(v) => void update({ privacy_mask: v })}
      />
      <div
        style={{
          margin: "12px 0",
          padding: 16,
          background: "#172b38",
          borderRadius: 6,
        }}
      >
        <strong style={{ fontSize: 23 }}>
          {privacy
            ? "•••.•••.•••.•••"
            : network?.recommended_ip || t("unavailable")}
        </strong>
        <div>
          {network?.interface || "—"} · SSH: {network?.ssh || "—"} · CEF:{" "}
          {network?.cef || "—"}
        </div>
        <p style={{ color: "#a9bbca", fontSize: 13 }}>{t("addressNote")}</p>
      </div>
      {device && (
        <div
          style={{
            display: "grid",
            gridTemplateColumns: "1fr 1fr",
            gap: 10,
            overflowWrap: "anywhere",
          }}
        >
          {[
            "profile",
            "os_name",
            "os_version",
            "os_build",
            "kernel",
            "bios",
            "monitor_version",
            "decky_version",
          ].map((key) => (
            <div key={key}>
              <span style={{ color: "#a9bbca" }}>{key}</span>
              <br />
              {String(device[key] ?? "—")}
            </div>
          ))}
        </div>
      )}
      <p>
        CPU: {status?.cpu_online ?? "—"} · {t("monitoring")}:{" "}
        {status?.samples ?? "—"}
      </p>
      <p style={{ color: "#a9bbca", fontSize: 13 }}>{t("threadNote")}</p>
      <p>
        {t("source")}: CPU {status?.sources.cpu_temperature || "—"} / GPU{" "}
        {status?.sources.gpu || "—"} / Battery {status?.sources.battery || "—"}
      </p>
      {status?.persistence_failed && <ErrorMessage text={t("storageError")} />}
      <Dropdown
        menuLabel={t("interval")}
        selectedOption={status?.settings.interval_ms || 1000}
        rgOptions={[1000, 2000, 5000].map((ms) => ({
          data: ms,
          label: `${ms / 1000} s`,
        }))}
        onChange={(v) => void update({ interval_ms: v.data })}
      />
      <PanelSectionRow>
        <DialogButton onClick={() => void copy()}>{t("copy")}</DialogButton>
      </PanelSectionRow>
      <PanelSectionRow>
        <DialogButton onClick={() => refresh((n) => n + 1)}>
          {t("refresh")}
        </DialogButton>
      </PanelSectionRow>
      <p>{notice}</p>
      {summary && (
        <pre style={{ whiteSpace: "pre-wrap", fontSize: 13 }}>{summary}</pre>
      )}
    </PanelSection>
  );
}
export function Page() {
  const [tab, setTab] = useState("overview");
  return (
    <div
      style={{
        height: "100%",
        boxSizing: "border-box",
        padding: "48px 28px 44px",
        background: "#0d1b26",
        color: "#eef4f8",
        overflow: "auto",
      }}
    >
      <header style={{ marginBottom: 16 }}>
        <strong style={{ fontSize: 24 }}>DeckScope</strong>
        <span style={{ marginLeft: 16, color: "#a9bbca" }}>
          {t("subtitle")}
        </span>
        <div style={{ fontSize: 12, color: "#c4ab76", marginTop: 5 }}>
          {t("partial")}
        </div>
      </header>
      <Tabs
        activeTab={tab}
        onShowTab={setTab}
        tabs={[
          {
            id: "overview",
            title: t("overview"),
            content: tab === "overview" ? <Overview /> : null,
          },
          {
            id: "history",
            title: t("history"),
            content: tab === "history" ? <HistoryPage /> : null,
          },
          {
            id: "device",
            title: t("device"),
            content: tab === "device" ? <DevicePage /> : null,
          },
        ]}
      />
    </div>
  );
}
