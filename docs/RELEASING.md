# 发版流程

本页供维护者使用，描述如何发布一个新版本。

## 仓库地址

本仓库的规范地址为 **`iRoy930/TuneC`**（<https://github.com/iRoy930/TuneC>）。
仓库内所有对外链接——README 徽章与克隆命令、Releases 链接、Issue 模板里的
Discussions / 排障 / 权限链接、CHANGELOG 的版本对比链接、SECURITY 的私密报告入口
——均已指向该地址，无需再做替换。

若日后仓库**改名或迁移**，需同步更新全仓引用：

```bash
OLD='iRoy930/TuneC'
NEW='<新用户名或组织>/<新仓库名>'

# macOS 的 sed 用 -i ''，但若 sed 被 toybox 覆盖则不接受该写法；
# perl 的写法两端通用，推荐使用：
grep -rl "$OLD" . --exclude-dir=.git | xargs perl -pi -e "s|\Q$OLD\E|$NEW|g"

# 确认已无残留
grep -rn "$OLD" . --exclude-dir=.git
```

然后核对 Markdown 相对内链仍然有效（本仓库的内链是相对路径，不受仓库改名影响），
并同步更新 `.gitignore` 与 CI 中可能硬编码的路径。

## 包标识符（`CFBundleIdentifier`）

`Resources/Info.plist` 里的 `CFBundleIdentifier` 决定了应用在系统里的身份
（TCC 权限记录、偏好文件路径、更新识别都以它为准）。**一旦对外发布过就不能再改**——
改了会被系统视为另一个应用，用户此前授予的权限全部失效，并可能同时存在两个副本。

当前值已定为 **`io.github.iRoy930.tunec`**，与仓库地址保持一致；
`docs/PERMISSIONS.md` 的 `tccutil` 示例已同步更新。

**自 `v1.0.0` 起此值冻结。** 后续任何版本都不得修改——包括仓库改名或迁移组织。
仓库地址可以变，这个标识符不能变，否则等同于发布了一个全新应用。

> 若日后确实必须更换，须当作一次**破坏性变更**处理：在 CHANGELOG 的 MAJOR 段落中
> 明确说明，并在 Release notes 与 README 中提示用户需要重新授权、迁移偏好设置。

```bash
# 仅查阅当前值，不要随意改写
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" Resources/Info.plist

# 全仓引用核对（应只在 Info.plist 与文档示例中出现）
grep -rn 'io\.github\.iRoy930\.tunec' . --exclude-dir=.git
```

## 版本号规范

采用 [SemVer](https://semver.org/lang/zh-CN/)：`MAJOR.MINOR.PATCH`。

| 变更类型 | 版本位 | 示例 |
| --- | --- | --- |
| 不兼容的行为变更 | MAJOR | `1.0.0` → `2.0.0` |
| 向后兼容的新功能 | MINOR | `1.0.0` → `1.1.0` |
| 向后兼容的缺陷修复 | PATCH | `1.0.0` → `1.0.1` |

**tag 命名**：一律为 `v` + 版本号，例如 `v1.0.0`、`v1.1.0`、`v1.0.1`。
Release workflow 由 `v*` 的 tag 推送触发，请勿使用其它前缀。

## 发布步骤

### 1. 更新 CHANGELOG.md

在文件顶部新增该版本段落，标题格式需与 tag 对应，以便 workflow 提取：

```markdown
## [1.0.0] - 2026-09-28

### 新增
- ...

### 修复
- ...
```

标题支持 `## 1.0.0`、`## [1.0.0]`、`## v1.0.0` 三种写法（可跟日期等后缀）。
workflow 会从该标题的下一行开始、直到下一个 `## ` 标题为止，整段作为
Release notes。**如果找不到对应段落，会退化为按提交记录自动生成并给出告警。**

### 2. 更新版本号

编辑 `Resources/Info.plist` 中两个键：

| 键 | 作用 | 示例 |
| --- | --- | --- |
| `CFBundleShortVersionString` | 面向用户的版本号（与 tag 一致） | `1.0.0` |
| `CFBundleVersion` | 构建号（整数，单调递增） | `1` |

两者含义不同，不必相等：`CFBundleShortVersionString` 跟随版本号，`CFBundleVersion`
是每次发版都要递增的整数构建号（当前为 `1`，发布下一个版本时递增为 `2`、`3`……）。

### 3. 提交并打 tag

```bash
git add CHANGELOG.md Resources/Info.plist
git commit -m "release: v1.0.0"
git push origin main

git tag v1.0.0
git push origin v1.0.0
```

推送 tag 即触发 `.github/workflows/release.yml`。

### 4. 校验产物

workflow 会依次完成：构建（`UNIVERSAL=1 NODEPLOY=1 bash scripts/build.sh release`，
产出 arm64 + x86_64 通用二进制，并要求**零编译告警**）→ 校验 `lipo -info` 里两个
架构都在 → 跑 `--selfcheck` → 用 `ditto -c -k --keepParent` 打包成
`TuneC-v1.0.0.zip` → 提取 Release notes → 创建 Release 并上传 zip。

**发版必须构建通用二进制**：不带 `UNIVERSAL=1` 时脚本只编本机架构，
得到的是单架构产物，Intel Mac 用户装上会闪退。本地可以 `make universal` 复现这一步。

**关于自检门禁的边界**：CI runner 没有外接显示器、没有可用的音频输入/输出设备、
也没有辅助功能授权，所以自检里依赖真实设备的那些断言在 CI 上不具代表性。
因此 workflow 的硬门禁是「构建零告警 + 通用二进制完整 + 自检能完整跑完并打印汇总行」，
汇总行里的 ❌ 计数会打印出来并在大于 0 时给出警告注解，由维护者结合逐项输出判断。
**真机严格验收请在本机执行 `make verify`**（本机有真实设备，自检结果才有意义）。

发布完成后请检查：

1. Release 页面已生成，标题为 tag 名，notes 内容与 CHANGELOG 对应段落一致。
2. 附件 `TuneC-v1.0.0.zip` 存在且大小合理（应为完整 App bundle 的量级，而非几十 KB）。
3. 下载到本地解压，确认得到 `TuneC.app` 且能打开；再确认
   `lipo -info TuneC.app/Contents/MacOS/TuneC` 同时列出 `arm64` 与 `x86_64`，
   并运行 `TuneC.app/Contents/MacOS/TuneC --selfcheck` 确认 ❌ 计数为 0。
4. 若任一环节失败，修复后**删除并重新推送 tag**（或打一个新 tag），
   不要复用已发布的 tag 指向不同内容。

> CI（`ci.yml`）在 `main` 与所有 PR 上运行同等强度的构建 + 自检，
> 因此正常情况下 `main` 上的提交已经过验证。发版前仍建议确认 `main` 的最新 CI 为绿色。

## 关于 `Core/` 预编译核心

`Core/` 下的 `libTuneCCore.a` 与 `TuneCCore.swiftinterface` 是**闭源预编译核心**，
**公开仓库不包含其源码**。

- 当核心有更新时，由维护者**在私有源码树中重新构建**，然后把产物
  （通用 `libTuneCCore.a` 与配套的 `.swiftinterface`）替换进本仓库的 `Core/`。
- 核心更新往往意味着功能性变更，请在 CHANGELOG 中明确写出影响，
  **并与壳层代码的改动分开提交**，便于回溯。
- 核心是通用库（`arm64` + `x86_64`），替换后请本地用
  `make universal && make selfcheck` 复验，并确认 `Core/TuneCCore.swiftinterface`
  里没有出现 `TuneCObjCBridge` / `ddc_` / `TuneCTapCapture` 等内部符号。
- 请勿在公开仓库中修改 `Core/` 内容，也不要在 PR 中提交对它的改动
  （见 [PULL_REQUEST_TEMPLATE](../.github/PULL_REQUEST_TEMPLATE.md)）。

## 发布前检查清单

- [ ] `CHANGELOG.md` 已补充本版段落，标题能被提取（`## [x.y.z]`）
- [ ] `Resources/Info.plist` 已更新：`CFBundleShortVersionString` 为本次版本号（首个公开版本为 `1.0.0`），`CFBundleVersion` 为递增的整数构建号（首个公开版本为 `1`）
- [ ] `main` 最新一次 CI 为绿色（通用二进制的构建与自检均通过）
- [ ] tag 名符合 `vX.Y.Z`，且指向预期的提交
- [ ] 如含核心更新，`Core/` 产物已在私有源码树中重建并替换
