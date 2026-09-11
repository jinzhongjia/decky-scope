import { useEffect, useState } from "react";
import { api, isSample, onMetrics, Sample, Status, unwrap } from "./api";
import { appendRecent } from "./trends";
let latest: Sample | null = null;
let status: Status | null = null;
let recent: Sample[] = [];
let error = "";
let off: (() => void) | null = null;
const listeners = new Set<() => void>();
let chain: Promise<unknown> = Promise.resolve();
const notify = () => listeners.forEach((fn) => fn());
function sync() {
  chain = chain
    .catch(() => {})
    .then(async () => {
      const active = listeners.size > 0;
      unwrap(await api.set_config({ live_push: active }));
      if (active) {
        status = unwrap(await api.get_status());
        if (isSample(status.latest)) {
          latest = status.latest;
          recent = appendRecent(recent, latest);
        }
        error = "";
        notify();
      }
    })
    .catch((reason) => {
      error = String(reason);
      notify();
    });
}
export function useLive() {
  const [, force] = useState(0);
  useEffect(() => {
    const listener = () => force((n) => n + 1);
    listeners.add(listener);
    if (listeners.size === 1) {
      off = onMetrics((sample) => {
        latest = sample;
        recent = appendRecent(recent, sample);
        error = "";
        notify();
      });
      sync();
    }
    return () => {
      listeners.delete(listener);
      if (listeners.size === 0) {
        off?.();
        off = null;
        sync();
      }
    };
  }, []);
  return { latest, status, recent, error, refresh: sync };
}
export function stopLive() {
  listeners.clear();
  off?.();
  off = null;
  sync();
}
