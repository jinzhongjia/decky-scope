const words = {
  cpuUsage: ["CPU 使用率", "CPU usage"],
  gpuUsage: ["GPU 使用率", "GPU usage"],
  chooseCategory: ["选择指标分类", "Choose a category"],
  backToCategories: ["返回分类", "Back to categories"],
  groupMetricTitle: ["{group}指标", "{group} metrics"],
  chooseMetric: ["选择监控项", "Choose a metric"],
  chooseRange: ["选择时间范围", "Choose a time range"],
  chartDetails: ["数据说明", "About this chart"],
  coverageShort: ["覆盖", "Coverage"],
  ssdTemperature: ["SSD 温度", "SSD temperature"],
  ssdCacheNote: [
    "SSD 温度每 30 秒更新一次",
    "SSD temperature is refreshed every 30 seconds",
  ],
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
  curveGroup: ["指标类别", "Metric group"],
  performanceGroup: ["性能", "Performance"],
  memoryGroup: ["内存", "Memory"],
  thermalGroup: ["温度", "Thermal"],
  ioGroup: ["磁盘 / 网络", "Disk / Network"],
  pressureGroup: ["压力", "PSI"],
  diskRead: ["磁盘读取", "Disk read"],
  diskWrite: ["磁盘写入", "Disk write"],
  netReceive: ["网络接收", "Network receive"],
  netSend: ["网络发送", "Network send"],
  psiCpu: ["CPU 等待（some）", "CPU stalls (some)"],
  psiMemSome: ["内存等待（some）", "Memory stalls (some)"],
  psiMemFull: ["内存等待（full）", "Memory stalls (full)"],
  psiIoSome: ["I/O 等待（some）", "I/O stalls (some)"],
  psiIoFull: ["I/O 等待（full）", "I/O stalls (full)"],
  psiNote: [
    "PSI 表示任务因资源不足而等待的时间比例，不是资源使用率。",
    "PSI measures time stalled for resources, not utilization.",
  ],
  integrity: ["记录完整性", "RECORDING COVERAGE"],
  coverageEstimate: ["有效记录时长（估算）", "Estimated coverage"],
  noDataTime: ["无记录时长", "Uncovered time"],
  coverageNote: [
    "按该指标的查询分辨率估算；空白不自动判定为休眠。",
    "Estimated at this metric’s query resolution. Gaps do not automatically mean suspend.",
  ],
  coverageAsOf: ["查询截至", "Query through"],
  noDataGap: ["无记录", "No data"],
  suspendResume: [
    "休眠 → 恢复（估算边界）",
    "Suspend → resume (estimated bounds)",
  ],
  clockChange: ["系统时间变化", "Clock change"],
  eventNote: [
    "只标记本版本采集器检测到的事件；旧空白保留为未知原因。",
    "Only events detected by this collector version are labeled; older gaps remain unexplained.",
  ],
  lastPersisted: ["最新落盘记录时间", "Latest persisted record"],
  lastSync: ["本次最后同步", "Last sync this run"],
  pendingRecords: ["待落盘分钟记录", "Pending minute records"],
  limitedEvents: ["区间过多，仅显示部分", "Only some intervals are shown"],
  eventStorageError: [
    "事件日志保存异常；分钟采集独立运行。",
    "Event log unavailable; minute collection is independent.",
  ],
  storageCapacity: ["存储空间", "FILESYSTEM CAPACITY"],
  systemVolume: ["系统分区", "System filesystem"],
  homeVolume: ["用户数据", "User data"],
  removableVolume: ["可移动存储", "Removable storage"],
  capacityTotal: ["总容量", "Total capacity"],
  capacityAvailable: ["可用容量", "Available capacity"],
  mounted: ["已挂载", "Mounted"],
  unmounted: ["已检测到，未找到支持的挂载", "Detected; no supported mount"],
  noRemovable: [
    "未检测到已挂载可移动存储",
    "No mounted removable storage detected",
  ],
  storageCapacityNote: [
    "显示本地文件系统容量，不等于整块 SSD 容量；不重复累计共享挂载。",
    "Local filesystem capacity, not physical SSD capacity; shared mounts are not summed.",
  ],
  batteryDetails: ["电池详情", "BATTERY DETAILS"],
  batteryStatus: ["电池状态", "Battery state"],
  fullCapacity: ["满充容量", "Full-charge capacity"],
  designCapacity: ["设计容量", "Design capacity"],
  batteryHealth: ["健康度（估算）", "Estimated health"],
  cycleCount: ["循环次数", "Cycle count"],
  voltage: ["电池电压", "Battery voltage"],
  healthNote: [
    "由满充容量 / 设计容量估算，不是校准后的寿命诊断；缺失字段显示 —。",
    "Full/design capacity estimate, not a calibrated lifespan diagnosis. Missing fields stay unavailable.",
  ],
  charging: ["充电中", "Charging"],
  discharging: ["放电中", "Discharging"],
  full: ["已充满", "Full"],
  notCharging: ["未充电", "Not charging"],
  systemRuntime: ["系统运行信息", "SYSTEM RUNTIME"],
  systemElapsed: ["开机时长（含休眠）", "Time since boot (includes sleep)"],
  systemAwake: ["累计清醒时长", "Awake since boot"],
  systemSuspended: ["累计休眠时长", "Suspended since boot"],
  loadAverage: ["负载 1 / 5 / 15 分钟", "Load average 1 / 5 / 15 min"],
  memoryAvailable: ["可用内存", "Available memory"],
  memoryCached: ["文件缓存", "File cache"],
  memoryReclaimable: ["可回收内核缓存", "Reclaimable kernel cache"],
  memoryDirty: ["待写回内存", "Dirty memory"],
  memoryWriteback: ["正在写回", "Writeback memory"],
  swapTotal: ["Swap 总量", "Swap total"],
  swapFree: ["Swap 可用", "Swap free"],
  zramOriginal: ["zram 原始数据", "zram original data"],
  zramCompressed: ["zram 压缩数据", "zram compressed data"],
  zramMemory: ["zram 实占内存", "zram memory used"],
  zswapEnabled: ["zswap 已启用", "zswap enabled"],
  enabled: ["是", "Yes"],
  disabled: ["否", "No"],
  runtimeNote: [
    "系统时长从本次系统启动累计，与插件采集器时长不同。",
    "System clocks count from OS boot, separately from sampler uptime.",
  ],
  deviceTab: ["设备", "Device"],
  storageTab: ["存储", "Storage"],
  runtimeTab: ["运行", "Runtime"],
  gapLegend: [
    "灰色区间：无记录；黄色虚线：检测到的休眠 / 恢复。",
    "Gray areas: no records. Yellow markers: detected suspend / resume.",
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
  if (ms > 0 && ms < 1000) return "<1 s";
  if (ms < 60000) return `${Math.floor(ms / 1000)} s`;
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

export function bytes(value?: number | null): string {
  return value === null || value === undefined || !Number.isFinite(value)
    ? "—"
    : `${(value / 1073741824).toFixed(2)} GiB`;
}
export function kib(value?: number | null): string {
  return value === null || value === undefined
    ? "—"
    : `${(value / 1024).toFixed(1)} MiB`;
}
