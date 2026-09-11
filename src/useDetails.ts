import { useCallback, useEffect, useState } from "react";
import { api, Connectivity, DeviceInfo, Status, unwrap } from "./api";
import { t } from "./i18n";
export function useDetails() {
  const [revision, setRevision] = useState(0);
  const [state, setState] = useState<{
    device: DeviceInfo | null;
    status: Status | null;
    network: Connectivity | null;
    error: string;
    loading: boolean;
  }>({ device: null, status: null, network: null, error: "", loading: true });
  useEffect(() => {
    let active = true;
    setState((previous) => ({ ...previous, loading: true }));
    Promise.allSettled([
      api.get_device_info().then(unwrap),
      api.get_status().then(unwrap),
      api.get_connectivity().then(unwrap),
    ])
      .then(([d, s, n]) => {
        if (!active) return;
        setState({
          device: d.status === "fulfilled" ? d.value : null,
          status: s.status === "fulfilled" ? s.value : null,
          network: n.status === "fulfilled" ? n.value : null,
          error: [d, s, n].some((x) => x.status === "rejected")
            ? t("nativeError")
            : "",
          loading: false,
        });
      })
      .catch(() => {
        if (active)
          setState((previous) => ({
            ...previous,
            error: t("nativeError"),
            loading: false,
          }));
      });
    return () => {
      active = false;
    };
  }, [revision]);
  return {
    ...state,
    refresh: useCallback(() => setRevision((n) => n + 1), []),
  };
}
