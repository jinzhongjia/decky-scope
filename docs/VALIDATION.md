# DeckScope 验证与侧载记录

**验证日期：2026-09-12（UTC+8，更新至 02:02）。版本：0.1.0 开发预览。** 修复版 `4740fbf` 已侧载到 OLED，并通过基础启动检查。初版的 Python 模块冲突不再出现在当前启动日志中。UI、指标数值和历史功能尚未通过真机验收，本记录不构成跨机型 SteamOS 兼容认证。测试入口为 `bash scripts/check.sh`。[1]

## 已执行的检查

| 检查 | 结果 | 证据范围 |
| --- | --- | --- |
| Zig 单元测试 | 18/18 通过 | 布局、CPU/内存/PSI 解析、环形缓冲、时间窗口、CRC、JSON 边界、netlink 地址过滤、监听状态、背压队列 |
| Python 集成测试：ReleaseSmall | 19/19 通过 | 原生子进程、真实 UDS、合成硬件、bridge、设置与宿主模块命名冲突 |
| Python 集成测试：ReleaseSafe | 同样 19/19 通过 | 使用保留符号、开启运行时检查的构建重复回归；不是另加 19 个不同用例 |
| 前端纯逻辑测试 | 3/3 通过 | 畸形实时事件过滤、缺失值与单位、中英文选择 |
| TypeScript | 通过 | `pnpm typecheck` |
| 前端构建 | 通过 | `pnpm build`，生成 `dist/index.js` |
| ELF 检查 | 通过 | x86_64、静态、无动态依赖、无 ELF interpreter |
| 插件 ZIP | 通过 | 白名单文件、ZIP CRC、完整内置二进制、排除配置与工作目录 |
| OLED 基础启动 | 通过 | Loader active、monitor 进程存在、私有 socket 权限、当前日志 `monitor ready` |

Zig 单元测试和 Python 集成测试的源码可直接审查。[2] [3] 初始结果保留在 `.work/final-check.log`，修复版完整回归保留在 `.work/namespace-fix-check.log`；这些工作日志不进入插件包或 Git。

## 二进制与开发包

| 产物 | 字节数 | SHA-256 |
| --- | ---: | --- |
| `bin/deckscope-monitor` | 126,616 | `6970ca56523d2dfd9d8eeebb19f6d74bcdd2f2454ae17827e3ae3310ca01d772` |
| `outputs/DeckScope-dev.zip`（已侧载修复版） | 63,992 | `9db5d590d578f79a0e19352e19dee2772fd7cba6a2e4115162a6af9ed9e802ec` |

发布二进制约 123.6 KiB，低于方案的 256 KiB 体积目标。这个结果只证明**当前编译产物的体积与链接方式**。没有据此宣称 SteamOS 稳态 RSS、CPU 占用、P99 采样耗时或游戏影响达标。Zig 测试命令显示的 MaxRSS 属于测试进程，不能当作 monitor 的稳态内存数据。

## 合成与本机回归的具体范围

| 场景 | 已验证行为 |
| --- | --- |
| Jupiter/Galileo | 识别配置，动态读取 CPU、BAT1 和非固定编号 DRM/hwmon |
| 非 Deck 配置 | 16/24 线程、BAT0/CMB0、coretemp、GPU 缺失时正常降级 |
| 首次 CPU 采样 | 建立基线，不把自启动以来的总计数当成本秒利用率 |
| 多 GPU 来源 | 选定 DRM 设备的温度不被另一个独立 hwmon 读数覆盖 |
| 电池充电 | 输出负充电速率，不标记为系统功耗 |
| 磁盘分区 | 只统计整块设备，排除分区重复计数 |
| PSI | 累计微秒差分形成当前比例 |
| 实时开关 | 未启用时不发 metrics；启用后限频；关闭后继续本地记录 |
| 历史初始化 | 第一条分钟聚合尚未产生时，近期高频历史仍可查询 |
| 持久化 | 断开 flush、重启恢复、截断尾修复、独占锁、保留窗口与无关文件保护 |
| 协议 | 未知方法失败、分段帧、有界超长帧、畸形参数错误关联、并发请求 |
| Bridge | 私有 socket、原子 0600 设置、子进程退出后重启、卸载清理、脱敏导出 |
| 本机网络 | 实际 rtnetlink 完成快照，SSH/CEF 检查不进行网络扫描 |
| 冻结运行时命名冲突 | 预载宿主 `settings`、`protocol`、`bridge` 后导入真实插件入口；插件仍使用自己的私有模块，且不覆盖宿主模块 |

这些夹具没有模拟所有硬件差异。特别是网卡切换、策略路由、netlink multipart 中断、热插拔、传感器权限变化和所有磁盘故障分支仍需要补充验证。

## SteamOS 真机检查边界

本次通过 mDNS 找到一台在线 Steam Deck，并使用 SSH 做了只读检查。DMI 为 **Galileo**，系统为 **SteamOS 3.8.16**，Build 为 `20260716.1`，内核为 `6.16.12-valve24.5-1-neptune-616-gb2f7cfe85e45`。`plugin_loader` 处于 active；hwmon 中可见 acpitz、BAT1、steamdeck_hwmon、nvme 和 amdgpu；CPU/内存/I/O PSI 文件可读。SSH 监听非回环地址，CEF 8080 仅监听回环地址。

01:25 按用户授权执行 `scripts/deploy.sh --confirm`，安装初版并重启 `plugin_loader`。初版来源为提交 `f748e87`，ZIP SHA-256 为 `34a5d430e143de4a84a10bb0bbfc758e2e993c0a462ef7d0fb19273eb506a3b9`。这是首次安装，没有旧 DeckScope 版本需要备份。01:26 核验发现 loader 为 active，安装后二进制哈希一致，但未找到 monitor 进程。

启动日志显示 `Plugin._main → Bridge.__init__ → settings.load(self.settings_path)` 最终调用了 `json.load`，报错 `AttributeError: 'PosixPath' object has no attribute 'read'`。这是通用 Python 模块名冲突，不是采样器启动成功后的传感器错误。

三个内部模块随后改为 `deckscope_bridge`、`deckscope_protocol`、`deckscope_settings`，并增加两项命名隔离回归。02:01 经用户授权重新安装提交 `4740fbf` 的修复包并重启 Loader。安装器将旧版保留在 `/home/deck/homebrew/deckscope-backups/DeckScope-1789149673267633579`。备份创建路径已执行；没有做回退恢复演练。

02:01 的只读检查结果如下。安装与检查原始输出保留在 `.work/sideload-fixed-20260912.log` 和 `.work/sideload-fixed-check-20260912.log`。

| 项目 | 观察结果 |
| --- | --- |
| `plugin_loader` | `active` |
| 安装后二进制 SHA-256 | 与本地 `6970ca56…a01d772` 一致 |
| 原生 monitor | PID 17229，使用本插件的 UDS 与 history 目录启动 |
| IPC 目录 / socket | `0700` / `0600`，owner 为登录用户 |
| History 目录 / 独占锁 | `0700` / `0600` |
| 当前插件日志 | `[2026-09-12 02:01:21,702][INFO]: [bridge] monitor ready`，本次读取未出现异常 |

用户在 01:59 临时授权当前空闲设备调试期内的侧载和必要 Loader 重启，无需逐次确认，并要求防休眠。已创建 task-owned 用户服务 `deckscope-n4qze4-nosleep`，用 `systemd-inhibit` 阻止 idle/sleep，最长 30 分钟自动到期。02:00 已核验 block 锁，02:02 调试结束后主动停止服务并确认锁已解除。没有留下永久防休眠配置。

没有操作 Steam UI，也未修改功耗、风扇、SSH 或 CEF 配置。设备 IP 没有写进项目配置或可复用代码，密码没有写入项目文件或 Git。进程和控制通道启动成功不能视为数值、历史持久化或完整产品验收，更不能证明 LCD 或其他 SteamOS 设备已兼容。

## 尚待验收

基础启动检查已经通过。仍需验证 Steam UI/QAM 与手柄操作、实时订阅关闭、异常注入、连续休眠恢复、网络切换、设备实际指标与系统工具对照、历史记录写入和跨重启恢复，以及至少一台 LCD 和一台非 Deck SteamOS 的适配。48 小时长稳、7 天滚动、游戏 frametime AB、生产性能预算和 Decky 商店安装流程均未执行。

## References

[1]: ../scripts/check.sh "DeckScope complete local validation entrypoint"
[2]: ../monitor/src/tests.zig "Zig unit test imports"
[3]: ../tests/ "Python integration and frontend logic tests"
