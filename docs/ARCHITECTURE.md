# 架构概览

TuneC 是一个 macOS 菜单栏常驻工具（`LSUIElement`，不显示 Dock 图标），
目标是让「用 Type-C / DP 接外接显示器时无法调节系统音量」的场景重新可用。
本文件只描述模块边界与职责，**核心实现细节不公开**。

## 模块划分

### 开源外壳：`Sources/TuneC/`（本仓库提供源码，共 6 个文件）

| 文件 | 职责 |
| --- | --- |
| `AppDelegate.swift` | 应用生命周期、启动装配、命令行 `--selfcheck` 入口 |
| `StatusBarController.swift` | 菜单栏图标与菜单、用户交互入口 |
| `HotKeyManager.swift` | 全局热键注册与回调分发 |
| `ScrollWheelGestureManager.swift` | 屏幕边缘滚轮手势的全局拦截与修饰键分类 |
| `ScrollHUD.swift` | 音量 / 亮度变化的屏幕浮层反馈 |
| `SelfCheck.swift` | CLI 自检：环境、设备与能力检查及结果汇总 |

### 预编译核心：`Core/`（**不提供源码**）

核心以静态库 `Core/libTuneCCore.a` 加文本接口 `Core/TuneCCore.swiftinterface` 的形式提供，
能力涵盖：音频设备管理、虚拟音频环回引擎、音量路由（CoreAudio / DDC-CI / 虚拟音频）、
DDC/CI 显示器控制、Core Audio Process Tap 与 BlackHole 采集，以及显示器识别
（内置少量已知型号的能力档案，目前包含 Mi 27 NU）。公开 API 以
`Core/TuneCCore.swiftinterface` 为准，本仓库不包含其实现源码。

### 其它

`Resources/` 为 `Info.plist`、`AppIcon.icns` 等打包资源；`scripts/` 为构建与辅助脚本。

## 启动流程（高层）

1. `AppDelegate` 启动，创建菜单栏控制器（不显示 Dock 图标）。
2. `StatusBarController` 点亮菜单栏图标并构建菜单（开关项、采集方式、权限入口）。
3. 依据用户设置注册全局热键，并按需启动边缘滚轮手势监听。
4. 用户调节音量或亮度时，由核心提供的 `VolumeRouter` 依据当前输出设备的能力选择后端
   （系统音量 / DDC/CI / 虚拟音频），结果交给 HUD 反馈。

## 两种采集后端的取舍

| 维度 | Tap（系统音频采集） | BlackHole（虚拟设备） |
| --- | --- | --- |
| 系统要求 | macOS 14.2+ | macOS 13.0+（兼容回退路径） |
| 所需权限 | 系统音频录制 | 麦克风 |
| 是否占用麦克风 | 否 | 是 |
| 信号衰减 | 无（零衰减） | 有（驱动按设备音量衰减） |
| 是否需要切换默认输出 | 否 | 是 |

预编译核心对外只暴露稳定接口，不包含源码，也不公开内部实现细节。
