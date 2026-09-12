import { t } from "./i18n";
export type MonitorMetric = {
  metric: string;
  label: string;
  note?: string;
  secondary?: string;
};
export function monitorGroups(): Record<
  string,
  { label: string; items: MonitorMetric[] }
> {
  return {
    performance: {
      label: t("performanceGroup"),
      items: [
        { metric: "cpu_pct_x10", label: t("cpuUsage"), secondary: "cpu_mhz" },
        { metric: "gpu_pct", label: t("gpuUsage"), secondary: "gpu_mhz" },
        {
          metric: "apu_power_mw",
          label: t("power"),
          note: t("powerNotSystem"),
        },
        {
          metric: "battery_rate_mw",
          label: t("batteryRate"),
          note: t("batterySigned"),
        },
      ],
    },
    memory: {
      label: t("memoryGroup"),
      items: [
        { metric: "mem_used_mb", label: t("memory") },
        { metric: "swap_used_mb", label: t("swap") },
      ],
    },
    thermal: {
      label: t("thermalGroup"),
      items: [
        { metric: "cpu_temp_mc", label: t("temperature") },
        { metric: "gpu_temp_mc", label: t("gpuTemp") },
        {
          metric: "nvme_temp_mc",
          label: t("ssdTemperature"),
          note: t("ssdCacheNote"),
        },
        { metric: "fan_rpm", label: t("fan") },
      ],
    },
    io: {
      label: t("ioGroup"),
      items: [
        { metric: "disk_read_kbps", label: t("diskRead") },
        { metric: "disk_write_kbps", label: t("diskWrite") },
        { metric: "net_rx_kbps", label: t("netReceive") },
        { metric: "net_tx_kbps", label: t("netSend") },
      ],
    },
    pressure: {
      label: t("pressureGroup"),
      items: [
        { metric: "psi_cpu_some_x100", label: t("psiCpu"), note: t("psiNote") },
        {
          metric: "psi_mem_some_x100",
          label: t("psiMemSome"),
          note: t("psiNote"),
        },
        {
          metric: "psi_mem_full_x100",
          label: t("psiMemFull"),
          note: t("psiNote"),
        },
        {
          metric: "psi_io_some_x100",
          label: t("psiIoSome"),
          note: t("psiNote"),
        },
        {
          metric: "psi_io_full_x100",
          label: t("psiIoFull"),
          note: t("psiNote"),
        },
      ],
    },
  };
}
