# 构建指南

TuneC 使用一个自包含的 shell 脚本完成构建，不依赖 Xcode 工程，也不需要任何第三方包管理器。

## 环境要求

- **构建机系统**：macOS 14.5 或更新（Xcode 16 / Command Line Tools 16 的系统前提）。
- **工具链**：只需 **Command Line Tools**，无需安装完整 Xcode：

  ```bash
  xcode-select --install
  ```

  安装后 `swiftc` 与 macOS SDK 即可用。脚本会检查 `swiftc` 与 SDK 是否存在，
  缺失时直接报错退出，不会半途产出损坏的 bundle。
- **工具链版本**：需要 **Xcode 16 / Command Line Tools 16 或更新**（即 macOS 15 SDK
  或更新）。更新版本的工具链没有上限要求。

  原因：预编译核心 `Core/libTuneCCore.a` 由更新版本的 SDK 导出，其目标文件要求链接
  Swift 的**分体运行时库**（`libswift_math`、`libswift_Builtin_float`、`libswift_errno`、
  `libswift_stdio`、`libswift_signal`、`libswift_time`、`libswiftsys_time`、`libswiftunistd`），
  这些存根自 macOS 15 SDK 起才随 SDK 提供。更旧的 SDK 既找不到它们，也无法满足核心里的
  `__swift_FORCE_LOAD_$_swift_*` 标记；链接阶段失败，报错形态见「常见构建报错」。
- **接口可读性是另一件事**：`Core/TuneCCore.swiftinterface` 已归一化到「能被 Swift 5.10
  读取」的形式，`scripts/check-core-interface.sh` 会守住这一点。但**能解析 ≠ 能链接** ——
  链接还取决于上一条的 SDK 下限。
- `git`（用于克隆源码）。

运行 TuneC 的终端用户系统要求为 **macOS 13.0+**；其中「系统音频采集（Tap）」后端
需要 **macOS 14.2+**，更早的系统会自动回退到 BlackHole 虚拟设备后端。

构建工具链的 SDK 下限与 App 的运行下限是两回事：产物仍以 **macOS 13.0** 作为部署目标，
在更旧的系统上照常运行。

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
   编译或链接失败时，调用 `scripts/diagnose-core-link.sh` 解读链接器输出 ——
   其中最常见的一类失败是「工具链过旧」，脚本会直接给出结论与升级做法。
6. 清理 bundle 内的伴随文件（`._*`、`.DS_Store`），避免破坏后续签名。
7. 用 `SIGN_IDENTITY` 指定的身份对 bundle 签名并校验。
8. 未设置 `NODEPLOY=1` 时，将 bundle 部署到 `~/Applications/TuneC.app`。

具体的编译与链接参数以 `scripts/build.sh` 为准。

仓库还有两个守卫脚本，本地构建与 CI 都会用到：

| 脚本 | 作用 |
| --- | --- |
| `scripts/check-core-interface.sh` | 保证 `Core/TuneCCore.swiftinterface` 能被旧编译器**解析**（`--fix` 可就地归一化） |
| `scripts/diagnose-core-link.sh` | 从链接器输出定位「预编译核心与当前工具链不兼容」，给出可读诊断 |

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

- **注意权限记录**：macOS 的 TCC 授权与签名身份绑定。**更换签名身份**（尤其是在
  ad-hoc 与证书之间切换）或**修改 `CFBundleIdentifier`** 之后，系统会把 App 视为
  另一个程序，需要重新授予权限；后者还会在权限面板里留下一条旧 id 的孤儿记录
  （删除方法见 [TROUBLESHOOTING.md](TROUBLESHOOTING.md)）。
  详见 [PERMISSIONS.md](PERMISSIONS.md)。

### 让授权在反复重建之间保持（本地开发推荐）

默认的 **ad-hoc 签名**（`--sign -`）在每次重新构建后权限都会失效。原因在于：
ad-hoc 签名下，系统记录下来的代码要求是**纯 cdhash**，也就是二进制内容的哈希 ——
代码一改、cdhash 就变，授权随即作废。反复开发时每次都得去系统设置里重新勾选。

改用**固定的自签名证书**可以一劳永逸：代码要求会变成「证书根指纹」的形式，
与二进制内容完全解耦，重建多少次都不影响已有授权。

```bash
D=~/tunec-signing && mkdir -p "$D" && cd "$D"

# 1) 生成自签名代码签名证书
cat > cert.cnf <<'EOF'
[ req ]
distinguished_name = dn
x509_extensions    = ext
prompt             = no
[ dn ]
CN = TuneC Code Signing
O  = TuneC
C  = CN
[ ext ]
basicConstraints     = critical,CA:TRUE
keyUsage             = critical,digitalSignature
extendedKeyUsage     = critical,codeSigning
subjectKeyIdentifier = hash
EOF
openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 \
    -keyout key.pem -out cert.pem -config cert.cnf

# OpenSSL 3.x 需要 -legacy 才能产出 macOS 认的 p12；1.1.1 没有该参数
openssl pkcs12 -export -out app.p12 -inkey key.pem -in cert.pem \
    -name "TuneC Code Signing" -passout pass:local-dev -legacy 2>/dev/null || \
openssl pkcs12 -export -out app.p12 -inkey key.pem -in cert.pem \
    -name "TuneC Code Signing" -passout pass:local-dev

# 2) 导入登录钥匙串。带 -T 之后，首次签名不会弹钥匙串授权框
security import app.p12 -k "$HOME/Library/Keychains/login.keychain-db" -P local-dev \
    -T /usr/bin/codesign -T /usr/bin/security

# 3) 用固定身份构建（identifier 由 Info.plist 决定，务必保持不变）
SIGN_IDENTITY="TuneC Code Signing" bash scripts/build.sh release
```

自签名证书**不需要**设为「始终信任」：`codesign --verify --strict` 可直接通过。

要确认授权是否真的稳住了，看 TCC 记录里的 `last_modified` 有没有动 ——
比只看 csreq 更直观：

```bash
DB="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
sqlite3 "$DB" "SELECT service, length(csreq),
  datetime(last_modified,'unixepoch','localtime') FROM access
  WHERE client='io.github.iRoy930.tunec';"
# 重建前后各查一次：last_modified 不变 = 授权保持，未触发重新授权
```

> **切换签名身份的那一次**，旧授权会作废，需要重新授权一次 —— 此后就一劳永逸。
> 证书私钥只需留在钥匙串里，**不要**把 `key.pem` / `app.p12` 提交进仓库。

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
| `no type named 'BitwiseCopyable' in module 'Swift'`<br>或 `failed to build module 'TuneCCore'; this SDK is not supported by the compiler` | 预编译核心接口由比本机**更新**的 Swift 导出：本机编译器不认识 Swift 6 才有的 `BitwiseCopyable`，或因接口文件头记录的编译器版本更高而主动拒载 | 升级 Command Line Tools / Xcode（接口自 **Swift 5.10** 起即可解析；实际完成构建需要 Xcode 16+，见下一条）。若你是维护者（接口由你重新生成后回退），运行 `bash scripts/check-core-interface.sh --fix` 把它归一化回基线 |
| `ld: warning: Could not find or use auto-linked library 'swift_math'`<br>（通常连同一串 `swift_errno`、`swift_Builtin_float`、`swift_stdio`、`swiftunistd` …）<br>以及 `Undefined symbols … __swift_FORCE_LOAD_$_swift_math` | 预编译核心要求链接 Swift **分体运行时库**，而当前 SDK 早于 **macOS 15 SDK**（例如 Xcode 15.4 自带的 SDK 14.5） | 升级到 **Xcode 16 / Command Line Tools 16 或更新**。构建脚本会自动打印诊断，也可单独运行：`bash scripts/diagnose-core-link.sh --log <构建日志>` |

## 依赖

**无第三方依赖。** 本工程不使用 SPM、CocoaPods、Homebrew 或任何外部库；
构建只需要系统自带的 Command Line Tools。可选的虚拟音频环回功能需要用户
自行安装 BlackHole 驱动，但它不是构建依赖。
