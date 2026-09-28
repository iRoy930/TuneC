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

## 许可

核心为闭源二进制分发，仅授予在未修改形式下与 TuneC 外壳配合使用的权利。
