const words = {
  overview: ["总览", "Overview"],
  history: ["历史", "History"],
  device: ["设备与连接", "Device & connection"],
  open: ["打开 DeckScope", "Open DeckScope"],
  refresh: ["刷新", "Refresh"],
  loading: ["读取中…", "Loading…"],
  unavailable: ["不可用", "Unavailable"],
  cpu: ["CPU 使用率", "CPU usage"],
  gpu: ["GPU 使用率", "GPU usage"],
  memory: ["已用内存", "Memory used"],
  temperature: ["CPU 温度", "CPU temperature"],
  power: ["APU 封装功耗", "APU package power"],
  battery: ["电池电量", "Battery"],
  batteryRate: ["电池充放电功率", "Battery charge/discharge"],
  sensorNote: ["电池功率：正值放电、负值充电；非整机功耗。NVMe 温度按 30 秒缓存。", "Battery power: positive discharging, negative charging; not system power. NVMe temperature cached for 30 seconds."],
  pressure: ["CPU 资源等待", "CPU pressure"],
  subtitle: [
    "只读 SteamOS 诊断与历史记录",
    "Read-only SteamOS diagnostics & history",
  ],
  partial: [
    "开发预览 · 非生产验收版本",
    "Development preview · not production validated",
  ],
  privacy: ["隐私遮罩", "Privacy mask"],
  interval: ["采样间隔", "Sample interval"],
  copy: ["复制脱敏环境摘要", "Copy redacted environment summary"],
  copied: ["已复制", "Copied"],
  copyFailed: [
    "剪贴板不可用，请查看下方摘要",
    "Clipboard unavailable; summary shown below",
  ],
  source: ["传感器来源", "Sensor sources"],
  monitoring: ["累计采样", "Samples collected"],
  storageError: [
    "历史写入失败；内存采集仍在继续",
    "History write failed; memory collection continues",
  ],
  noData: ["所选时段暂无可用样本", "No available samples in this range"],
  noSessions: [
    "会话自动识别尚未实现；当前按时间记录，不会伪造游戏记录。",
    "Automatic session detection is not implemented; history is time-based.",
  ],
  addressNote: [
    "监听状态不等于已验证的网络可达性；CEF 仅本机时请使用 SSH 转发。",
    "Listener state does not prove reachability. Use SSH forwarding for loopback-only CEF.",
  ],
  threadNote: [
    "线程数由系统探测；当前版本历史仅保存 CPU 总体指标。",
    "CPU topology is discovered; current history stores total CPU metrics only.",
  ],
  time: ["时间范围", "Time range"],
  metric: ["指标", "Metric"],
} as const;
export type TextKey = keyof typeof words;
export const t = (key: TextKey) =>
  words[key][(navigator.language || "").toLowerCase().startsWith("zh") ? 0 : 1];
export function formatMetric(key: string, value?: number | null): string {
  if (value === undefined || value === null || !Number.isFinite(value))
    return "—";
  if (key.endsWith("_x10")) return `${(value / 10).toFixed(1)}%`;
  if (key.endsWith("_x100")) return `${(value / 100).toFixed(2)}%`;
  if (key.endsWith("_pct")) return `${value}%`;
  if (key.endsWith("_mc")) return `${(value / 1000).toFixed(1)} °C`;
  if (key.endsWith("_mw")) return `${(value / 1000).toFixed(1)} W`;
  if (key.endsWith("_mb")) return `${value} MiB`;
  if (key.endsWith("_kbps")) return `${value} KiB/s`;
  return String(value);
}
