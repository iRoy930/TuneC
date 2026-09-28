# Changelog

本项目的所有重要变更都会记录在此文件中。

格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [Unreleased]

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

[Unreleased]: https://github.com/iRoy930/TuneC/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/iRoy930/TuneC/releases/tag/v1.0.0
