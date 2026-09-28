#!/bin/bash
#
# 安装 BlackHole 2ch 虚拟音频驱动（可选组件）
#
# 什么时候需要它：
#   TuneC 的「虚拟音频环回」有两条采集后端。
#     · Process Tap（默认，macOS 14.2+）—— 不需要任何驱动
#     · BlackHole（回退，macOS 13 可用）—— 需要本驱动
#   只有在 macOS 13 上、或你主动把后端切到 BlackHole 时，才需要安装它。
#
# 本脚本做什么：
#   1) 已经装了就直接退出
#   2) 否则从 BlackHole 官方 GitHub Releases 下载 2ch 安装包（本项目不再分发安装包）
#   3) 调用系统 installer 安装，并重启 coreaudiod
#
# 注意：
#   · 需要 sudo，脚本会先打印将要执行的命令，请自行确认后再运行
#   · BlackHole 由 Existential Audio 开发，以 GPL-3.0 发布，与本项目无隶属关系
#   · 卸载：sudo rm -rf /Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver && sudo killall coreaudiod
#
# 用法：
#   bash scripts/install_blackhole.sh                 # 自动下载最新 2ch 版本
#   bash scripts/install_blackhole.sh --pkg <路径>    # 用本地已有的 .pkg 离线安装
#
set -euo pipefail

BH_REPO="ExistentialAudio/BlackHole"
BH_DRIVER="/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver"
PKG_PATH=""
TMP_DIR=""

usage() {
    # 打印文件开头的注释块（跳过 shebang，遇到第一条非注释行即停止）。
    # 用 awk 而不是写死行号：原先的 sed -n '3,25p' 会把第 25 行的
    # `set -euo pipefail` 一并打印出来；写死行号也容易在注释增删后再次错位。
    awk 'NR > 1 && /^#/ { sub(/^#[[:space:]]?/, ""); print; next } NR > 1 { exit }' "$0"
}

cleanup() {
    [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ] && rm -rf "$TMP_DIR"
    return 0
}
trap cleanup EXIT

while [ $# -gt 0 ]; do
    case "$1" in
        --pkg)
            [ $# -ge 2 ] || { echo "❌ --pkg 后面要跟 .pkg 路径" >&2; exit 1; }
            PKG_PATH="$2"; shift 2 ;;
        -h|--help)
            usage; exit 0 ;;
        *)
            echo "❌ 未知参数: $1" >&2; usage >&2; exit 1 ;;
    esac
done

echo "═══════════════════════════════════════════"
echo "  BlackHole 2ch 安装"
echo "═══════════════════════════════════════════"

# ── 1. 已经装了就跳过 ────────────────────────────────────────
if [ -d "$BH_DRIVER" ] || system_profiler SPAudioDataType 2>/dev/null | grep -qi "BlackHole"; then
    echo "✅ 已检测到 BlackHole 设备，无需重复安装。"
    echo "   如需卸载：sudo rm -rf '$BH_DRIVER' && sudo killall coreaudiod"
    exit 0
fi

# ── 2. 取安装包 ──────────────────────────────────────────────
if [ -z "$PKG_PATH" ]; then
    echo "🔍 正在查询 BlackHole 最新版本…"
    API_URL="https://api.github.com/repos/$BH_REPO/releases/latest"

    JSON="$(curl -fsSL "$API_URL" 2>/dev/null || true)"
    if [ -z "$JSON" ]; then
        echo "❌ 无法访问 GitHub API（网络受限？）" >&2
        echo "   请手动下载 2ch 版安装包：" >&2
        echo "     https://github.com/$BH_REPO/releases" >&2
        echo "   然后再用：bash $0 --pkg ~/Downloads/BlackHole2ch.vX.Y.Z.pkg" >&2
        exit 1
    fi

    URL="$(printf '%s\n' "$JSON" \
        | grep -o '"browser_download_url"[^,]*BlackHole2ch[^,]*\.pkg"' \
        | head -n 1 \
        | sed -e 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"//' -e 's/"$//')"

    if [ -z "$URL" ]; then
        echo "❌ 最新 release 里没找到 2ch 的 .pkg 资产" >&2
        echo "   请手动下载：https://github.com/$BH_REPO/releases" >&2
        exit 1
    fi

    TMP_DIR="$(mktemp -d)"
    PKG_PATH="$TMP_DIR/$(basename "$URL")"
    echo "⬇️  $URL"
    curl -fL --progress-bar -o "$PKG_PATH" "$URL"
    echo "✅ 下载完成：$(du -h "$PKG_PATH" | cut -f1)"
fi

if [ ! -f "$PKG_PATH" ]; then
    echo "❌ 找不到安装包：$PKG_PATH" >&2
    exit 1
fi

# ── 3. 安装 ──────────────────────────────────────────────────
echo ""
echo "即将执行（需要 sudo 密码）："
echo "  sudo installer -pkg '$PKG_PATH' -target /"
echo "  sudo killall coreaudiod"
echo ""
sudo installer -pkg "$PKG_PATH" -target /

echo "🔄 重启 coreaudiod 让驱动生效…"
sudo killall coreaudiod || true
sleep 2

# ── 4. 验证 ──────────────────────────────────────────────────
echo ""
if [ -d "$BH_DRIVER" ]; then
    echo "✅ BlackHole 2ch 安装成功：$BH_DRIVER"
    system_profiler SPAudioDataType 2>/dev/null | grep -i "BlackHole" | sed 's/^/   /' || true
    echo ""
    echo "下一步：打开 TuneC → 在菜单里把采集后端切到「BlackHole」。"
else
    echo "⚠️  没找到 $BH_DRIVER" >&2
    echo "   可打开「音频 MIDI 设置」确认是否出现 BlackHole 2ch" >&2
    exit 1
fi
