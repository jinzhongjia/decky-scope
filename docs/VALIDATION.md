# DeckScope 本地验证记录

**验证日期：2026-09-12（UTC+8）。版本：0.1.0 开发预览。** 本记录说明当前代码在开发电脑上的构建、协议和合成数据回归结果，不构成跨机型 SteamOS 兼容认证。测试入口为 `bash scripts/check.sh`。[1]

## 已执行的检查

| 检查 | 结果 | 证据范围 |
| --- | --- | --- |
| Zig 单元测试 | 18/18 通过 | 布局、CPU/内存/PSI 解析、环形缓冲、时间窗口、CRC、JSON 边界、netlink 地址过滤、监听状态、背压队列 |
| Python 集成测试：ReleaseSmall | 17/17 通过 | 原生子进程、真实 UDS、合成硬件、bridge 与设置 |
| Python 集成测试：ReleaseSafe | 同样 17/17 通过 | 使用保留符号、开启运行时检查的构建重复回归；不是另加 17 个不同用例 |
| 前端纯逻辑测试 | 3/3 通过 | 畸形实时事件过滤、缺失值与单位、中英文选择 |
| TypeScript | 通过 | `pnpm typecheck` |
| 前端构建 | 通过 | `pnpm build`，生成 `dist/index.js` |
| ELF 检查 | 通过 | x86_64、静态、无动态依赖、无 ELF interpreter |
| 插件 ZIP | 通过 | 白名单文件、ZIP CRC、完整内置二进制、排除配置与工作目录 |

Zig 单元测试和 Python 集成测试的源码可直接审查。[2] [3] 测试输出保留在本机 `.work/final-check.log`；该工作日志不进入插件包或 Git。

## 二进制与开发包

| 产物 | 字节数 | SHA-256 |
| --- | ---: | --- |
| `bin/deckscope-monitor` | 126,616 | `6970ca56523d2dfd9d8eeebb19f6d74bcdd2f2454ae17827e3ae3310ca01d772` |
| `outputs/DeckScope-dev.zip` | 63,916 | `34a5d430e143de4a84a10bb0bbfc758e2e993c0a462ef7d0fb19273eb506a3b9` |

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

这些夹具没有模拟所有硬件差异。特别是网卡切换、策略路由、netlink multipart 中断、热插拔、传感器权限变化和所有磁盘故障分支仍需要补充验证。

## SteamOS 真机检查边界

本次通过 mDNS 找到一台在线 Steam Deck，并使用 SSH 做了只读检查。DMI 为 **Galileo**，系统为 **SteamOS 3.8.16**，Build 为 `20260716.1`，内核为 `6.16.12-valve24.5-1-neptune-616-gb2f7cfe85e45`。`plugin_loader` 处于 active；hwmon 中可见 acpitz、BAT1、steamdeck_hwmon、nvme 和 amdgpu；CPU/内存/I/O PSI 文件可读。SSH 监听非回环地址，CEF 8080 仅监听回环地址。

**没有上传或运行本项目二进制，没有安装插件，没有重启 Decky，也没有操作 Steam UI。** 设备 IP 仅用于本次连接，没有写进项目配置或代码。密码没有写入文件或 Git。当前发现结果不能证明本插件已在 OLED 上运行，更不能证明 LCD 或其他 SteamOS 设备已兼容。

## 尚待验收

真正部署后还需验证 Steam UI/QAM 与手柄操作、实时订阅关闭、异常注入、连续休眠恢复、网络切换、设备实际指标与系统工具对照、跨重启历史恢复，以及至少一台 LCD 和一台非 Deck SteamOS 的适配。48 小时长稳、7 天滚动、游戏 frametime AB、生产性能预算和 Decky 商店安装流程均未执行。

## References

[1]: ../scripts/check.sh "DeckScope complete local validation entrypoint"
[2]: ../monitor/src/tests.zig "Zig unit test imports"
[3]: ../tests/ "Python integration and frontend logic tests"
