# TuneC

**TuneC** 是一个 macOS 菜单栏常驻小工具，让你能像调节内置扬声器一样，用键盘和滚轮控制外接显示器的音量和亮度。

[English](README.en.md) | 简体中文

[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey)](https://github.com/iRoy930/TuneC)
[![Swift](https://img.shields.io/badge/Swift-5-orange)](https://github.com/iRoy930/TuneC)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

> **系统要求**：macOS 13.0 或更高（Process Tap 后端需 macOS 14.2+），Apple Silicon 与 Intel Mac 均支持。

## 为什么需要它

把 Mac 通过 Type-C 或 DisplayPort 接上带音箱的外接显示器后，你会发现一个很别扭的事：

> **音量键没反应了，菜单栏的音量图标是灰的，系统设置里也找不到音量滑块。**

原因是这条音频链路走的是显示器自身的 DAC，macOS 只把它当成一个"固定电平"的输出设备，没有向系统暴露 `VolumeScalar`（软件音量）属性。于是 macOS 认为这台设备**根本没有音量可调**，把控制权整个交给了显示器的物理按键。TuneC 补上的就是这一块：它接管音量键与滚轮，先尝试直接控制设备；设备不支持时，用 DDC/CI 走显示器硬件；硬件也不支持时，用一个音频环回引擎在软件层完成调节。

---

## 功能特性

**菜单栏**

- 常驻菜单栏，无 Dock 图标、不占用程序坞（`LSUIElement`）
- 菜单内直接查看并切换当前输出 / 输入设备
- 音量滑块与静音开关，实时反映当前后端状态
- 识别外接显示器型号与能力，自动显示亮度滑块

**音量控制（多后端自动路由）**

- **CoreAudio 后端**：设备提供可写的 `VolumeScalar` 时直接控制，行为与系统原生一致
- **DDC/CI 后端**：显示器支持 DDC 音量（VCP `0x62`）时走硬件控制；启用前会做一次写后读回探针，确认真的可写才切换
- **虚拟音频后端**：显示器固件未实现 DDC 音量时的软件方案（见下）

**DDC/CI 显示器控制**

- 亮度调节（VCP `0x10`），支持菜单滑块与快捷键
- 对比度调节（VCP `0x12`），支持滚轮手势
- 显示器热插拔自动重新识别
- 内置少量已知型号的能力档案（目前包含 Mi 27 NU），识别得到型号后自动套用已知能力

**虚拟音频环回**

当输出设备的音量既不可写、显示器也不支持 DDC 音量时，TuneC 可以接管系统声音 → 统一调节音量 → 再输出到物理设备。提供两种采集后端：

| 后端 | 系统要求 | 权限 | 是否需要额外安装 |
| --- | --- | --- | --- |
| **Core Audio Process Tap**（默认） | macOS 14.2+ | 系统音频录制 | 否 |
| **BlackHole**（回退） | macOS 13.0+ | 麦克风 | 需自行安装 BlackHole 2ch |

Process Tap 后端不占用麦克风，因此**不会点亮菜单栏的橙色麦克风指示点**，也不需要安装任何驱动。

**全局操作**

- 全局热键（基于 Carbon `RegisterEventHotKey`），在任意应用内可用
- 边缘滚轮手势：滚轮移到屏幕**顶边**调亮度，移到**底边**调音量；默认关闭，开启需辅助功能权限

**音量 / 亮度 HUD**

- 极简半透明浮窗，显示当前数值与进度条
- 位置固定在屏幕高度的 61.8%（黄金分割点），水平居中
- 自动跟随系统亮色 / 暗色外观

**自检**

```bash
/Applications/TuneC.app/Contents/MacOS/TuneC --selfcheck
```

输出 30 余项检查，覆盖设备枚举、音量读写、DDC 通道、环回链路与手势配置，用于排查环境问题。

> TuneC **不含** EQ、混响等音频处理功能，**不做**录音，**不会**上传任何音频。

---

## 安装

### 方式一：下载预编译版本

1. 前往 [Releases](https://github.com/iRoy930/TuneC/releases) 下载最新版 `.zip`
2. 解压后把 `TuneC.app` 拖入 `/Applications`
3. 首次打开时，若系统提示"无法验证开发者"，请在**系统设置 → 隐私与安全性**中点击"仍要打开"

### 方式二：从源码构建（只需 Command Line Tools，无需完整 Xcode）

```bash
git clone https://github.com/iRoy930/TuneC.git
cd TuneC
bash scripts/build.sh
```

构建产物为 `build/TuneC.app`，直接 `open build/TuneC.app` 即可运行。更多细节见 [docs/BUILD.md](docs/BUILD.md)。

---

## 权限说明

TuneC 只为实际需要的功能申请权限，最小化授权范围：

| 权限 | 何时需要 | 说明 |
| --- | --- | --- |
| 系统音频录制 | 使用 Process Tap 后端 | 用于采集系统正在播放的声音。不涉及麦克风 |
| 麦克风 | 采集后端选为 BlackHole | BlackHole 是虚拟输入设备，读取它归入麦克风权限；该后端下启动即申请 |
| 辅助功能 | 开启边缘滚轮手势 | 需要拦截全系统滚轮事件；不开启手势则不申请 |

TuneC 不会录音，不会保存音频，没有任何网络上传行为。详见 [docs/PERMISSIONS.md](docs/PERMISSIONS.md)。

---

## 快捷键

| 快捷键 | 功能 |
| --- | --- |
| `⌃⌥ O` | 切换输出设备（循环） |
| `⌃⌥ I` | 切换输入设备（循环） |
| `⌃⌥ ↑` | 音量 + |
| `⌃⌥ ↓` | 音量 − |
| `⌃⌥ M` | 静音切换 |
| `⌃⌥ →` | 亮度 + |
| `⌃⌥ ←` | 亮度 − |

**边缘滚轮手势**（默认关闭，需辅助功能权限）：

| 位置 | 滚轮 | `⌥` + 滚轮 | `⌃` + 滚轮 | `⌘` + 滚轮 |
| --- | --- | --- | --- | --- |
| 屏幕顶边 | 亮度 | 精细调节 | 对比度 | — |
| 屏幕底边 | 音量 | 精细调节 | 切换输出设备 | 静音切换 |

---

## 常见问题

**Q：为什么按音量键还是没反应？**

先看菜单栏菜单里的"音量后端"一行。如果是「不支持」，说明当前设备既没有软件音量、显示器也不支持 DDC 音量——此时请打开菜单中的**虚拟音频环回**，之后音量键即可生效。

**Q：菜单栏出现了橙色的麦克风指示点，正常吗？**

说明当前采集后端是 **BlackHole**。BlackHole 是虚拟输入设备，读取它会计入麦克风权限，因此系统会亮起指示点。想避免它，请在「虚拟音频 → 采集方式」中切换到 **系统音频采集**（需 macOS 14.2+）。

**Q：需要安装 BlackHole 吗？**

macOS 14.2 及以上**不需要**。默认的 Process Tap 后端可直接采集系统音频，无需任何驱动。只有在 macOS 13.x 上，或需要兼容旧方案时，才需要安装 BlackHole 2ch。

**Q：滚轮手势没反应？**

手势默认关闭，且需要**辅助功能**权限。请到「系统设置 → 隐私与安全性 → 辅助功能」中勾选 TuneC，然后在菜单里打开"边缘滚轮手势"。另外全屏应用中默认需要按住 `⌥`（可在设置中调整）。

**Q：亮度滑块不出现？**

亮度滑块只在识别到外接显示器时显示，且该显示器的 DDC 通道必须可用。显示器睡眠或使用转接坞时，DDC 通道可能暂时不可用。

**Q：辅助功能里出现了两个 TuneC？卸载之后条目还在？**

macOS 的权限记录独立于 App 存在，**卸载不会删除它**；若 App 的 bundle identifier 变更过，
面板里还会多出一条基于旧 id 的记录。在「系统设置 → 隐私与安全性 → 辅助功能」里选中多余的
那条，点左下角 **`−`** 即可 —— 注意**不要拨幽灵条目的开关**，那会把它重新激活。
详见 [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)。

其他问题请先查阅 [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)。

---

## 目录结构

```
TuneC/
├── Sources/TuneC/      # 开放源码：菜单栏 UI、热键、手势、HUD、自检
├── Core/               # 闭源预编译二进制核心 + 文本接口（.swiftinterface）
├── Resources/          # Info.plist、应用图标
├── scripts/            # 构建与辅助脚本
├── docs/               # 构建、架构、权限、排障、发布文档
└── README.md
```

---

## 关于闭源核心

为了让项目可持续维护，仓库中有一部分能力以**预编译库**形式提供：核心音频引擎与 DDC 协议实现放在 `Core/` 目录，随附文本接口文件（`.swiftinterface`）供编译期类型检查，源码不公开。

`Core/` 是**专有软件**，不适用本仓库的 MIT 许可证，仅授权你在本项目构建流程中链接使用。仓库内其余开放源码部分（`Sources/`、`scripts/`、`Resources/` 等）完整可用、可读、可改。

具体条款见 [NOTICE](NOTICE)，架构说明见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

---

## 许可证

本仓库开放源码部分采用 **MIT License**，见 [LICENSE](LICENSE)。

`Core/` 目录下的预编译二进制不适用 MIT，见 [NOTICE](NOTICE)。

---

## 致谢

- [m1ddc](https://github.com/waydabber/m1ddc) — 本项目 DDC/CI 实现思路参考了该项目
- [BlackHole](https://github.com/ExistentialAudio/BlackHole) — 开源虚拟音频驱动，由用户自行安装

感谢所有提交 issue 与 PR 的使用者。
