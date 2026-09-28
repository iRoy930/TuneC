#!/bin/bash
# 从编译/链接输出里定位「预编译核心与当前工具链不兼容」这一类失败。
#
# 背景
# ----
# Core/libTuneCCore.a 由特定版本的 Swift / macOS SDK 导出，其 .o 成员携带
# 「自动链接」（LC_LINKER_OPTION）要求。自 Swift 6 / macOS 15 SDK 起，Swift 标准库
# 被拆成若干独立库：
#   libswift_Builtin_float  libswift_errno  libswift_math  libswift_signal
#   libswift_stdio  libswift_time  libswiftsys_time  libswiftunistd
# 归档因此要求链接它们，而这些 .tbd 存根只存在于 macOS 15 SDK 中。
#
# 用更旧的 SDK（例如 Xcode 15.4 自带的 SDK 14.5）链接时，链接器既找不到这些库，
# 又无法满足 __swift_FORCE_LOAD_$_swift_* 标记，输出的是：
#   ld: warning: Could not find or use auto-linked library 'swift_math': ...
#   Undefined symbols for architecture arm64:
#     "__swift_FORCE_LOAD_$_swift_math", referenced from: ...
# 这段信息指不到根因上。本脚本把日志读进来，命中该特征时给出可读诊断。
#
# 注意：接口能否被**解析**（见 check-core-interface.sh）与能否被**链接**是两件事。
# Swift 5.10 能读懂 Core/TuneCCore.swiftinterface，但它的 SDK 里没有上述 .tbd，
# 链接照样失败。
#
# 用法
# ----
#   bash scripts/diagnose-core-link.sh --log build.log
#   cat build.log | bash scripts/diagnose-core-link.sh --log -
#   --sdk /path/to/MacOSX.sdk   指定 SDK（默认取 xcrun 的结果）
#
# 退出码
# ------
#   0 = 识别为「预编译核心与工具链不兼容」，已打印诊断
#   1 = 不是这一类失败（调用方自行显示原始输出即可）

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE=""
SDK_PATH=""

while [ $# -gt 0 ]; do
    case "$1" in
        --log) shift; LOG_FILE="${1:-}" ;;
        --sdk) shift; SDK_PATH="${1:-}" ;;
        -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
        *) echo "未知参数: $1（用 --help 查看用法）" >&2; exit 1 ;;
    esac
    shift
done

if [ -z "$LOG_FILE" ]; then
    echo "缺少 --log 参数" >&2
    exit 1
fi

if [ "$LOG_FILE" = "-" ]; then
    LOG_CONTENT="$(cat)"
elif [ -f "$LOG_FILE" ]; then
    LOG_CONTENT="$(cat "$LOG_FILE")"
else
    echo "日志文件不存在: $LOG_FILE" >&2
    exit 1
fi

# ── 特征识别 ─────────────────────────────────────────────────────────────────
# 只有「自动链接失败」+「force-load 标记未解析」同时出现，才归到这一类。
MISSING_LIBS="$(printf '%s\n' "$LOG_CONTENT" \
    | grep -oE "auto-linked library '[^']+'" 2>/dev/null \
    | sed "s/auto-linked library '//; s/'$//" | sort -u)"
MISSING_FRAMEWORKS="$(printf '%s\n' "$LOG_CONTENT" \
    | grep -oE "auto-linked framework '[^']+'" 2>/dev/null \
    | sed "s/auto-linked framework '//; s/'$//" | sort -u)"

if ! printf '%s\n' "$LOG_CONTENT" | grep -q "__swift_FORCE_LOAD_"; then
    exit 1
fi
if [ -z "$MISSING_LIBS" ]; then
    exit 1
fi

# ── SDK 提供情况 ─────────────────────────────────────────────────────────────
if [ -z "$SDK_PATH" ] || [ ! -d "$SDK_PATH" ]; then
    SDK_PATH="$(xcrun --show-sdk-path 2>/dev/null || true)"
fi
SDK_VERSION=""
if [ -n "$SDK_PATH" ] && [ -d "$SDK_PATH" ]; then
    SDK_VERSION="$(/usr/libexec/PlistBuddy -c "Print :ProductVersion" \
        "${SDK_PATH}/SDKSettings.plist" 2>/dev/null || true)"
    [ -n "$SDK_VERSION" ] || SDK_VERSION="$(basename "${SDK_PATH}" .sdk | sed 's/^MacOSX//')"
fi

sdk_has_lib() {
    # $1 = SDK 路径, $2 = 库名（不含 lib 前缀与 .tbd 后缀）
    local sdk="$1" name="$2" d
    for d in "${sdk}/usr/lib/swift" "${sdk}/usr/lib" "${sdk}/usr/lib/system"; do
        [ -f "${d}/lib${name}.tbd" ] && return 0
    done
    return 1
}

# 若当前 SDK 里其实都有这些存根，说明不是「SDK 过旧」这一类问题，交给调用方显示原文
ALL_PRESENT=1
for lib in $MISSING_LIBS; do
    sdk_has_lib "$SDK_PATH" "$lib" || ALL_PRESENT=0
done
[ "$ALL_PRESENT" -eq 1 ] && exit 1

# ── 诊断输出 ─────────────────────────────────────────────────────────────────
echo ""
echo "❌ 无法链接预编译核心 Core/libTuneCCore.a"
if [ -n "$SDK_PATH" ]; then
    echo ""
    echo "   当前 SDK：${SDK_PATH}（${SDK_VERSION}）"
fi
echo ""
echo "   该 SDK 缺少以下自动链接库的存根（.tbd），链接器无法满足预编译核心的要求："
for lib in $MISSING_LIBS; do
    echo "     · lib${lib}.tbd"
done
if [ -n "$MISSING_FRAMEWORKS" ]; then
    echo ""
    echo "   同时缺少以下自动链接框架："
    for fw in $MISSING_FRAMEWORKS; do
        echo "     · ${fw}.framework"
    done
fi

echo ""
echo "   原因：上述 Swift 分体运行时库自 macOS 15 SDK（Xcode 16）起才提供，"
echo "   而 Core/libTuneCCore.a 是用更新版本的 SDK 导出的。Swift 官方并不保证"
echo "   更旧的工具链能链接新工具链产出的静态库，因此本仓库的预编译核心要求"
echo "   Xcode 16 / macOS 15 SDK 或更新。"
echo ""
echo "   处理：升级工具链后重试 ——"
echo "     · 升级 Command Line Tools（或到 https://developer.apple.com/download/all/ 下载对应版本）"
echo "     · 或安装 Xcode 16+ 后执行：sudo xcode-select -s /Applications/Xcode.app"

CANDIDATES=""
for sdk in /Library/Developer/CommandLineTools/SDKs/*.sdk \
           /Applications/Xcode*.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/*.sdk; do
    [ -d "$sdk" ] || continue
    ok=1
    for lib in $MISSING_LIBS; do
        sdk_has_lib "$sdk" "$lib" || ok=0
    done
    if [ "$ok" -eq 1 ]; then
        CANDIDATES="${CANDIDATES} $(basename "${sdk}")"
    fi
done
if [ -n "$CANDIDATES" ]; then
    echo ""
    echo "   本机已安装、且含所需存根的 SDK：${CANDIDATES}"
    echo "   （若其中一个来自完整 Xcode，可用 sudo xcode-select -s 切过去）"
fi

echo ""
echo "   ── 给维护者 ────────────────────────────────────────────────────"
echo "   预编译核心与导出它的工具链绑定。若要让更旧的工具链也能构建，需要用"
echo "   目标工具链重新导出 libTuneCCore.a 与 TuneCCore.swiftinterface"
echo "   （核心源码不在本仓库内）。"
echo ""
exit 0
