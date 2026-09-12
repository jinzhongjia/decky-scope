# DeckScope 0.1.0 发布准备

**当前版本：0.1.0-rc.2。状态：本地候选包，已侧载验证，未公开发布。更新：2026-09-12。**

## 产品定位

DeckScope 是面向 SteamOS 的 **QAM-only 系统信息与监控工具**。它没有独立大屏、路由或“大屏打开”入口。监控页包含 CPU、GPU 和功率曲线，系统页集中展示 SteamOS、内核、硬件与开发连接信息。关闭面板不停止原生后台记录。

本轮候选版在一台 Steam Deck OLED 上执行了实际 QAM 视觉与交互测试。商店兼容验证、长期性能认证和其他硬件验证仍不能从单机测试推导。详细结果见 [QAM 验收记录](QAM-ACCEPTANCE.md)。

rc.2 已改用原生 Field/PanelSection，修正两组按钮的横向导航。触摸原始问题尚未稳定复现，详见 [输入验收](UI-INPUT-ACCEPTANCE.md)。

## 候选版变更说明

CPU 与 GPU 以并排曲线呈现，并显示当前频率。功率图可在 APU 封装功耗和电池充放电功率之间切换。所有曲线来自真实历史与实时数据，支持 5 分钟、30 分钟、6 小时和 7 天查询范围。CPU/GPU 均使用 0–100% 刻度，缺失数据保留断点，电池充电保持负号，不把 APU 功耗伪装为整机功耗。

系统页显示处理器型号、逻辑 CPU 数、操作系统可见内存、制造商、型号、BIOS、内核、SteamOS 版本与构建、IP、网卡以及 SSH/CEF 的本机监听状态。IP 默认隐藏，可手动显示或复制。系统摘要采用字段白名单，不含 IP、序列号或 SteamID。

设置页以分段按钮提供 0.5、1、2、5 秒采样间隔，避免原生下拉菜单转移到 Steam 主视窗。静态系统字段也参加原生焦点树，方便使用方向键逐项阅读。UI 事件最高约 1 Hz，不等于全部历史采样率。

## 公开发布前仍须完成

| 项目 | 当前证据与待办 |
| --- | --- |
| 主许可证与参考代码权利 | 仓库没有 LICENSE；用户提供的参考包中也未找到许可文件。需要用户确认授权来源和主许可证，不能由代理默认替用户授予许可。 |
| 第三方通知 | 当前安装的 `@decky/api`、`@decky/ui` 元数据声明 LGPL-2.1，`react-icons` 声明 MIT。还需核对实际分发内容和所用图标的原始许可，归档所需通知；不能把这些元数据当作完整法律审查。 |
| 发布渠道和仓库 | 当前 Git 没有 remote。GitHub 与 GitHub CLI 连接器在本会话未启用。需要确定仓库、可见性、发布账号及先走 GitHub Release 还是商店。 |
| 商店后端构建 | 官方模板要求自定义后端通过 CLI/Docker 构建并输出至 `backend/out`，源码布局要求见官方说明。当前使用 `monitor/` 与本机 Zig 0.16；尚未完成官方商店构建适配及验证。[2] |
| 前端构建工具 | 官方模板说明要求 pnpm 9；当前项目锁定 pnpm 11.3.0。应在实际目标构建环境验证并协调，不把本地构建通过当成商店 CI 通过。[2] |
| 商店展示图 | `plugin.json.publish.image` 仍为空。已有真实 QAM 截图，但未上传公共地址。 |
| 稳定版验证范围 | 尚未完成 SteamOS Stable/Beta 通道组合、其他机型、真实休眠/网络切换、48 小时稳定性和游戏 frametime/P99 验证。官方数据库也要求遵守其提交清单。[1] |
| 稳定版本号及公开动作 | 当前明确为 `0.1.0-rc.2`，不是 `0.1.0` 稳定版。完成待办后再修改版本、创建 tag、推送或发布；本轮没有执行这些公开动作。 |

官方数据库说明，首次商店提交需要以子模块形式向 `decky-plugin-database` 发起 pull request，后续更新也需要更新版本与子模块引用。官方模板同时允许以 URL 分发符合布局的 ZIP，因此“可侧载 ZIP”和“商店发布通过”不是同一个结论。[1] [2]

本次已读取两份官方 GitHub README。官方 wiki 的正文抓取失败，没有将未读取内容当成已经核验的发布规则。

## 本地命令

```bash
bash scripts/check.sh
python3 scripts/release-check.py
python3 scripts/package-candidate.py

# 严格公共发布预检；当前会因明确的发布缺项而失败
python3 scripts/release-check.py --public
```

预检只做机械一致性检查，不替代许可证审查或商店审批。候选包允许本地私有测试，不表示已经具备对外分发许可或正式版资格。

## 升级与数据

从早期大屏版本升级后，只从 Decky QAM 进入插件；旧 `/deckscope` 路由不再提供。当前历史 schema 保持 v1，升级不删除既有历史和设置。原生异常退出仍可能丢失尚未批量写入的分钟记录。候选版已采用保留旧插件目录的完整侧载脚本，不使用直接写入 root-owned 前端文件的方式。

## References

[1]: https://github.com/SteamDeckHomebrew/decky-plugin-database "Decky Plugin Database submission README, accessed 2026-09-12"
[2]: https://github.com/SteamDeckHomebrew/decky-plugin-template "Decky Plugin Template build, binary layout and distribution README, accessed 2026-09-12"
