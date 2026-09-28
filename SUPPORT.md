# 获取帮助

遇到问题了？请按下面顺序来，绝大多数情况可以自助解决。

## 第一步：先查文档与既有讨论

| 资源 | 用来解决什么 |
| --- | --- |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | **先看这个。** 常见问题与排查步骤 |
| [README.md 常见问题](README.md#常见问题) | 调不了音量、麦克风指示点、要不要装 BlackHole 等高频疑问 |
| [docs/PERMISSIONS.md](docs/PERMISSIONS.md) | 权限相关：授权了还是不生效、如何撤销授权 |
| [docs/BUILD.md](docs/BUILD.md) | 从源码构建失败 |
| [Issues](https://github.com/iRoy930/TuneC/issues) | 搜索是否已经有人遇到过同样的问题 |
| [Discussions](https://github.com/iRoy930/TuneC/discussions) | 开放式提问、使用交流、想法讨论 |

## 第二步：该去哪里问

- **使用疑问、配置咨询、想法交流** → 发到 [Discussions](https://github.com/iRoy930/TuneC/discussions)
- **确认是缺陷（可复现、有明确错误行为）** → 开 [Issue](https://github.com/iRoy930/TuneC/issues)
- **安全漏洞** → **不要开公开 issue**，请按 [SECURITY.md](SECURITY.md) 私下报告

## 第三步：提问时必须附上的信息

没有这些信息，问题基本无法定位。请一次性贴全：

### 1. 环境信息

- **macOS 版本**（例如 macOS 14.5 / macOS 13.6）
- **芯片**：Apple Silicon 还是 Intel
- **TuneC 版本**（Release 版本号，或说明是自己构建的）
- **显示器型号**与连接方式（Type-C 直连 / DisplayPort / HDMI / 是否经过扩展坞）

### 2. 自检输出

在终端运行，并把**完整输出**贴上来（不要只贴结论那一行）：

```bash
/Applications/TuneC.app/Contents/MacOS/TuneC --selfcheck
```

如果你是自己构建的，路径相应改为：

```bash
build/TuneC.app/Contents/MacOS/TuneC --selfcheck
```

自检报告会列出每项检查的结果（通过 / 跳过 / 失败）。**跳过项也要贴**——它能说明是环境不具备，还是功能真的没工作。

### 3. 日志

运行以下命令，把输出一并贴上：

```bash
tail -n 200 /tmp/tunec.log
```

复现问题后立刻取日志，相关性最高。如果日志很长，请至少包含**问题发生前后各 50 行**。

### 4. 问题描述

请明确写清：

- **复现步骤**：从启动应用到问题出现，你依次做了什么
- **期望行为**：你认为应该发生什么
- **实际行为**：实际发生了什么
- **是否稳定复现**：每次必现，还是偶尔出现

### 5. 截图（如适用）

问题与菜单、滑块、HUD 显示有关时，请附上截图。

---

## 提问模板

可以直接复制下面这段填写：

```markdown
### 环境
- macOS 版本：
- 芯片：
- TuneC 版本：
- 显示器型号与连接方式：

### 复现步骤
1.
2.
3.

### 期望行为

### 实际行为

### 是否稳定复现

### 自检输出
（粘贴 `TuneC --selfcheck` 的完整输出）

### 日志
（粘贴 `/tmp/tunec.log` 的相关片段）

### 补充信息 / 截图
```

---

## 我们不做的事

为了管理预期，以下内容不在支持范围内：

- 修改 `Core/` 目录下的预编译二进制行为（见 [CONTRIBUTING.md](CONTRIBUTING.md)）
- 音频后处理功能（EQ、混响等）——本项目不提供，也不计划提供
- 非官方渠道下载的、被重新打包过的 TuneC 副本
- 与 TuneC 无关的 macOS 音频问题

## 如果你是来帮忙的

欢迎！请先读 [CONTRIBUTING.md](CONTRIBUTING.md) 与 [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)。
