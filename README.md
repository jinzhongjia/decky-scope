# DeckScope

[简体中文](#简体中文) · [English](#english)

## 简体中文

**DeckScope 是一款面向 SteamOS 的 Decky 系统监控与历史记录插件。** 在快捷访问菜单（QAM）中查看设备状态、性能趋势和系统信息，无需离开游戏切换到桌面或独立全屏页面。

### 能做什么

- **查看实时状态**：了解 CPU、GPU、内存、温度、功耗、磁盘和网络活动，以及系统资源压力。
- **回看历史趋势**：查看最近七个自然日内的性能记录，观察负载、温度与功耗随时间的变化。
- **专注一个指标**：默认只展示一个指标和一张清晰的曲线图，按分类选择其他指标，按需展开详细信息。
- **了解设备信息**：查看 SteamOS 版本、内核、硬件、电池、存储空间和网络信息，并复制诊断摘要。
- **使用熟悉的界面**：所有功能都在 QAM 内，支持简体中文和英文。

### 使用边界

DeckScope 用于观察和诊断，不负责超频、风扇控制或系统调优。监控数据保留在本机，不上传；不采集账号凭据、Steam ID 或设备序列号。

可用指标取决于设备提供的数据，不支持的读数会标为不可用，而不是显示为零。电池功率和 APU 功率不等于整机插座功耗。

当前公开预览版本为 **`0.1.0-alpha.1`**，仅供实验性侧载使用，不是稳定版或 Decky 商店认证版本。真机验证范围仅覆盖此前候选包在一台 Steam Deck OLED 上的测试；本次 alpha 包未重新进行真机验收，Steam Deck LCD 和其他 SteamOS 设备尚未验证。自动游戏场次识别与总结、完整的图表游标和缩放功能暂未提供。

### Alpha 下载

前往 [GitHub prerelease](https://github.com/jinzhongjia/decky-scope/releases/tag/v0.1.0-alpha.1)，下载 **`DeckScope-0.1.0-alpha.1-linux-x86_64.zip`**，不要使用自动生成的 Source code 压缩包。发布附件同时提供 `SHA256SUMS` 和 `build-manifest.json`。使用前请阅读[部署与回滚](docs/DEPLOYMENT.md)、[兼容性限制](docs/COMPATIBILITY.md)和[第三方声明](THIRD-PARTY-NOTICES.md)；项目尚未指定主许可证。

## English

**DeckScope is a Decky plugin for SteamOS system monitoring and performance history.** View device status, performance trends, and system information from the Quick Access Menu (QAM), without switching from your game to the desktop or a separate fullscreen page.

### What it does

- **Check live status**: See CPU, GPU, memory, temperature, power, disk and network activity, and system resource pressure.
- **Review historical trends**: Explore performance records from the last seven calendar days to see how load, temperature, and power change over time.
- **Focus on one metric**: Start with one selected metric and one clear chart. Browse other metrics by category and expand details when needed.
- **Understand your device**: View the SteamOS version, kernel, hardware, battery, storage capacity, and network information, and copy a diagnostic summary.
- **Stay in a familiar interface**: Everything lives inside QAM, with Simplified Chinese and English support.

### Scope and availability

DeckScope is for observation and diagnostics, not overclocking, fan control, or system tuning. Monitoring data stays on your device and is not uploaded. Account credentials, Steam IDs, and device serial numbers are not collected.

Available metrics depend on the data your device exposes. Unsupported readings are shown as unavailable, not as zero. Battery power and APU power are not whole-device wall power.

The current public preview is **`0.1.0-alpha.1`**, an experimental sideload build, not a stable release or Decky Store-certified package. Device evidence covers earlier candidates on one Steam Deck OLED; this alpha package has not undergone a new on-device acceptance run. Steam Deck LCD and other SteamOS devices remain unverified. Automatic game-session detection and summaries, full chart cursors, and zoom are not yet available.

### Alpha download

Open the [GitHub prerelease](https://github.com/jinzhongjia/decky-scope/releases/tag/v0.1.0-alpha.1) and download **`DeckScope-0.1.0-alpha.1-linux-x86_64.zip`**, not the generated Source code archives. Assets also include `SHA256SUMS` and `build-manifest.json`. Read [deployment and rollback](docs/DEPLOYMENT.md), [compatibility limits](docs/COMPATIBILITY.md), and [third-party notices](THIRD-PARTY-NOTICES.md) before use; no main project license has been selected.
