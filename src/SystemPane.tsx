import { useRef, useState } from "react";
import { DialogButton } from "@decky/ui";
import { api, unwrap } from "./api";
import { copyText } from "./clipboard";
import { useDetails } from "./useDetails";
import { Actions, Row, Section, Segments } from "./Controls";
import { formatMetric as f, listenerLabel, t } from "./i18n";
import { SystemDetails, DetailPane } from "./SystemDetails";
export function SystemPane() {
  const { device, status, network, error, loading, refresh } = useDetails();
  const [pane, setPane] = useState<DetailPane>("device");
  const owner = useRef<HTMLDivElement>(null);
  const [notice, setNotice] = useState(""),
    [summary, setSummary] = useState(""),
    [actionError, setActionError] = useState("");
  const get = (key: string) =>
    typeof device?.[key] === "string" ? String(device[key]) : "";
  const privacy = status?.settings.privacy_mask ?? true;
  const title =
    get("profile") === "steam_deck_oled"
      ? "Steam Deck OLED"
      : get("profile") === "steam_deck_lcd"
        ? "Steam Deck LCD"
        : get("product") || t("customDevice");
  async function togglePrivacy() {
    try {
      unwrap(await api.set_config({ privacy_mask: !privacy }));
      setActionError("");
      refresh();
    } catch {
      setActionError(t("nativeError"));
    }
  }
  async function copy(kind: "summary" | "ip") {
    try {
      const text =
        kind === "summary"
          ? unwrap(await api.export_summary()).text
          : network?.recommended_ip;
      if (!text) return;
      if (kind === "summary") setSummary(text);
      await copyText(text, owner.current?.ownerDocument);
      setNotice(t("copied"));
      setActionError("");
    } catch {
      setNotice("");
      setActionError(t("copyFailed"));
    }
  }
  return (
    <div ref={owner}>
      {loading && !device ? (
        <div className="ds-loading">{t("loading")}</div>
      ) : (
        <>
          <div className="ds-intro">
            <div className="ds-device-name">{title}</div>
            <span className="ds-tag">
              {get("os_name") || "—"} {get("os_version")}
            </span>
          </div>
          <div className="ds-intro">
            <Segments
              label={t("system")}
              className="ds-ranges"
              value={pane}
              onChange={setPane}
              options={[
                { value: "device", label: t("deviceTab") },
                { value: "storage", label: t("storageTab") },
                { value: "battery", label: t("battery") },
                { value: "runtime", label: t("runtimeTab") },
              ]}
            />
          </div>
          {pane === "device" ? (
            <>
              <Section title={t("operatingSystem")}>
                <div>
                  <Row label={t("os")} value={get("os_name")} />
                  <Row label={t("osVersion")} value={get("os_version")} />
                  <Row label={t("build")} value={get("os_build")} />
                  <Row label={t("kernel")} value={get("kernel")} long />
                  <Row label={t("architecture")} value={get("arch")} />
                </div>
              </Section>
              <Section title={t("hardware")}>
                <div>
                  <Row label={t("processor")} value={get("cpu_model")} long />
                  <Row label={t("logicalCpu")} value={status?.cpu_online} />
                  <Row
                    label={t("physicalMemory")}
                    value={
                      status?.latest?.mem_total_mb
                        ? `${(status.latest.mem_total_mb / 1024).toFixed(2)} GiB`
                        : "—"
                    }
                  />
                  <Row label={t("manufacturer")} value={get("vendor")} />
                  <Row
                    label={t("model")}
                    value={get("product") || get("board")}
                  />
                  <Row label={t("firmware")} value={get("bios")} />
                </div>
              </Section>
              <Section title={t("connection")}>
                <div className="ds-card">
                  <div className="ds-topline">
                    <span>IP · {network?.interface || "—"}</span>
                    <span>{privacy ? t("masked") : "IPv4 / IPv6"}</span>
                  </div>
                  <div
                    className={`ds-address${privacy ? " ds-address-muted" : ""}`}
                  >
                    {privacy
                      ? "•••.•••.•••.•••"
                      : network?.recommended_ip || "—"}
                  </div>
                  <Actions>
                    <DialogButton
                      className="ds-action"
                      onClick={() => void togglePrivacy()}
                      disabled={!status}
                    >
                      {privacy ? t("showIp") : t("hideIp")}
                    </DialogButton>
                    <DialogButton
                      className="ds-action"
                      onClick={() => void copy("ip")}
                      disabled={!network?.recommended_ip}
                    >
                      {t("copyIp")}
                    </DialogButton>
                  </Actions>
                </div>
                <div>
                  <Row label="SSH · 22" value={listenerLabel(network?.ssh)} />
                  <Row label="CEF · 8080" value={listenerLabel(network?.cef)} />
                </div>
                <p className="ds-note">{t("addressNote")}</p>
              </Section>
              <Section title={t("source")}>
                <div>
                  <Row label="CPU" value={status?.sources.cpu_temperature} />
                  <Row label="GPU" value={status?.sources.gpu} />
                  <Row label={t("battery")} value={status?.sources.battery} />
                  <Row
                    label={t("batteryRate")}
                    value={status?.sources.battery_power}
                  />
                  <Row
                    label={t("nvmeTemp")}
                    value={f("nvme_temp_mc", status?.latest?.nvme_temp_mc)}
                  />
                </div>
              </Section>
            </>
          ) : (
            <SystemDetails device={device} pane={pane} />
          )}
          <Section title={t("about")}>
            <div>
              <Row label="DeckScope" value={get("monitor_version")} />
              <Row label="Decky Loader" value={get("decky_version")} />
            </div>
            <p className="ds-note">{t("privacyNote")}</p>
            <Actions>
              <DialogButton
                className="ds-action"
                onClick={() => void copy("summary")}
              >
                {t("copy")}
              </DialogButton>
              <DialogButton className="ds-action" onClick={refresh}>
                {t("refresh")}
              </DialogButton>
            </Actions>
          </Section>
        </>
      )}
      {(error || actionError) && (
        <div className="ds-error" role="alert">
          {actionError || error}
        </div>
      )}
      {notice && (
        <p className="ds-success" role="status">
          {notice}
        </p>
      )}
      {summary && <pre className="ds-summary">{summary}</pre>}
    </div>
  );
}
