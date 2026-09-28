#!/bin/bash
# TuneC 构建脚本
#
# 用法: ./scripts/build.sh [release|debug]
#       NODEPLOY=1 ./scripts/build.sh          # 只构建，不部署
#       UNIVERSAL=1 ./scripts/build.sh         # 产出 arm64 + x86_64 通用二进制（发布用）
#       SIGN_IDENTITY="Apple Development: …" ./scripts/build.sh
#
# 依赖: Xcode Command Line Tools（swiftc / clang）。不需要完整 Xcode，不使用 SPM。
#
# 本仓库是 TuneC 的开源外壳：只有菜单栏 UI、热键、滚轮手势与自检等外层代码。
# 音频设备管理、虚拟音频环回、DDC/CI 显示控制等核心能力由预编译静态库
# Core/libTuneCCore.a 提供，其公开接口见 Core/TuneCCore.swiftinterface。
# 因此 Sources/TuneC 里的每个文件都只通过顶部 `import TuneCCore` 与核心耦合。

set -e

usage() {
    cat <<'USAGE'
用法: ./scripts/build.sh [release|debug]

环境变量:
  NODEPLOY=1       只构建，不部署到 ~/Applications
  UNIVERSAL=1      产出 arm64 + x86_64 通用二进制（发布用）
  SIGN_IDENTITY=…  指定签名身份（默认 "-"，即 ad-hoc）

构建模式（第一个位置参数，可省略，默认 release）:
  release   优化构建（-O）
  debug     不优化构建（-Onone）
USAGE
}

# 校验构建模式：只接受 空 / release / debug。
# 拼错模式（如 bogus）原先会静默落到 debug 分支并打印"构建成功"，这里直接拦掉。
case "${1:-}" in
    "" | release | debug) ;;
    *)
        echo "❌ 未知构建模式: $1" >&2
        echo "" >&2
        usage >&2
        exit 2
        ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_MODE="${1:-release}"
APP_NAME="TuneC"
APP_BUNDLE="$PROJECT_DIR/build/$APP_NAME.app"
EXECUTABLE="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
CORE_DIR="$PROJECT_DIR/Core"
APP_SRC="$PROJECT_DIR/Sources/TuneC"
ARCH="$(uname -m)"
DEPLOY_TARGET="macosx13.0"

# UNIVERSAL=1 → 同时编 arm64 与 x86_64 再合成通用二进制（发版用）。
# 核心库 Core/libTuneCCore.a 本身就是通用库，两个架构都能直接链接。
if [ "${UNIVERSAL:-0}" = "1" ]; then
    ARCH_LIST="arm64 x86_64"
    ARCH_DESC="universal (arm64 + x86_64)"
else
    ARCH_LIST="$ARCH"
    ARCH_DESC="$ARCH"
fi

echo "═══════════════════════════════════════════"
echo "  TuneC 构建 ($BUILD_MODE, $ARCH_DESC)"
echo "═══════════════════════════════════════════"

# 检查 swiftc
if ! command -v swiftc &> /dev/null; then
    echo "❌ 未找到 swiftc，请安装 Command Line Tools: xcode-select --install"
    exit 1
fi

# SDK：优先用 xcrun，失败再退回 Command Line Tools 的默认位置
SDK_PATH="$(xcrun --show-sdk-path 2>/dev/null || true)"
if [ -z "$SDK_PATH" ] || [ ! -d "$SDK_PATH" ]; then
    SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
fi
if [ ! -d "$SDK_PATH" ]; then
    echo "❌ 未找到 macOS SDK，请安装 Xcode Command Line Tools: xcode-select --install"
    exit 1
fi

# 检查核心静态库
if [ ! -f "$CORE_DIR/libTuneCCore.a" ] || [ ! -f "$CORE_DIR/TuneCCore.swiftinterface" ]; then
    echo "❌ 缺少核心产物，Core/ 下应有 libTuneCCore.a 与 TuneCCore.swiftinterface"
    exit 1
fi

echo "🔧 编译器: $(swiftc --version | head -1)"
echo "📱 SDK: $SDK_PATH"
echo "📦 核心库: $(du -h "$CORE_DIR/libTuneCCore.a" | cut -f1)  $CORE_DIR/libTuneCCore.a"
echo ""

# 编译参数
if [ "$BUILD_MODE" = "release" ]; then
    OPT_FLAG="-O"
else
    OPT_FLAG="-Onone"
fi

# 组装 App Bundle
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
if [ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    echo "🧩 应用图标: AppIcon.icns ($(du -h "$PROJECT_DIR/Resources/AppIcon.icns" | cut -f1))"
else
    echo "⚠️  无应用图标（Resources/AppIcon.icns 不存在）"
fi

# 编译并链接核心静态库（UNIVERSAL=1 时逐架构编译后 lipo 合成）
#
#   -Xlinker -weak_framework -Xlinker CoreDisplay：CoreDisplay 是 Apple 私有框架
#   （SDK 里只有 .tbd 存根），改成弱链接，避免将来系统移除该框架时 dyld 在
#   加载期就直接崩溃；核心侧已对该符号做判空降级。
#   -Xlinker -x：链接期不写本地符号（配合产出后的 strip -S -x），
#   让预编译核心的私有成员名不出现在最终二进制里。
SLICES=()
for slice in $ARCH_LIST; do
    SLICE_OUT="$PROJECT_DIR/build/obj/TuneC-$slice"
    SLICE_LOG="$PROJECT_DIR/build/obj/TuneC-$slice.buildlog"
    mkdir -p "$PROJECT_DIR/build/obj"
    echo "🔨 编译 Swift 源码 [$slice] 并链接 libTuneCCore.a…"

    # 编译输出先落盘：成功且无告警时完全静默（与改造前一致），
    # 失败时交给诊断脚本定位根因。
    if ! swiftc $OPT_FLAG \
        -target "$slice-apple-$DEPLOY_TARGET" \
        -sdk "$SDK_PATH" \
        -I "$CORE_DIR" \
        -L "$CORE_DIR" \
        -lTuneCCore \
        -framework AppKit \
        -framework CoreAudio \
        -framework AudioToolbox \
        -framework AVFoundation \
        -framework Carbon \
        -framework SwiftUI \
        -Xlinker -weak_framework -Xlinker CoreDisplay \
        -Xlinker -x \
        "$APP_SRC/"*.swift \
        -o "$SLICE_OUT" > "$SLICE_LOG" 2>&1
    then
        echo ""
        echo "──── 编译 / 链接失败（${slice}）───────────────────────────"
        # 预编译核心与导出它的工具链绑定：若当前 SDK 缺少核心所要求的 Swift
        # 分体运行时存根，链接器只会报一串 auto-linked library 与 FORCE_LOAD，
        # 指不到根因上。这里是唯一能拿到真实链接输出的地方，交给诊断脚本解读；
        # 识别不出来时退回显示原始输出的尾部。
        if ! bash "$SCRIPT_DIR/diagnose-core-link.sh" --log "$SLICE_LOG" --sdk "$SDK_PATH"; then
            tail -n 30 "$SLICE_LOG"
        fi
        echo "──────────────────────────────────────────────────────────"
        exit 1
    fi

    if [ -s "$SLICE_LOG" ]; then
        cat "$SLICE_LOG"
    fi
    rm -f "$SLICE_LOG"
    SLICES+=("$SLICE_OUT")
done

if [ "${#SLICES[@]}" -gt 1 ]; then
    echo "🔗 lipo 合成通用可执行文件…"
    lipo -create "${SLICES[@]}" -output "$EXECUTABLE"
else
    cp "${SLICES[0]}" "$EXECUTABLE"
fi

# 剥离本地符号与调试信息（必须在 codesign 之前做）
strip -S -x "$EXECUTABLE"
echo "✅ 编译完成 ($(lipo -info "$EXECUTABLE" | sed 's/.*architecture[s]*: //'))"

# ★ 清理 AppleDouble 伴生文件（._*）
#   某些文件系统（部分外置盘、网络共享、跨平台交换卷）会为每个文件生成 ._xxx
#   伴生文件；codesign 会把它当作"未签名的子组件"而报错：
#     code object is not signed at all / In subcomponent: .../._TuneC
find "$APP_BUNDLE" -name '._*' -delete >/dev/null 2>&1 || true
find "$APP_BUNDLE" -name '.DS_Store' -delete >/dev/null 2>&1 || true

# 代码签名：默认 ad-hoc（本地运行足够，且无需任何证书）
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
echo "✍️  代码签名 (identity=$SIGN_IDENTITY)..."
codesign --force --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
codesign --verify --verbose=1 "$APP_BUNDLE" 2>&1 | tail -3
echo "✅ 签名完成"

# 部署到 ~/Applications（跳过 NODEPLOY=1）
# 复制后必须再次清理 ._* 并重新签名 —— 跨文件系统拷贝会带出伴生文件
if [ "${NODEPLOY:-0}" != "1" ]; then
    DEST="$HOME/Applications/$APP_NAME.app"
    echo ""
    echo "📲 部署到 $DEST …"
    # 原地更新，**不要** rm -rf 整个 .app：
    #   在 ~/Applications 这类受保护目录里，删除整个 app bundle 会被系统转成
    #   「移到废纸篓」——每次构建都在废纸篓留一份副本，而这些副本会被
    #   Spotlight / Finder 扫进 LaunchServices，累积成同 bundle id 的死记录，
    #   最终让图标归属与「打开方式」不再确定。
    #   只替换 Contents：$DEST 自身的 inode 不变（LS 记录保持有效），
    #   且被删的 Contents 不带 .app 后缀，不会被当作应用注册。
    if [ -d "$DEST/Contents" ]; then
        rm -rf "$DEST/Contents"
    fi
    mkdir -p "$DEST"
    ditto "$APP_BUNDLE" "$DEST"
    find "$DEST" -name '._*' -delete >/dev/null 2>&1 || true
    find "$DEST" -name '.DS_Store' -delete >/dev/null 2>&1 || true
    xattr -cr "$DEST" 2>/dev/null || true
    codesign --force --sign "$SIGN_IDENTITY" "$DEST" >/dev/null 2>&1 || true

    # 重新注册到 LaunchServices。
    # 上面只替换了 Contents 子目录、保住了 $DEST 自身的 inode，但 LaunchServices
    # 的记录按 路径 + inode 建立 —— 历史上用「整体 rm -rf 再 ditto」部署过留下的
    # 死记录、以及被 Finder / Spotlight 扫进来的副本，都可能与本次部署抢同一
    # bundle id：失效的记录不会被新记录自动顶掉，于是 Finder 解析不到
    # CFBundleIconFile，图标退化成通用占位图（app 本身仍能正常运行）。
    # 每次部署显式重注册一次，代价极低。
    LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    if [ -x "$LSREGISTER" ]; then
        "$LSREGISTER" -f "$DEST" >/dev/null 2>&1 || true
        # 顺带摘除「构建产物自身」的注册。Finder / Spotlight 扫到构建目录里的 .app
        # 会把它按同一个 bundle id 注册成第二条记录 —— 图标归属与「打开方式」都会
        # 变得不确定（这条记录会随每次构建反复出现，所以必须每次清）。
        "$LSREGISTER" -u "$APP_BUNDLE" >/dev/null 2>&1 || true
    fi

    echo "   → $DEST"
fi

echo ""
echo "═══════════════════════════════════════════"
echo "  构建成功!"
echo "═══════════════════════════════════════════"
echo "  📦 App Bundle: $APP_BUNDLE"
echo "  📏 大小: $(du -sh "$APP_BUNDLE" | cut -f1)"
echo "  🚀 启动: open '$APP_BUNDLE'"
echo "  🧪 自检: '$EXECUTABLE' --selfcheck"
echo "═══════════════════════════════════════════"
