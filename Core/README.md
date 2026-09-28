# TuneCCore（预编译二进制核心）

本目录提供 TuneC 的核心静态库，**不含源码**。

- `libTuneCCore.a` — 通用静态库（arm64 + x86_64），已启用 Swift Library Evolution。
- `TuneCCore.swiftinterface` — 核心的公开 Swift 接口。核心对外只暴露纯 Swift API，
  不导出任何 Objective-C 头文件，构建时无需 `-import-objc-header`。

核心负责：CoreAudio 设备枚举与切换、音量后端路由（CoreAudio / DDC-CI / 虚拟音频环回）、
Core Audio Process Tap 与 BlackHole 采集、DDC/CI 显示器亮度与音量控制、显示器识别
（内置少量已知型号的能力档案，目前包含 Mi 27 NU）。

## 使用

`Sources/TuneC/` 下的外壳代码只需在文件顶部写 `import TuneCCore`，
构建脚本用 `-I Core -L Core -lTuneCCore` 链接即可，公开 API 见 `.swiftinterface`。

## 工具链要求

**预编译核心与导出它的工具链绑定**，需要 **Xcode 16 / Command Line Tools 16 或更新**
（即 macOS 15 SDK 或更新）。

原因是链接期而非编译期：`libTuneCCore.a` 里各目标文件带有对 Swift **分体运行时库**的
自动链接要求（`libswift_math`、`libswift_Builtin_float`、`libswift_errno`、`libswift_stdio`、
`libswift_signal`、`libswift_time`、`libswiftsys_time`、`libswiftunistd`），这些 `.tbd` 存根
自 macOS 15 SDK 起才随 SDK 提供。用更旧的 SDK 链接会失败，报错形如：

```
ld: warning: Could not find or use auto-linked library 'swift_math': library 'swift_math' not found
Undefined symbols for architecture arm64:
  "__swift_FORCE_LOAD_$_swift_math", referenced from: …
```

与之相对，**接口层面**是向后兼容的：`TuneCCore.swiftinterface` 已被归一化到能被
Swift 5.10 读取的形式，`scripts/check-core-interface.sh` 负责守住这一点。
换句话说，旧编译器能读懂接口，但链接不了二进制。

这只影响**构建**，不影响运行：产物以 macOS 13.0 为部署目标，在更旧的系统上照常运行
（这些分体运行时库在 minos 低于 15.0 时是弱引用，不会成为硬依赖）。

## 许可

核心为闭源二进制分发，仅授予在未修改形式下与 TuneC 外壳配合使用的权利。
