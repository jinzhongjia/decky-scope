import { Component, ReactNode } from "react";
import { definePlugin, routerHook } from "@decky/api";
import {
  DialogButton,
  Navigation,
  PanelSectionRow,
  staticClasses,
} from "@decky/ui";
import { FaChartLine } from "react-icons/fa";
import { Overview, Page, ROUTE } from "./Page";
import { stopLive } from "./live";
import { t } from "./i18n";
class Boundary extends Component<{ children: ReactNode }, { failed: boolean }> {
  state = { failed: false };
  static getDerivedStateFromError() {
    return { failed: true };
  }
  render() {
    return this.state.failed ? (
      <div role="alert" style={{ padding: 16 }}>
        DeckScope UI unavailable.{" "}
        <DialogButton onClick={() => this.setState({ failed: false })}>
          {t("refresh")}
        </DialogButton>
      </div>
    ) : (
      this.props.children
    );
  }
}
export default definePlugin(() => {
  routerHook.addRoute(ROUTE, () => (
    <Boundary>
      <Page />
    </Boundary>
  ));
  return {
    name: "DeckScope",
    titleView: <div className={staticClasses.Title}>DeckScope</div>,
    icon: <FaChartLine />,
    content: (
      <Boundary>
        <Overview compact />
        <PanelSectionRow>
          <DialogButton
            onClick={() => {
              Navigation.CloseSideMenus();
              Navigation.Navigate(ROUTE);
            }}
          >
            {t("open")}
          </DialogButton>
        </PanelSectionRow>
      </Boundary>
    ),
    onDismount() {
      stopLive();
      routerHook.removeRoute(ROUTE);
    },
  };
});
