#!/bin/bash
# 校验（或修复）预编译核心的 Swift 接口，确保它能被「比维护者更旧」的编译器读取。
#
# 为什么需要这一步
# ----------------
# Core/TuneCCore.swiftinterface 是预编译核心对外暴露的唯一接口：使用者只拿到
# 二进制 libTuneCCore.a 和这个文本接口。它的兼容性直接决定别人能不能从源码
# 构建 TuneC —— 而多数使用者的工具链比维护者旧。
#
# Swift 6 编译器在导出接口时有两个「对旧编译器不友好」的行为：
#   1. 自动为部分类型插入 `extension … : Swift.BitwiseCopyable {}`
#      （BitwiseCopyable 是 Swift 6 才有的协议）→ 旧编译器：
#        error: no type named 'BitwiseCopyable' in module 'Swift'
#   2. 在文件头写入自身版本（swift-compiler-version）→ 旧编译器读到更新的版本
#      会直接拒载：
#        error: failed to build module 'TuneCCore'; this SDK is not supported by
#        the compiler (the SDK is built with 'Apple Swift version 6.1.2 …',
#        while this compiler is 'Apple Swift version 5.10 …')
#
# 这两条都会让「比维护者旧」的编译器构建失败，而 Swift 官方并不保证
# 「旧编译器能读新编译器导出的接口」。因此这里把接口归一化成向后兼容形态，
# 并作为 CI 门禁守住它 —— 让接口不因重新生成核心而回退。
#
# 注意范围：本脚本只管接口能否被**解析**。能否**链接**还取决于 SDK 版本
# （预编译核心要求 macOS 15 SDK 或更新，见 Core/README.md 与
# scripts/diagnose-core-link.sh）。能解析 ≠ 能链接。
#
# 用法
# ----
#   ./scripts/check-core-interface.sh          # 只校验，不合格退出 1（CI 用）
#   ./scripts/check-core-interface.sh --fix    # 就地归一化（幂等，只改不合规的部分）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
IFACE="$PROJECT_DIR/Core/TuneCCore.swiftinterface"

# 向后兼容基线：接口至少要能被这个版本的编译器读取。
# 5.10 = Xcode 15.4 / Command Line Tools 15.x。
# 实际完成构建的下限由 SDK 决定（Xcode 16+），比这里更严 —— 保持接口基线更低
# 只是让产物在接口层面尽可能不挑工具链，成本为零。
BASELINE="5.10"

if [ ! -f "$IFACE" ]; then
    echo "❌ 未找到 $IFACE"
    exit 1
fi

if [ "${1:-}" = "--fix" ]; then
    echo "🔧 归一化 Core 接口（向后兼容基线 Swift ${BASELINE}）…"
    python3 - "$IFACE" "$BASELINE" <<'PY'
import re
import sys

path, baseline = sys.argv[1], sys.argv[2]


def vkey(v):
    return tuple(int(x) for x in v.split("."))


def newer_than(a, b):
    """a 是否比 b 新（按分量补零比较）"""
    ka, kb = vkey(a), vkey(b)
    n = max(len(ka), len(kb))
    ka += (0,) * (n - len(ka))
    kb += (0,) * (n - len(kb))
    return ka > kb


lines = open(path, encoding="utf-8").read().splitlines(keepends=True)
changes = []

# ① 摘掉 Swift 6 自动插入的 BitwiseCopyable conformance
kept = [l for l in lines if "BitwiseCopyable" not in l]
if len(kept) != len(lines):
    changes.append("移除 BitwiseCopyable conformance：%d 处" % (len(lines) - len(kept)))

# ② 文件头记录的生成版本高于基线时降级（已合规则原样保留，保证幂等）
out = []
for line in kept:
    if line.startswith("// swift-compiler-version:"):
        m = re.search(r"Apple Swift version ([0-9]+(?:\.[0-9]+)*)", line)
        if m and newer_than(m.group(1), baseline):
            line = "// swift-compiler-version: Apple Swift version %s\n" % baseline
            changes.append("swift-compiler-version：%s → %s" % (m.group(1), baseline))
    elif line.startswith("// swift-module-flags-ignorable:"):
        m = re.search(r"-interface-compiler-version ([0-9]+(?:\.[0-9]+)*)", line)
        if m and newer_than(m.group(1), baseline):
            line = line.replace(m.group(1), baseline)
            changes.append("-interface-compiler-version：%s → %s" % (m.group(1), baseline))
    out.append(line)

if changes:
    open(path, "w", encoding="utf-8").write("".join(out))
    for c in changes:
        print("   " + c)
else:
    print("   无需改动（已符合基线）")
PY
    echo "   完成"
fi

# ── 校验 ────────────────────────────────────────────────────────────────
fail=0
issues=""

if grep -q "BitwiseCopyable" "$IFACE"; then
    issues="${issues}
  · 含 Swift 6 专属的 BitwiseCopyable conformance（旧编译器不认识该协议）
$(grep -n 'BitwiseCopyable' "$IFACE" | head -5 | sed 's/^/    /')"
    fail=1
fi

GEN="$(grep -oE '^// swift-compiler-version: Apple Swift version [0-9]+(\.[0-9]+)*' "$IFACE" \
        | head -1 | grep -oE '[0-9]+(\.[0-9]+)*$' || true)"

if [ -z "$GEN" ]; then
    issues="${issues}
  · 无法从文件头解析 swift-compiler-version"
    fail=1
else
    LOWEST="$(printf '%s\n%s\n' "$BASELINE" "$GEN" | sort -V | head -1)"
    if [ "$LOWEST" != "$BASELINE" ]; then
        issues="${issues}
  · 接口标记的生成版本为 ${GEN}，高于向后兼容基线 ${BASELINE}
    （Swift ${BASELINE} 及更旧的编译器会拒载该接口）"
        fail=1
    fi
fi

if [ "$fail" -ne 0 ]; then
    echo "❌ Core 接口向后兼容检查未通过：${issues}"
    echo
    echo "   修复：bash scripts/check-core-interface.sh --fix"
    echo "   （核心接口通常是在重新生成后回退的；修完请核对 public API 是否有变化）"
    exit 1
fi

echo "✅ Core 接口向后兼容检查通过（生成版本 ${GEN} ≤ 基线 ${BASELINE}）"
