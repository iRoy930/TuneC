# Changelog

本项目的所有重要变更都会记录在此文件中。

格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### Changed

- README 中英文版顶部加入应用图标（`.github/assets/appicon.png`，512×512，由 `Resources/AppIcon.icns` 导出，含透明圆角与投影），并将标题、简介、语言切换与徽章整体居中，作为仓库首页的视觉标识。
- `.github/ISSUE_TEMPLATE/bug_report.yml`：「外接显示器型号」与「显示器连接方式」改为**非必填**，未使用外接显示器的用户不必再硬填；下拉项顺序调整为以「未连接外接显示器」起头。
- README 中英文版的「目录结构 / Repository layout」补全为完整的顶层清单（此前只列出 6 项），并注明三个仓库级配置文件。

## [1.0.0] - 2026-09-28

首个公开发布版本。

### Added

- **菜单栏常驻**：应用以 `LSUIElement` 方式运行，无 Dock 图标；菜单内提供设备、音量、亮度、虚拟音频、手势与快捷键等分区。
- **音频设备管理**：枚举并切换系统输出 / 输入设备，支持循环切换，并监听设备插拔与默认设备变化。
- **CoreAudio 音量与静音控制**：对暴露可写 `VolumeScalar` 的设备直接读写音量与静音状态，行为与系统原生一致。
- **DDC/CI 显示器亮度控制**：通过 VCP `0x10` 调节外接显示器硬件亮度，菜单滑块与快捷键共用同一控制路径。
- **DDC/CI 音量后端**：对显示输出设备探针 VCP `0x62` 音量能力（读原值 → 写入 → 读回 → 恢复），仅在确认可写时切换到 DDC 后端，结果带缓存。
- **全局热键**：基于 Carbon `RegisterEventHotKey` 注册全局快捷键，覆盖切换输出设备、切换输入设备、音量增减、静音与亮度增减。
- **边缘滚轮手势**：基于 `CGEventTap` 拦截全系统滚轮事件，屏幕顶边滚轮调亮度、底边滚轮调音量，支持精度修饰键、热区高度与步进调节、自动全屏检测（默认关闭，需辅助功能权限）。
- **音量 / 亮度 HUD 浮窗**：无边框半透明浮窗，显示数值与进度条，位置按屏幕高度黄金分割点放置，并自动适配系统亮 / 暗色外观。
- **虚拟音频环回**：接管系统声音 → 统一增益调节 → 输出到物理设备。提供两种采集后端：Core Audio Process Tap（默认，需 macOS 14.2+，走"系统音频录制"权限，不占用麦克风）与 BlackHole（回退，macOS 13 可用，需自行安装 BlackHole 2ch）。
- **内置自检**：`TuneC --selfcheck` 输出 30 余项检查，覆盖设备枚举、音量读写、DDC 通道探针、环回链路与手势配置。

### Fixed

- 归一化预编译核心的 Swift 接口：移除 Swift 6 编译器自动插入的 `Swift.BitwiseCopyable` conformance 与接口文件头的编译器版本标记，旧编译器不再拒载 `Core/TuneCCore.swiftinterface`。
- 明确工具链下限并纳入守卫：`Core/libTuneCCore.a` 的目标文件要求链接 Swift 分体运行时库（`libswift_math` 等），需 **Xcode 16 / macOS 15 SDK 或更新**；构建或链接失败时由 `scripts/diagnose-core-link.sh` 给出可读诊断，CI/发版流程固定在 `macos-15`。

### Documentation

- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) 新增权限记录排障条目：说明卸载不会删除权限记录、变更 bundle identifier 会留下旧 id 的孤儿记录，以及幽灵条目只能点 `−` 删除。
- [docs/PERMISSIONS.md](docs/PERMISSIONS.md) 补充 `tccutil` 的三个前提条件，并说明更换签名身份或修改 bundle identifier 会让已有授权失效。
- [docs/BUILD.md](docs/BUILD.md) 新增「让授权在反复重建之间保持」一节，给出用固定自签名证书避免重建后重复授权的做法；工具链要求更新为 **Xcode 16 / macOS 15 SDK 起**，并区分「接口可解析」与「二进制可链接」，补充两类构建报错的定位方式。
- [Core/README.md](Core/README.md) 新增「工具链要求」一节，说明预编译核心与导出它的工具链之间的绑定关系。
- README 的中英文版各补充一条权限相关 FAQ 与工具链版本要求。

[Unreleased]: https://github.com/iRoy930/TuneC/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/iRoy930/TuneC/releases/tag/v1.0.0
