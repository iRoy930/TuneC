# 构建指南

TuneC 使用一个自包含的 shell 脚本完成构建，不依赖 Xcode 工程，也不需要任何第三方包管理器。

## 环境要求

- **构建机系统**：macOS 13.0 或更新（更新版本更稳妥）。
- **工具链**：只需 **Command Line Tools**，无需安装完整 Xcode：

  ```bash
  xcode-select --install
  ```

  安装后 `swiftc` 与 macOS SDK 即可用。脚本会检查 `swiftc` 与 SDK 是否存在，
  缺失时直接报错退出，不会半途产出损坏的 bundle。
- `git`（用于克隆源码）。

运行 TuneC 的终端用户系统要求为 **macOS 13.0+**；其中「系统音频采集（Tap）」后端
需要 **macOS 14.2+**，更早的系统会自动回退到 BlackHole 虚拟设备后端。

## 获取源码

```bash
git clone https://github.com/iRoy930/TuneC.git
cd TuneC
```

仓库内已包含构建所需的**预编译二进制核心**（`Core/libTuneCCore.a` 与
`Core/TuneCCore.swiftinterface`），无需另外下载或编译任何东西。
`Core/` 是闭源预编译核心，仓库中不含其源码。

## 构建

```bash
# release 构建（默认），完成后部署到 ~/Applications/TuneC.app
bash scripts/build.sh

# 或显式指定模式
bash scripts/build.sh release
bash scripts/build.sh debug

# 只构建、不部署（CI 与本地验证常用）
NODEPLOY=1 bash scripts/build.sh release
```

等价的 Makefile 目标：

```bash
make build      # release 构建
make debug      # debug 构建
make verify     # 构建 + 自检（与 CI 的校验等价）
make clean      # 清理 build/ 与 .build/
```

## 产物位置

| 路径 | 说明 |
| --- | --- |
| `build/TuneC.app` | 构建产物（App bundle） |
| `~/Applications/TuneC.app` | 部署副本（`NODEPLOY=1` 时跳过） |

自检命令：

```bash
build/TuneC.app/Contents/MacOS/TuneC --selfcheck
```

自检会输出 30 余项环境与能力检查，末行为汇总，形如 `✅31 ⏭️3 ❌0`。
**❌ 计数为 0 时进程退出码为 0**；若某类设备未接入（例如没有外接显示器），
相关项会被标记为 ⏭️ 跳过，这是正常现象，不影响退出码。

## 构建脚本做了什么

`scripts/build.sh` 按顺序完成以下工作：

1. 校验工具链：确认能找到 `swiftc` 与 macOS SDK。
2. 准备 `build/TuneC.app` 的 `Contents/MacOS` 与 `Contents/Resources` 目录。
3. 复制 `Resources/Info.plist` 与 `Resources/AppIcon.icns` 到 bundle 内。
4. 编译开源壳层源码 `Sources/TuneC/*.swift`。
5. **链接 `Core/libTuneCCore.a` 预编译核心**，产出可执行文件。
6. 清理 bundle 内的伴随文件（`._*`、`.DS_Store`），避免破坏后续签名。
7. 用 `SIGN_IDENTITY` 指定的身份对 bundle 签名并校验。
8. 未设置 `NODEPLOY=1` 时，将 bundle 部署到 `~/Applications/TuneC.app`。

具体的编译与链接参数以 `scripts/build.sh` 为准。

## 签名与公证

- **本地自用**：默认使用 **ad-hoc 签名**，直接就能运行，无需任何开发者账号。
  可用环境变量覆盖签名身份：

  ```bash
  SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" bash scripts/build.sh release
  ```

- **分发给他人**：ad-hoc 签名的 App 在其他机器上会被 Gatekeeper 拦截。
  正式分发需要 **Apple Developer 账号**下的 *Developer ID Application* 证书，
  以 hardened runtime 签名后再提交 **notarization（公证）**，最后把公证票据
  装订到 App 上，才能让下载者直接打开。简要流程：

  ```bash
  codesign --force --options runtime --timestamp \
      --sign "Developer ID Application: Your Name (TEAMID)" build/TuneC.app
  xcrun notarytool submit TuneC.zip --keychain-profile <profile> --wait
  xcrun stapler staple build/TuneC.app
  ```

- **注意权限记录**：macOS 的 TCC 授权与签名身份绑定。更换签名身份（尤其是在
  ad-hoc 与证书之间切换）后，系统会把 App 视为新程序，需要重新授予权限，
  参见 [PERMISSIONS.md](PERMISSIONS.md)。

## 跨架构构建

- 预编译核心是**通用库**（同时包含 `arm64` 与 `x86_64`），因此同一个仓库在
  Apple Silicon 与 Intel 上都能构建，无需额外步骤。
- 默认构建脚本按本机架构（`uname -m`）编译，得到单架构可执行文件，本机运行完全够用。
- 要产出**通用二进制**（例如自己打包分发给别人），加 `UNIVERSAL=1`：

  ```bash
  UNIVERSAL=1 bash scripts/build.sh release
  # 或
  make universal
  ```

  脚本会分别按 `arm64` 与 `x86_64` 编译，再用 `lipo` 合成一个 fat 可执行文件。
  用 `lipo -info build/TuneC.app/Contents/MacOS/TuneC` 可以确认两个架构都在。
- **不要使用 SPM**（`swift build` / `Package.swift`）来构建本工程；发布树的
  构建入口只有 `scripts/build.sh`。

## 常见构建报错

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| `xcrun: unable to lookup item 'PlatformPath'` | 工具链指向了不存在或未安装的 Xcode 路径 | 用 Command Line Tools 构建（`xcode-select --install`），并**不要用 SPM** 构建本工程；确认 `xcode-select -p` 指向一个真实存在的路径 |
| `code object is not signed at all` 或 `In subcomponent: .../._TuneC` | 目录中混入了伴随文件（从外置卷或压缩包解压产生） | `make clean`，或手动 `find . -name '._*' -delete` 后重新构建 |
| `❌ 未找到 swiftc` | 未安装 Command Line Tools | `xcode-select --install` |
| `❌ 未找到 macOS SDK` | SDK 路径不存在 | 安装 Command Line Tools，或检查 `xcode-select -p` 输出是否正确 |
| 构建成功但打开无反应 | 旧副本仍在运行 / 权限被拒 | 退出旧实例后重试；必要时重置权限（见 [PERMISSIONS.md](PERMISSIONS.md)） |

## 依赖

**无第三方依赖。** 本工程不使用 SPM、CocoaPods、Homebrew 或任何外部库；
构建只需要系统自带的 Command Line Tools。可选的虚拟音频环回功能需要用户
自行安装 BlackHole 驱动，但它不是构建依赖。
