import { useState } from "react";
import { DialogButton, ToggleField } from "@decky/ui";
import { api, unwrap } from "./api";
import { useDetails } from "./useDetails";
import { Row, Section, Segments } from "./Controls";
import { duration, t } from "./i18n";
export function SettingsPane() {
  const { status, error, loading, refresh } = useDetails();
  const [saving, setSaving] = useState(false),
    [issue, setIssue] = useState("");
  async function update(value: {
    interval_ms?: number;
    privacy_mask?: boolean;
  }) {
    setSaving(true);
    setIssue("");
    try {
      unwrap(await api.set_config(value));
      refresh();
    } catch {
      setIssue(t("nativeError"));
    } finally {
      setSaving(false);
    }
  }
  if (!status && loading)
    return <div className="ds-loading">{t("loading")}</div>;
  return (
    <>
      <Section title={t("interval")}>
        <div className="ds-select">
          <Segments
            label={t("interval")}
            className="ds-ranges ds-interval"
            value={status?.settings.interval_ms || 1000}
            disabled={!status || saving}
            options={[
              { value: 500, label: "0.5 s" },
              { value: 1000, label: "1 s" },
              { value: 2000, label: "2 s" },
              { value: 5000, label: "5 s" },
            ]}
            onChange={(interval_ms) => void update({ interval_ms })}
          />
        </div>
        <p className="ds-note">{t("backgroundNote")}</p>
      </Section>
      <Section title={t("privacyGroup")}>
        <ToggleField
          label={t("privacy")}
          checked={status?.settings.privacy_mask ?? true}
          disabled={!status || saving}
          onChange={(privacy_mask) => void update({ privacy_mask })}
        />
        <p className="ds-note">{t("privacyNote")}</p>
      </Section>
      <Section title={t("storage")}>
        <div>
          <Row label={t("records")} value={status?.lo_len} />
          <Row label={t("monitoring")} value={status?.samples} />
          <Row
            label={t("uptime")}
            value={status ? duration(status.uptime_ms) : "—"}
          />
        </div>
        <p className="ds-note">{t("historyNote")}</p>
        {status?.persistence_failed && (
          <p className="ds-error" role="alert">
            {t("storageError")}
          </p>
        )}
      </Section>
      <Section title={t("about")}>
        <div>
          <Row label={t("version")} value={status?.version} />
        </div>
        <p className="ds-note">
          {t("powerUnavailable")}
          <br />
          {t("batterySigned")}
        </p>
      </Section>
      {(issue || error) && (
        <div className="ds-error" role="alert">
          {issue || error}
        </div>
      )}
      <div className="ds-intro">
        <DialogButton className="ds-action" onClick={refresh}>
          {t("refresh")}
        </DialogButton>
      </div>
    </>
  );
}
