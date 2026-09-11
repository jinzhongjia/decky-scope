import { Component, ReactNode, useState } from "react";
import { definePlugin } from "@decky/api";
import { DialogButton, staticClasses } from "@decky/ui";
import { FaChartLine } from "react-icons/fa";
import { MonitorPane } from "./MonitorPane";
import { SystemPane } from "./SystemPane";
import { SettingsPane } from "./SettingsPane";
import { Segments } from "./Controls";
import { stopLive } from "./live";
import { styles } from "./styles";
import { t } from "./i18n";
class Boundary extends Component<{ children: ReactNode }, { failed: boolean }> {
  state = { failed: false };
  static getDerivedStateFromError() {
    return { failed: true };
  }
  render() {
    return this.state.failed ? (
      <div className="ds">
        <p role="alert" className="ds-error">
          DeckScope UI unavailable.
        </p>
        <DialogButton onClick={() => this.setState({ failed: false })}>
          {t("retry")}
        </DialogButton>
      </div>
    ) : (
      this.props.children
    );
  }
}
function Panel() {
  const [view, setView] = useState("monitor");
  return (
    <div className="ds" data-deckscope="qam-only">
      <style>{styles}</style>
      <Segments
        label="DeckScope"
        value={view}
        onChange={setView}
        options={[
          { value: "monitor", label: t("monitor") },
          { value: "system", label: t("system") },
          { value: "settings", label: t("settings") },
        ]}
      />
      {view === "monitor" ? (
        <MonitorPane />
      ) : view === "system" ? (
        <SystemPane />
      ) : (
        <SettingsPane />
      )}
      <footer className="ds-footer">
        <span>DECKSCOPE</span>
        <span>STEAMOS SYSTEM TOOLS</span>
      </footer>
    </div>
  );
}
export default definePlugin(() => ({
  name: "DeckScope",
  titleView: <div className={staticClasses.Title}>DeckScope</div>,
  icon: <FaChartLine />,
  content: (
    <Boundary>
      <Panel />
    </Boundary>
  ),
  onDismount() {
    stopLive();
  },
}));
