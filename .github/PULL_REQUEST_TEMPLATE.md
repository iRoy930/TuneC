## 变更说明

<!-- 简要描述这个 PR 做了什么、为什么需要它 -->

## 变更类型

- [ ] 🐛 Bug 修复
- [ ] ✨ 新功能
- [ ] 📝 文档 / 注释
- [ ] 🧹 重构（无行为变化）
- [ ] 🔧 构建 / CI / 工程配置
- [ ] 其它：______

## 关联 Issue

<!-- 例如 Closes #12；没有关联 issue 可写「无」 -->

## 自测清单

- [ ] 本地构建通过：`NODEPLOY=1 bash scripts/build.sh release`
- [ ] 已运行自检且汇总行 ❌ 计数为 0：`build/TuneC.app/Contents/MacOS/TuneC --selfcheck`
- [ ] 本次改动**未修改 `Core/` 目录下任何文件**

> ⚠️ **关于 `Core/`**
> `Core/` 是闭源预编译二进制核心（`Core/libTuneCCore.a` 与
> `Core/TuneCCore.swiftinterface`），公开仓库中不包含它的源码。
> 因此**任何修改 `Core/` 的 PR 都会被关闭**——这些改动无法被审阅或验证。
> 如果你怀疑问题出在核心内部，请改为提交 Issue 并附上复现方式与自检输出。

## 截图 / 录屏

<!-- 涉及界面、菜单或 HUD 变化的改动请附图 -->

## 备注

<!-- 还有什么需要维护者知道的？ -->
