import { useEffect, useRef, useState } from "react";
import type { ReactNode } from "react";
import { DialogButton, Focusable } from "@decky/ui";
import {
  FaChevronDown,
  FaChevronUp,
  FaChevronLeft,
  FaChevronRight,
  FaCheck,
} from "react-icons/fa";
import { monitorGroups } from "./monitorMetrics";
import { t } from "./i18n";
export type PickerMode = "metric" | "range" | null;
export function MonitorPicker({
  metric,
  range,
  mode,
  onMode,
  onMetric,
  onRange,
}: {
  metric: string;
  range: number;
  mode: PickerMode;
  onMode: (v: PickerMode) => void;
  onMetric: (v: string) => void;
  onRange: (v: number) => void;
}) {
  const groups = monitorGroups();
  const currentGroup = Object.keys(groups).find((key) =>
    groups[key].items.some((item) => item.metric === metric),
  )!;
  const selected = groups[currentGroup].items.find(
    (item) => item.metric === metric,
  )!;
  const [group, setGroup] = useState<string | null>(currentGroup);
  const metricRef = useRef<HTMLDivElement>(null),
    rangeRef = useRef<HTMLDivElement>(null);
  const categoryRefs = useRef<Record<string, HTMLDivElement | null>>({});
  const itemRefs = useRef<Record<string, HTMLDivElement | null>>({});
  const levelTarget = useRef<{
    kind: "category" | "metric";
    key: string;
  } | null>(null);
  const returning = useRef<"metric" | "range" | null>(null);
  const ranges = [
    { value: 300000, label: t("fiveMin") },
    { value: 1800000, label: t("halfHour") },
    { value: 21600000, label: t("sixHour") },
    { value: 604800000, label: t("sevenDays") },
  ];
  // Restore only after an explicit selection, never when samples update.
  useEffect(() => {
    if (mode === null && returning.current) {
      (returning.current === "metric" ? metricRef : rangeRef).current?.focus();
      returning.current = null;
    }
  }, [mode]);
  // A level transition is user-driven. Live sample updates never move focus.
  useEffect(() => {
    if (mode !== "metric" || !levelTarget.current) return;
    const { kind, key } = levelTarget.current;
    (kind === "category" ? categoryRefs : itemRefs).current[key]?.focus();
    levelTarget.current = null;
  }, [mode, group]);
  const enterGroup = (value: string) => {
    const item =
      groups[value].items.find((item) => item.metric === metric) ||
      groups[value].items[0];
    levelTarget.current = { kind: "metric", key: item.metric };
    setGroup(value);
  };
  const backToCategories = () => {
    levelTarget.current = { kind: "category", key: group || currentGroup };
    setGroup(null);
  };
  const chooseMetric = (value: string) => {
    returning.current = "metric";
    onMetric(value);
    onMode(null);
  };
  const chooseRange = (value: number) => {
    returning.current = "range";
    onRange(value);
    onMode(null);
  };
  return (
    <>
      <Focusable className="ds-monitor-toolbar" flow-children="horizontal">
        <DialogButton
          ref={metricRef}
          className="ds-metric-trigger"
          aria-expanded={mode === "metric"}
          onClick={() => {
            if (mode !== "metric") {
              levelTarget.current = { kind: "metric", key: metric };
              setGroup(currentGroup);
            }
            onMode(mode === "metric" ? null : "metric");
          }}
        >
          <span>{selected.label}</span>
          {mode === "metric" ? <FaChevronUp /> : <FaChevronDown />}
        </DialogButton>
        <DialogButton
          ref={rangeRef}
          className="ds-range-trigger"
          aria-expanded={mode === "range"}
          onClick={() => onMode(mode === "range" ? null : "range")}
        >
          <span>{ranges.find((r) => r.value === range)?.label}</span>
          {mode === "range" ? <FaChevronUp /> : <FaChevronDown />}
        </DialogButton>
      </Focusable>
      {mode === "metric" && (
        <div
          className="ds-metric-picker"
          data-picker-level={group === null ? "categories" : "metrics"}
        >
          {group === null ? (
            <>
              <h3>{t("chooseCategory")}</h3>
              <div className="ds-metric-options ds-category-options">
                {Object.entries(groups).map(([key, category]) => (
                  <DialogButton
                    key={key}
                    ref={(node) => {
                      categoryRefs.current[key] = node;
                    }}
                    className="ds-action ds-category-option"
                    onClick={() => enterGroup(key)}
                  >
                    <span>{category.label}</span>
                    <FaChevronRight aria-hidden="true" />
                  </DialogButton>
                ))}
              </div>
            </>
          ) : (
            <>
              <DialogButton
                className="ds-action ds-category-back"
                onClick={backToCategories}
              >
                <FaChevronLeft aria-hidden="true" />
                <span>{t("backToCategories")}</span>
              </DialogButton>
              <h3>
                {t("groupMetricTitle").replace("{group}", groups[group].label)}
              </h3>
              <div className="ds-metric-options">
                {groups[group].items.map((item) => (
                  <DialogButton
                    key={item.metric}
                    ref={(node) => {
                      itemRefs.current[item.metric] = node;
                    }}
                    className="ds-action ds-metric-option"
                    aria-pressed={metric === item.metric}
                    onClick={() => chooseMetric(item.metric)}
                  >
                    <span>{item.label}</span>
                    {metric === item.metric && <FaCheck aria-hidden="true" />}
                  </DialogButton>
                ))}
              </div>
            </>
          )}
        </div>
      )}
      {mode === "range" && (
        <div className="ds-range-picker">
          <h3>{t("chooseRange")}</h3>
          <div className="ds-metric-options">
            {ranges.map((item) => (
              <DialogButton
                key={item.value}
                className="ds-action ds-range-option"
                aria-pressed={range === item.value}
                onClick={() => chooseRange(item.value)}
              >
                <span>{item.label}</span>
                {range === item.value && <FaCheck />}
              </DialogButton>
            ))}
          </div>
        </div>
      )}
    </>
  );
}
export function MonitorDisclosure({
  label,
  summary,
  open,
  onToggle,
  children,
}: {
  label: string;
  summary?: string;
  open: boolean;
  onToggle: () => void;
  children: ReactNode;
}) {
  return (
    <div className="ds-monitor-disclosure">
      <DialogButton
        className="ds-action ds-disclosure-trigger"
        aria-expanded={open}
        onClick={onToggle}
      >
        <span>{label}</span>
        <span className="ds-disclosure-end">
          {summary}
          {open ? <FaChevronUp /> : <FaChevronDown />}
        </span>
      </DialogButton>
      {open && children}
    </div>
  );
}
