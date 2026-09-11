# DeckScope / decky-scope

**面向 SteamOS 的只读诊断与历史性能记录插件。** 核心使用 Zig 0.16，Decky 后端仅使用 Python 标准库，前端使用 React、TypeScript 与 Decky UI。当前为 `0.1.0` 开发预览，已经形成可构建、可测试、可打包的基础版本，**不是原技术方案全部完成后的生产发布版**。[1]

## 平台边界

产品适配对象是 **SteamOS，而不只是 Steam Deck**。Steam Deck LCD（Jupiter）和 OLED（Galileo）是已知机型配置。CPU 拓扑、电池名称、DRM 编号和传感器编号均通过系统能力探测。其他 SteamOS 设备不因 DMI 机型不匹配而被拒绝。不存在的数据不伪装成零，未实测的平台不标记为兼容认证。

| 场景 | 当前实现 | 验证状态 |
| --- | --- | --- |
| Steam Deck LCD | Jupiter 配置；动态 CPU、DRM 与电池发现 | 合成夹具通过；尚无 LCD 真机验收 |
| Steam Deck OLED | Galileo 配置；同样不硬编码编号 | 合成夹具通过；在线 OLED 只做了 SSH 只读环境检查，尚未部署本插件 |
| 非 Deck SteamOS | 通用 CPU/内存/PSI/I/O/连接信息；按可读来源提供硬件指标 | 16/24 线程、BAT0/CMB0、无 GPU 等合成场景通过；尚无其他 SteamOS 真机验收 |
| 普通 Linux 开发机 | 允许降级运行，方便测试协议与内核接口 | 当前开发机完成本地回归；不等于 SteamOS 真机认证 |
| Intel/NVIDIA GPU、特殊 EC 风扇、多 GPU/多电池汇总 | 缺失时明确不可用；当前仅选一个可读 GPU 和一个电池 | 专用采集器、显式设备选择和多设备汇总未完成 |

CPU 当前快照支持逻辑编号 0–255；超过上限会报告截断。历史暂时只保留 CPU 总体指标。GPU 利用率、温度和频率绑定到同一个选定 DRM 设备，避免把不同显卡的数据混在一起。`apu_power_mw` 只在已知 Deck APU 配置下解释为封装功耗，不把任意独立显卡功耗冒充 APU 功耗。[1]

## 已实现的基础链路

| 模块 | 当前能力 |
| --- | --- |
| Zig monitor | 无 libc、静态 x86_64 ELF；单线程 `timerfd + epoll`；采样热路径无堆分配 |
| 采集 | CPU 总体/当前每线程/频率、内存与 Swap、可用的温度/GPU/电池/风扇、PSI、整块存储设备和默认路由接口 I/O |
| 历史 | 1,800 高频点、2,160 个十秒窗口、10,080 个分钟窗口；单调时间聚合；UTC 时间戳；缺失值独立计数 |
| 持久化 | DSCP schema v1、128 字节记录、CRC32、按 UTC 日保留、坏尾恢复、批量追加、独占锁、写入失败时保留内存采集 |
| 开发连接 | rtnetlink 事件驱动缓存；IPv4/IPv6 推荐地址；SSH/CEF 本地监听状态，不扫描局域网或查询公网 IP |
| Bridge | 私有 UDS、SO_PEERCRED 校验、请求关联、纯 stdlib、设置原子写、限频重启、卸载 flush |
| 基础 UI | QAM 速览、总览、历史 Canvas、设备/连接页、隐私遮罩、脱敏摘要复制、中英文本 |
| 工程工具 | 本地构建、发布/安全构建双回归、完整开发 ZIP、显式确认部署、旧插件备份、只读发现与日志脚本 |

`battery_rate_mw` 正值为放电、负值为充电，**不是墙上整机功耗**。当前历史聚合对 CPU/GPU 保留 min/avg/max，其余指标保留均值。网络卡片在进入页面和手动刷新时读取更新后的内核缓存，尚未接入网络变化的前端主动推送。[1]

## 目录

```text
decky-scope/
├── main.py                 # Decky callable 白名单门面
├── py_modules/             # 生命周期、协议、设置
├── monitor/src/            # Zig 采集、网络、历史、持久化
├── src/                    # React UI 和唯一 API 层
├── tests/                  # 合成硬件、UDS、bridge、UI 纯逻辑测试
├── scripts/                # 构建、打包、部署和只读调试
├── docs/                   # 设计、协议、验证与后续工作
├── bin/                    # 本地发布二进制（构建生成，Git 忽略）
└── outputs/DeckScope-dev.zip # 完整开发包（构建生成，Git 忽略）
```

用户提供的原方案与 demo 解压保留在 `.work/reference/`，仅供追溯，不进入插件包。`sys.zig`、最小运行时和日志方案参考该 demo；bridge 门面、Decky 控件、构建/侧载思路参考相邻的 `decky-music`。没有修改 `decky-music` 项目代码，也没有把其部署目标、密码或音乐业务复制过来。

## 本地构建与验证

开发环境需要 Linux x86_64、Zig 0.16.x、Python 3.10+、Node.js 和 pnpm。部署辅助脚本另外使用 OpenSSH、`file` 和 `readelf`。monitor 本身不需要 Python、libc、外部命令或第三方运行库。

```bash
cd /home/jin/code/decky-scope
pnpm install
bash scripts/check.sh
```

`check.sh` 依次运行 Zig 单元测试、ReleaseSmall 构建、保留符号的 ReleaseSafe 构建、两份二进制的 Python 集成回归、前端类型检查、UI 纯逻辑测试、前端构建和 ZIP 校验。当前验证结果与未验证项见 [验证记录](docs/VALIDATION.md)。[2]

```bash
# 仅构建 Zig，生成 bin/deckscope-monitor 和 monitor/zig-debug/bin/deckscope-monitor
bash scripts/build-monitor.sh

# 重建 Zig 和前端后，输出完整开发包
bash scripts/package.sh
```

原生进程调用形式为 `deckscope-monitor <uds_socket_path> <history_directory> [fixture_root]`。UDS server 必须先存在；该程序不是命令行交互 shell。`tests/support.py` 提供本地 mock bridge，硬件夹具由测试按需生成。

## 真机部署与调试

**当前没有部署，也没有重启在线设备的任何服务。** 首次部署前应确认设备地址、目标用户以及当前没有需要保持不中断的 Decky 操作。部署会安装/替换 `DeckScope` 并重启 `plugin_loader`，因此可能短暂影响其他 Decky 插件；不会修改系统功耗、风扇、SSH 或 CEF 配置。

```bash
# 只读查找，不扫描整个局域网；地址不要写进仓库
bash scripts/discover.sh steamdeck.local

# 以下命令仅在用户明确批准部署后执行；user@ip 是占位符
DECK_HOST=user@ip bash scripts/deploy.sh --confirm

# 只读查看当前插件日志
DECK_HOST=user@ip bash scripts/logs.sh
```

部署脚本每次重建全部产物，使用远端登录用户的 `$HOME/homebrew/plugins`，不假设用户名必为 `deck`。认证由 SSH/sudo 交互或已有密钥负责；不要把密码写进脚本或环境文件。旧版本保存在 `homebrew/deckscope-backups/`，不放在插件扫描目录内。该侧载路径尚未实机执行；ZIP 结构校验不代表 Decky 商店安装验收。

如果 CEF 只监听回环地址，可通过用户主动运行的 SSH 转发访问，例如 `ssh -L 8080:127.0.0.1:8080 user@ip`。项目不自动打开调试端口。实际 Steam UI 的调试方法可继续参考 `decky-music` 中的 `decky-dev` 与 `steam-cdp` 说明；任何重新部署、服务重启或可见 UI 操作都应先明确授权。

## 数据与隐私

历史数据保存在插件专属 runtime/data 目录下的 `history/`。仅保留当前 UTC 日和前六日，时钟回拨后落在窗口外的文件也会被清理，因此重要测试记录应先归档再修改系统时间。默认每十条分钟聚合批量写出；异常掉电或强杀可能丢失尚未 flush 的批次。历史恢复和格式细节见 [协议说明](docs/PROTOCOL.md)。[1]

插件不采集 SteamID、MAC、SSID、设备序列号、其他进程的环境或完整命令行。它不联网外传。摘要导出使用字段白名单，而不是试图从任意原始日志里事后删除敏感信息。实时指标仅在挂载的消费者需要时启用；没有 AI 调用、云端定时任务或前端定时轮询。

## 下一阶段

当前基础版本没有自动游戏会话识别、会话摘要、PSI 阈值事件、历史时间线事件、完整手柄游标/缩放、存储容量/显示器信息和 Intel/NVIDIA 专用 GPU 采集。网络选择只覆盖主路由表，VPN 排除仍为启发式，复杂策略路由与 multipart 中断恢复还需要专门回归。新设备热插拔目前主要依赖重启或休眠恢复时重新探测。持久化启动恢复仍读取有界的七日数据，尚未实现惰性索引读取。

接下来应先在已发现的 OLED 上完成授权侧载、真实数据核对、手柄 UI 和休眠恢复验收，再收集 LCD 与至少一台非 Deck SteamOS 的实际来源清单。48 小时长稳、游戏 frametime AB、真实 P99 和商店发布都仍未验收。**不要把这次本地成功编译，或参考 demo 的性能数字，当作跨机型生产验收。**

## References

[1]: docs/PROTOCOL.md "DeckScope protocol, data semantics and on-disk schema"
[2]: docs/VALIDATION.md "DeckScope local validation record"
