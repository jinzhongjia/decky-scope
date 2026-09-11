const words = {
  overview: ["总览", "Overview"],
  monitor: ["监控", "Monitor"],
  system: ["系统", "System"],
  settings: ["设置", "Settings"],
  history: ["历史", "History"],
  refresh: ["刷新数据", "Refresh data"],
  loading: ["读取中…", "Loading…"],
  unavailable: ["不可用", "Unavailable"],
  cpu: ["CPU", "CPU"],
  gpu: ["GPU", "GPU"],
  memory: ["内存", "Memory"],
  temperature: ["CPU 温度", "CPU temperature"],
  power: ["APU 封装功耗", "APU package power"],
  battery: ["电池", "Battery"],
  batteryRate: ["电池充放电", "Battery flow"],
  pressure: ["CPU 资源等待", "CPU pressure"],
  privacyGroup: ["隐私与共享", "PRIVACY & SHARING"],
  privacy: ["隐藏 IP 地址", "Hide IP address"],
  interval: ["采样间隔", "Sample interval"],
  copy: ["复制系统摘要", "Copy system summary"],
  showIp: ["显示 IP", "Show IP"],
  hideIp: ["隐藏 IP", "Hide IP"],
  copyIp: ["复制 IP", "Copy IP"],
  copied: ["已复制", "Copied"],
  copyFailed: [
    "剪贴板不可用；摘要显示在下方",
    "Clipboard unavailable; summary shown below",
  ],
  source: ["采集来源", "Sensor sources"],
  monitoring: ["累计采样", "Samples collected"],
  storageError: [
    "历史写入失败；内存采集仍在继续",
    "History write failed; memory sampling continues",
  ],
  noData: ["所选时段暂无可用样本", "No samples in this range"],
  noReadings: ["暂无读数", "No readings"],
  recording: ["后台采集", "Sampling"],
  localOnly: ["仅存本机", "Local only"],
  fiveMin: ["5分", "5m"],
  halfHour: ["30分", "30m"],
  sixHour: ["6时", "6h"],
  sevenDays: ["7天", "7d"],
  powerNotSystem: [
    "封装读数，不代表整机功耗",
    "Package reading, not total system power",
  ],
  batterySigned: [
    "＋ 放电 / − 充电 · 非整机功耗",
    "+ discharging / − charging · not system power",
  ],
  powerUnavailable: ["未提供整机功耗来源", "No total-system power source"],
  now: ["现在", "Now"],
  sampleMean: ["历史均值 + 实时点", "History means + live points"],
  sampleRaw: ["历史采样 + 实时点", "History samples + live points"],
  fan: ["风扇", "Fan"],
  networkIO: ["网络 ↓ / ↑", "Network ↓ / ↑"],
  diskIO: ["磁盘 读 / 写", "Disk read / write"],
  gpuTemp: ["GPU 温度", "GPU temperature"],
  nvmeTemp: ["SSD 温度 · 30秒缓存", "SSD temp · 30s cache"],
  swap: ["交换空间", "Swap used"],
  operatingSystem: ["操作系统", "OPERATING SYSTEM"],
  hardware: ["硬件信息", "HARDWARE"],
  connection: ["网络与开发", "NETWORK & DEVELOPMENT"],
  os: ["系统", "OS"],
  osVersion: ["SteamOS 版本", "SteamOS version"],
  build: ["系统构建", "OS build"],
  kernel: ["内核版本", "Kernel"],
  architecture: ["架构", "Architecture"],
  firmware: ["BIOS / 固件", "BIOS / firmware"],
  processor: ["处理器", "Processor"],
  logicalCpu: ["逻辑处理器", "Logical CPUs"],
  physicalMemory: ["可用物理内存总量", "OS-visible memory"],
  model: ["型号", "Model"],
  manufacturer: ["制造商", "Manufacturer"],
  interface: ["网络接口", "Interface"],
  masked: ["地址已隐藏", "Address hidden"],
  notDetected: ["未检测到", "Not detected"],
  loopback: ["仅本机", "Localhost only"],
  lanListener: ["非回环监听", "Non-loopback listener"],
  unknown: ["未知", "Unknown"],
  addressNote: [
    "监听状态不代表远端可达。CEF 仅本机时使用 SSH 转发。",
    "A listener does not prove reachability. Use SSH forwarding for localhost CEF.",
  ],
  privacyNote: [
    "默认隐藏地址。系统摘要始终不含 IP、序列号、SteamID。",
    "Addresses are hidden by default. System summaries never include IP, serial number or SteamID.",
  ],
  backgroundNote: [
    "关闭面板仅停止界面推送，后台继续采样与保存历史。",
    "Closing this panel stops UI pushes, not background sampling or history.",
  ],
  historyNote: [
    "最多保留 7 天。分钟数据批量落盘，异常退出可能丢失未写入部分。",
    "Up to 7 days. Minute records are batched; an unexpected exit may lose unflushed data.",
  ],
  storage: ["历史记录", "HISTORY"],
  records: ["内存中的分钟记录", "Minute records in memory"],
  uptime: ["本次采集已运行", "Sampler uptime"],
  about: ["关于 DeckScope", "ABOUT DECKSCOPE"],
  readOnly: ["只读诊断 · 无需 root", "Read-only · no root required"],
  version: ["版本", "Version"],
  refreshHistory: ["刷新曲线", "Refresh charts"],
  retry: ["重试", "Retry"],
  customDevice: ["SteamOS 设备", "SteamOS device"],
  nativeError: [
    "采集连接异常，请刷新重试",
    "Sampler connection issue. Refresh to retry.",
  ],
  chartError: [
    "历史暂时不可读，可刷新重试",
    "History unavailable. Refresh to retry.",
  ],
} as const;
export type TextKey = keyof typeof words;
export const locale = () =>
  (navigator.language || "").toLowerCase().startsWith("zh") ? "zh-CN" : "en-US";
export const t = (key: TextKey) => words[key][locale() === "zh-CN" ? 0 : 1];
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
  if (key.endsWith("_mhz")) return `${(value / 1000).toFixed(2)} GHz`;
  if (key.endsWith("_rpm")) return `${value} RPM`;
  return String(value);
}
export function timeLabel(ms: number, days = false) {
  return new Intl.DateTimeFormat(
    locale(),
    days
      ? {
          month: "2-digit",
          day: "2-digit",
          hour: "2-digit",
          minute: "2-digit",
          hour12: false,
        }
      : { hour: "2-digit", minute: "2-digit", hour12: false },
  ).format(ms);
}
export function duration(ms: number) {
  const minutes = Math.floor(ms / 60000);
  return minutes < 60
    ? `${minutes} min`
    : `${Math.floor(minutes / 60)} h ${minutes % 60} min`;
}
export function listenerLabel(value?: string) {
  return value === "loopback_only"
    ? t("loopback")
    : value === "non_loopback_listener"
      ? t("lanListener")
      : value === "not_listening"
        ? t("notDetected")
        : t("unknown");
}
