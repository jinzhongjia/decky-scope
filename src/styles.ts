// Layout only for controls: Steam owns button colors, focus, borders and animations.
export const styles = `
.ds {
  font-variant-numeric: tabular-nums;
  padding-bottom: 12px;
}
.ds * { box-sizing: border-box; }
.ds-nav, .ds-ranges, .ds-power-modes, .ds-actions {
  display: flex;
  gap: 6px;
}
.ds-nav { margin: 0 16px 12px; }
.ds .ds-nav button, .ds .ds-ranges button, .ds .ds-power-modes button, .ds .ds-action {
  min-width: 0 !important;
  width: auto !important;
  flex: 1 1 0;
  padding-left: 4px !important;
  padding-right: 4px !important;
}
.ds .ds-nav button, .ds .ds-ranges button, .ds .ds-power-modes button {
  min-height: 0 !important;
  padding-top: 5px !important;
  padding-bottom: 5px !important;
  line-height: 20px !important;
  font-size: 13px !important;
}
.ds button[aria-pressed] { position: relative; }
.ds button[aria-pressed=true]::after { content: ""; position: absolute; left: 6px; right: 6px; bottom: 1px; height: 2px; background: #1a9fff; pointer-events: none; }
.ds .ds-action { width: 100% !important; font-size: 13px !important; }
.ds-actions { margin-top: 10px; }
.ds-ranges { margin: 8px 0 12px; }
.ds-power-modes { margin: 8px 0; }
.ds-monitor, .ds-intro { padding: 0 16px; }
.ds-topline { display: flex; justify-content: space-between; gap: 8px; font-size: 12px; color: #b8bcbf; margin-bottom: 8px; }
.ds-record { display: flex; align-items: center; gap: 5px; }
.ds-dot { width: 5px; height: 5px; background: #1a9fff; border-radius: 50%; }
.ds-two { display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); gap: 16px; }
.ds-card { min-width: 0; }
.ds-card-title { display: flex; align-items: center; justify-content: space-between; gap: 4px; font-size: 13px; }
.ds-card-title svg { margin-right: 5px; }
.ds-value { font-size: 24px; font-weight: 600; line-height: 1.25; margin: 5px 0; }
.ds-unit { font-size: 13px; font-weight: normal; margin-left: 3px; }
.ds-subvalue { font-size: 11px; color: #b8bcbf; white-space: nowrap; }
.ds-power { margin-top: 12px; padding-top: 12px; border-top: 1px solid #3d4148; }
.ds-power-head { display: flex; align-items: center; justify-content: space-between; gap: 6px; }
.ds-power .ds-value { margin: 0; }
.ds-chart { position: relative; margin-top: 6px; }
.ds-chart canvas { display: block; }
.ds-chart-scale, .ds-chart-floor { position: absolute; right: 1px; top: 0; font-size: 10px; color: #b8bcbf; pointer-events: none; }
.ds-chart-floor { top: auto; bottom: 0; }
.ds-chart-empty { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; color: #b8bcbf; font-size: 12px; pointer-events: none; }
.ds-chart-caption { display: flex; justify-content: space-between; font-size: 11px; color: #b8bcbf; margin-top: 6px; }
.ds-extra-charts > .ds-card + .ds-card { margin-top: 18px; }
.ds-group-picker { margin-bottom: 12px; }
.ds-telemetry { margin-top: 12px; }
.ds-field-value { overflow-wrap: anywhere; font-size: 13px; }
.ds-device-name { font-size: 18px; font-weight: 600; margin: 4px 0; }
.ds-tag { color: #b8bcbf; font-size: 14px; }
.ds-address { font-size: 18px; overflow-wrap: anywhere; margin: 8px 0; }
.ds-address-muted { color: #b8bcbf; letter-spacing: 1px; }
.ds-note { font-size: 12px; color: #b8bcbf; line-height: 1.5; margin: 10px 0; }
.ds-error { color: #ffc080; font-size: 13px; padding: 8px 0; overflow-wrap: anywhere; }
.ds-success { color: #a4d007; font-size: 13px; }
.ds-summary { white-space: pre-wrap; overflow-wrap: anywhere; font: 12px/1.5 monospace; margin: 12px 16px; }
.ds-progress { height: 3px; background: #3d4148; margin: 3px 0 8px; }
.ds-progress>span { display: block; height: 100%; background: #1a9fff; }
.ds-loading { padding: 20px 16px; }
.ds-monitor-toolbar { display: flex; gap: 8px; margin: 0 0 18px; }
.ds .ds-monitor-toolbar button { min-width: 0 !important; width: auto !important; padding: 7px 10px !important; font-size: 13px !important; line-height: 20px !important; }
.ds-monitor-toolbar .ds-metric-trigger { flex: 1 1 0; }
.ds-monitor-toolbar .ds-range-trigger { flex: 0 0 76px; }
.ds .ds-metric-trigger, .ds .ds-range-trigger, .ds .ds-metric-option, .ds .ds-range-option, .ds .ds-disclosure-trigger { display: flex; align-items: center; justify-content: space-between; gap: 8px; }
.ds-monitor-toolbar svg, .ds-disclosure-end svg, .ds-metric-options svg { flex-shrink: 0; width: 10px; height: 10px; }
.ds-primary-reading { display: flex; align-items: baseline; justify-content: space-between; gap: 12px; margin-bottom: 12px; }
.ds-primary-reading strong { font-size: 30px; font-weight: 600; line-height: 1.2; }
.ds-primary-reading>span { font-size: 12px; color: #b8bcbf; }
.ds-primary-metric { margin-bottom: 18px; }
.ds-monitor-status { display: flex; justify-content: space-between; font-size: 12px; color: #b8bcbf; margin-bottom: 12px; }
.ds-monitor-disclosure { margin-top: 8px; }
.ds .ds-disclosure-trigger { padding: 7px 10px !important; line-height: 20px !important; }
.ds-disclosure-end { display: inline-flex; align-items: center; gap: 8px; font-size: 11px; }
.ds-integrity-details, .ds-chart-details { padding: 8px 0; }
.ds-monitor-refresh { margin-top: 12px; }
.ds-metric-picker h3, .ds-range-picker h3 { font-size: 14px; font-weight: 500; margin: 8px 0 14px; }
.ds-metric-options { display: grid; grid-template-columns: minmax(0,1fr); gap: 8px; margin-top: 16px; }
.ds .ds-metric-options button { text-align: left; padding: 9px 12px !important; line-height: 20px !important; }
`;
