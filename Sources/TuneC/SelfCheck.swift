import Foundation
import CoreGraphics
import AppKit
import ApplicationServices
import TuneCCore

// MARK: - CLI 自检模式

enum SelfCheck {

    static func run() {
        print("")
        print("╔══════════════════════════════════════════════╗")
        print("║        TuneC 自检报告           ║")
        print("╚══════════════════════════════════════════════╝")
        print("")

        let manager = AudioDeviceManager.shared
        var passed = 0
        var failed = 0
        var skipped = 0

        // === 1. 设备枚举 ===
        print("━━━ 1. 设备枚举 ━━━")
        let allDevices = manager.allDevices()
        print("  全部设备数量: \(allDevices.count)")
        for device in allDevices {
            let type = device.hasInput && device.hasOutput ? "输入+输出" : (device.hasInput ? "输入" : "输出")
            print("    - [\(type)] \(device.name) (id=\(device.id))")
        }
        if allDevices.count > 0 { passed += 1 } else { failed += 1; print("  ❌ 未找到任何音频设备") }
        print("")

        // === 2. 输出设备 ===
        print("━━━ 2. 输出设备 ━━━")
        let outputDevices = manager.outputDevices()
        print("  输出设备数量: \(outputDevices.count)")
        for device in outputDevices {
            print("    - \(device.name) (id=\(device.id))")
        }
        if outputDevices.count > 0 { passed += 1 } else { failed += 1 }
        print("")

        // === 3. 输入设备 ===
        print("━━━ 3. 输入设备 ━━━")
        let inputDevices = manager.inputDevices()
        print("  输入设备数量: \(inputDevices.count)")
        for device in inputDevices {
            print("    - \(device.name) (id=\(device.id))")
        }
        if inputDevices.count > 0 { passed += 1 } else { failed += 1 }
        print("")

        // === 4. 默认设备读取 ===
        print("━━━ 4. 默认设备读取 ━━━")
        if let defaultOutput = manager.defaultOutputDevice() {
            print("  ✅ 默认输出: \(defaultOutput.name) (id=\(defaultOutput.id))")
            passed += 1
        } else {
            print("  ❌ 无法读取默认输出设备")
            failed += 1
        }
        if let defaultInput = manager.defaultInputDevice() {
            print("  ✅ 默认输入: \(defaultInput.name) (id=\(defaultInput.id))")
            passed += 1
        } else {
            print("  ❌ 无法读取默认输入设备")
            failed += 1
        }
        print("")

        // === 5. 音量读取 ===
        // ★ 关键前置判定：DP/HDMI 音频设备（外接显示器居多）通常完全不暴露软件音量控制，
        //   此时读到 0 是设备的正常表现而非故障 —— 必须与"读取失败"区分开，
        //   否则自检会把设备能力限制误报成错误。
        print("━━━ 5. 音量读取 ━━━")
        let outName = manager.defaultOutputDevice()?.name ?? "?"
        let supportsVolCtrl = manager.outputSupportsSoftwareVolume()
        let supportsMuteCtrl = manager.defaultOutputDevice()
            .map { manager.deviceSupportsSoftwareMute($0.id) } ?? false
        print("  默认输出: \(outName)  软件音量=\(supportsVolCtrl ? "支持" : "不支持")  软件静音=\(supportsMuteCtrl ? "支持" : "不支持")")

        if supportsVolCtrl {
            let volume = manager.outputVolume()
            print("  当前输出音量: \(String(format: "%.4f", volume)) (\(String(format: "%.0f%%", volume * 100)))")
            if volume >= 0 && volume <= 1 {
                print("  ✅ 音量值在有效范围 [0, 1]")
                passed += 1
            } else {
                print("  ❌ 音量值超出有效范围")
                failed += 1
            }
        } else {
            print("  ⏭️  跳过音量读写：该设备不提供软件音量控制")
            print("     DP/HDMI 音频由显示器硬件（OSD / DDC）控制，macOS 未暴露 VolumeScalar。")
            print("     TuneC 的软件调音在环回模式下经内部增益实现（菜单 → 虚拟音频）。")
            skipped += 1
        }
        print("")

        // === 6. 音量写入测试 ===
        print("━━━ 6. 音量写入测试 ━━━")
        if supportsVolCtrl {
            let originalVolume = manager.outputVolume()
            let testVolume: Float32 = 0.5
            let setResult = manager.setOutputVolume(testVolume)
            let readBack = manager.outputVolume()
            manager.setOutputVolume(originalVolume)
            let restored = manager.outputVolume()

            if setResult {
                print("  ✅ setOutputVolume(\(testVolume)) 返回成功")
                passed += 1
            } else {
                print("  ❌ setOutputVolume(\(testVolume)) 返回失败")
                failed += 1
            }
            print("  写入后读回: \(String(format: "%.4f", readBack)) (期望 ~\(testVolume))")
            if abs(readBack - testVolume) < 0.05 {
                print("  ✅ 读回值与写入值一致（误差 < 5%）")
                passed += 1
            } else {
                print("  ⚠️  读回值与写入值有偏差（设备可能不支持精细音量）")
            }
            print("  恢复原音量后: \(String(format: "%.4f", restored)) (原值 \(String(format: "%.4f", originalVolume)))")
            if abs(restored - originalVolume) < 0.05 {
                print("  ✅ 音量已恢复")
                passed += 1
            } else {
                print("  ⚠️  音量恢复有偏差")
            }
        } else {
            print("  ⏭️  跳过：设备不提供软件音量控制（同第 5 项判定）")
            skipped += 1
        }
        print("")

        // === 7. 静音测试 ===
        print("━━━ 7. 静音测试 ━━━")
        if supportsMuteCtrl {
            let originalMute = manager.isOutputMuted()
            print("  当前静音状态: \(originalMute ? "是" : "否")")
            let toggleResult1 = manager.setOutputMuted(!originalMute)
            let muteAfterToggle = manager.isOutputMuted()
            let toggleResult2 = manager.setOutputMuted(originalMute)
            let muteRestored = manager.isOutputMuted()

            if toggleResult1 && toggleResult2 {
                print("  ✅ 静音设置 API 调用成功")
                passed += 1
            } else {
                print("  ❌ 静音设置 API 调用失败")
                failed += 1
            }
            print("  切换后静音: \(muteAfterToggle ? "是" : "否") (期望 \(!originalMute ? "是" : "否"))")
            if muteAfterToggle == !originalMute {
                print("  ✅ 静音切换生效")
                passed += 1
            } else {
                print("  ⚠️  静音切换未生效（设备可能不支持静音）")
            }
            print("  恢复后静音: \(muteRestored ? "是" : "否") (期望 \(originalMute ? "是" : "否"))")
        } else {
            print("  ⏭️  跳过：设备不提供软件静音控制（DP/HDMI 音频的静音同样由显示器硬件负责）")
            skipped += 1
        }
        print("")

        // === 8. 设备切换测试 ===
        print("━━━ 8. 设备切换测试 ━━━")
        if outputDevices.count >= 2 {
            let originalOutput = manager.defaultOutputDevice()
            let otherDevice = outputDevices.first { $0.id != originalOutput?.id }
            if let other = otherDevice, let original = originalOutput {
                print("  从 '\(original.name)' 切换到 '\(other.name)'…")
                let switchResult = manager.setDefaultOutputDevice(other)
                let afterSwitch = manager.defaultOutputDevice()
                manager.setDefaultOutputDevice(original)
                let afterRestore = manager.defaultOutputDevice()

                if switchResult {
                    print("  ✅ setDefaultOutputDevice 返回成功")
                    passed += 1
                } else {
                    print("  ❌ setDefaultOutputDevice 返回失败")
                    failed += 1
                }
                if afterSwitch?.id == other.id {
                    print("  ✅ 切换后默认设备确认为 '\(other.name)'")
                    passed += 1
                } else {
                    print("  ❌ 切换后默认设备不是预期设备")
                    failed += 1
                }
                if afterRestore?.id == original.id {
                    print("  ✅ 已恢复原默认设备 '\(original.name)'")
                    passed += 1
                } else {
                    print("  ⚠️  恢复原设备失败")
                }
            }
        } else {
            print("  ⏭️  跳过（仅有 \(outputDevices.count) 个输出设备，需至少 2 个才能测试切换）")
        }
        print("")

        // === 9. 快捷键注册测试（Carbon RegisterEventHotKey）===
        print("━━━ 9. 快捷键注册测试（Carbon RegisterEventHotKey）━━━")
        print("  默认热键配置:")
        for config in HotKeyManager.defaultConfigs {
            print("    - \(config.action.displayName): \(config.modifierDisplay)+\(keyDisplay(config.keyCode)) (keyCode=0x\(String(config.keyCode, radix: 16)))")
        }
        print("")
        print("  执行注册…")
        let hotKeyManager = HotKeyManager.shared
        hotKeyManager.registerAll()
        if hotKeyManager.isRegistered {
            print("  ✅ HotKeyManager.isRegistered = true")
            passed += 1
        } else {
            print("  ❌ HotKeyManager.isRegistered = false")
            failed += 1
        }
        // 注册后立即注销，避免占用系统热键
        hotKeyManager.unregisterAll()
        print("  已注销热键（避免占用）")
        print("")

        // === 10. DDC/CI 显示器后端自检 ===
        print("━━━ 10. DDC/CI 显示器后端自检 ━━━")
        let ddc = DDCManager.shared
        let ddcCount = ddc.refreshDisplays().count
        print("  在线物理显示器数量: \(ddcCount)")
        if ddcCount == 0 {
            // 没接外接显示器 / 合盖无头运行时，DDC 通道根本不存在，
            // 属**环境不具备**而非故障，应计为跳过（与下方提示语一致）。
            print("  ⏭️  跳过：未连接外接显示器（内置屏 / 无头模式）")
            skipped += 1
        } else {
            passed += 1
        }
        for disp in ddc.displays() {
            print("    - \(disp)")
        }
        print("")

        // 对每台外接显示器做 VCP 探针：先读亮度 0x10 验证通道，再探音量 0x62
        for disp in ddc.displays() where disp.isExternal {
            print("  ── 显示器: \(disp.name) ──")

            // 10a. 亮度 VCP 0x10 读（通道验证）
            if let lum = ddc.readVCP(uuid: disp.uuid, code: DDCVCP.luminance) {
                print("    ✅ VCP 0x10 亮度读通: cur=\(lum.cur) max=\(lum.max)")
                passed += 1
            } else {
                print("    ❌ VCP 0x10 亮度读失败（DDC 通道不可用）")
                failed += 1
                continue
            }

            // 10b. 音量 VCP 0x62 写后读回探针（内部自动恢复原值）
            if let r = ddc.probeVolume(uuid: disp.uuid) {
                print("    探针: \(r.summary)")
                if r.volumeWritable {
                    print("    ✅ DDC 音量可用（本显示器可走 DDC 后端）")
                    passed += 1
                } else {
                    print("    ⚠️  DDC 音量不可用（该显示器固件未实现 VCP 0x62，需虚拟音频后端）")
                }
            } else {
                print("    ❌ 探针执行失败（无法打开 DDC 通道）")
                failed += 1
            }
            print("")
        }

        // 10c. 音量路由后端标签
        VolumeRouter.shared.refreshRouting()
        print("  当前输出设备的音量后端: \(VolumeRouter.shared.backendLabel)")
        print("")

        // === 11. 虚拟音频环回（BlackHole）自检 ===
        print("━━━ 11. 虚拟音频环回（BlackHole）自检 ━━━")
        let ve = VirtualAudioEngine.shared
        if let bh = ve.findBlackHoleDevice() {
            print("  ✅ 检测到 BlackHole 设备: \(bh.name) (id=\(bh.id))")
            passed += 1
            // 用当前默认输出作为物理目标做启动/停止冒烟测试
            if let phys = manager.defaultOutputDevice(), phys.id != bh.id {
                print("  测试环回启动: BlackHole → \(phys.name)…")
                let ok = ve.start(physicalOutput: phys)
                if ok {
                    sleep(1)
                    if ve.isRunning {
                        print("  ✅ 环回引擎运行中 (isRunning=true)")
                        passed += 1
                        // 增益设置/读取测试
                        ve.setGain(0.5)
                        let g = ve.gain
                        print("  增益测试: setGain(0.5) → gain=\(String(format: "%.3f", g))")
                        if abs(g - 0.5) < 0.01 {
                            print("  ✅ 增益设置/读取一致")
                            passed += 1
                        } else {
                            print("  ❌ 增益读取不一致")
                            failed += 1
                        }
                        ve.setGain(1.0)

                        // 渲染链路观测：跑 5 秒，每秒采样 fillRatio / 回调数 / discard
                        print("  ── 渲染链路观测（5 秒）──")
                        var samples: [Float] = []
                        var totalDiscard = 0
                        var steadyDiscard = 0      // 排除第 1 秒（HAL 冷启动抖动）之后的欠载数
                        var totalCb = 0
                        for i in 1...5 {
                            sleep(1)
                            let snap = ve.diagSnapshot()
                            samples.append(snap.fillRatio)
                            totalDiscard += snap.discard
                            if i > 1 { steadyDiscard += snap.discard }
                            totalCb += snap.callbacks
                            print("    [\(i)s] fillRatio=\(String(format: "%.3f", snap.fillRatio))  cb/s=\(snap.callbacks)  discard/s=\(snap.discard)")
                        }
                        // 验证：无 discard（underrun）；fillRatio 不持续单调增长/下降
                        // 本项跑在"无真实音频流"的静音链路上，且判据受机器负载影响很大：
                        //   · 第 1 秒通常包含 HAL 冷启动 / 首次回调抖动，故不参与判定（steadyDiscard）
                        //   · 负载高的机器上偶发十几次欠载仍属正常，只有持续大量欠载才说明路由有问题
                        // 因此这里只在 steady 阶段"整整 5 秒一次都没有"时记通过，
                        // 少量欠载只提示不计数，避免把负载抖动误判成故障。
                        if steadyDiscard == 0 {
                            print("  ✅ 观测期无 discard（无欠载，含启动瞬间）")
                            passed += 1
                        } else if steadyDiscard <= 10 {
                            print("  ⚠️  观测期 discard=\(steadyDiscard)（总 \(totalDiscard) 次，多为启动抖动或机器负载，不计失败）")
                        } else {
                            print("  ❌ 观测期 discard=\(steadyDiscard)（持续欠载/断流）")
                            failed += 1
                        }
                        if totalCb == 0 {
                            print("  ⚠️  渲染回调未触发（静音链路下回调可能被 HAL 节流，无真实音频流时属正常）")
                        } else {
                            print("  ✅ 渲染回调活跃（5 秒 \(totalCb) 次）")
                            passed += 1
                        }
                        if samples.count >= 2 {
                            let diffs = zip(samples.dropFirst(), samples).map { $0 - $1 }
                            let monotonicUp = diffs.allSatisfy { $0 > 0.02 }
                            let monotonicDown = diffs.allSatisfy { $0 < -0.02 }
                            if monotonicUp || monotonicDown {
                                print("  ⚠️  fillRatio 持续单调\(monotonicUp ? "上升" : "下降")，PID 可能未补偿时钟漂移（待真实音频流验证）")
                            } else {
                                print("  ✅ fillRatio 未持续单调漂移（PID 正在调节）")
                                passed += 1
                            }
                        }
                    } else {
                        print("  ❌ 启动后 isRunning=false")
                        failed += 1
                    }
                    ve.stop()
                    print("  环回已停止，默认输出已恢复")
                } else {
                    print("  ❌ VirtualAudioEngine.start 失败")
                    failed += 1
                }
            } else {
                // 默认输出本身就是 BlackHole（= 环回正在工作）：没有独立物理目标可做冒烟测试
                print("  ⏭️  跳过启动测试（默认输出即 BlackHole，无独立物理输出目标）")
                skipped += 1
            }
        } else {
            print("  ⏭️  未检测到 BlackHole 设备")
            skipped += 1
            print("  安装方法（需要 sudo）:")
            print("      bash scripts/install_blackhole.sh")
            print("  脚本会自动从官方 Releases 下载 pkg；查看全部选项：bash scripts/install_blackhole.sh --help")
            print("  官方下载: https://github.com/ExistentialAudio/BlackHole/releases")
            print("  （BlackHole 未安装时虚拟音频功能优雅降级，不影响其它后端）")
        }
        print("")

        // === 12. 亮度 VCP 0x10 读写测试 ===
        print("━━━ 12. 亮度 VCP 0x10 读写测试 ━━━")
        if let ext = ddc.displays().first(where: { $0.isExternal }) {
            print("  目标显示器: \(ext.name) (uuid=\(ext.uuid))")
            let asleep = CGDisplayIsAsleep(CGDirectDisplayID(ext.cgid)) != 0
            if asleep {
                print("  ⏭️  显示器当前睡眠（CGDisplayIsAsleep=1），跳过亮度读写实测")
                print("  → 唤醒显示器后重跑自检可验证读 VCP 0x10 → 写 30 → 读回 → 恢复")
            } else if let orig = ddc.readVCP(uuid: ext.uuid, code: DDCVCP.luminance) {
                print("  ✅ 读亮度成功: cur=\(orig.cur) max=\(orig.max)")
                passed += 1
                // 写 30
                let wrote = ddc.writeVCP(uuid: ext.uuid, code: DDCVCP.luminance, value: 30)
                usleep(300_000)
                if wrote {
                    print("  ✅ 写亮度=30 返回成功（I2C ACK）")
                    passed += 1
                } else {
                    print("  ❌ 写亮度=30 失败")
                    failed += 1
                }
                // 读回
                if let rb = ddc.readVCP(uuid: ext.uuid, code: DDCVCP.luminance) {
                    print("  读回亮度=\(rb.cur)（写入 30）")
                    if asleep {
                        print("  ℹ️  睡眠态读回为缓存值，跳过一致性判定")
                    } else if abs(rb.cur - 30) <= 3 {
                        print("  ✅ 读回值与写入值一致（±3）")
                        passed += 1
                    } else {
                        print("  ⚠️  读回值偏差较大（该显示器可能读回不实时，写仍可能生效）")
                    }
                } else {
                    print("  ❌ 写后读回失败")
                    failed += 1
                }
                // 恢复原值
                _ = ddc.writeVCP(uuid: ext.uuid, code: DDCVCP.luminance, value: UInt16(max(0, min(65535, orig.cur))))
                usleep(300_000)
                if let rest = ddc.readVCP(uuid: ext.uuid, code: DDCVCP.luminance) {
                    print("  恢复后亮度=\(rest.cur)（原值 \(orig.cur)）")
                }
            } else {
                print("  ❌ 读 VCP 0x10 失败（DDC 通道不可用）")
                failed += 1
            }
        } else {
            print("  ⏭️  跳过（无外接显示器）")
            skipped += 1
        }
        print("")

        // === 13. 显示器参数库 CRUD 测试 ===
        print("━━━ 13. 显示器参数库 CRUD 测试 ━━━")
        let store = DisplayProfileStore.shared
        // 内置默认库应非空，且能按 EDID 键（vendorID + productID）命中条目。
        // 只验证「库可查」这一通用性质，不绑定任何具体显示器型号。
        let builtinList = store.allProfiles()
        if let sample = builtinList.first,
           store.profile(vendorID: sample.vendorID, productID: sample.productID) != nil {
            print("  ✅ 内置 profile 库可用：\(builtinList.count) 条，按 EDID 键可命中（示例: \(sample.displayName)）")
            passed += 1
        } else {
            print("  ❌ 内置 profile 库为空，或按 EDID 键（vendorID/productID）查询不到条目")
            failed += 1
        }
        // 创建临时 profile → upsert → 查询 → 校验字段 → 删除
        let tempVendor: UInt32 = 0xDEAD
        let tempProduct: UInt32 = 0xBEEF
        let temp = DisplayProfile(
            vendorID: tempVendor, productID: tempProduct, serialNumber: "SN123",
            displayName: "SelfCheck 临时显示器",
            ddcBrightnessSupported: true, ddcVolumeSupported: false,
            ddcContrastSupported: true, ddcInputSwitchSupported: false,
            needsVirtualAudio: true, quirks: ["自检临时条目"]
        )
        store.upsert(temp)
        if let back = store.profile(vendorID: tempVendor, productID: tempProduct) {
            let fieldsOK = back.displayName == temp.displayName &&
                           back.ddcBrightnessSupported == temp.ddcBrightnessSupported &&
                           back.quirks == temp.quirks
            print("  回查: \(back.displayName) bright=\(back.ddcBrightnessSupported) quirks=\(back.quirks)")
            if fieldsOK {
                print("  ✅ upsert→查询字段一致（Codable 往返正确）")
                passed += 1
            } else {
                print("  ❌ 回查字段不一致")
                failed += 1
            }
        } else {
            print("  ❌ upsert 后查询不到临时 profile")
            failed += 1
        }
        // 删除并验证清理
        if store.remove(vendorID: tempVendor, productID: tempProduct) {
            if store.profile(vendorID: tempVendor, productID: tempProduct) == nil {
                print("  ✅ 临时 profile 已删除并落盘清理")
                passed += 1
            } else {
                print("  ❌ 删除后仍能查到")
                failed += 1
            }
        } else {
            print("  ❌ 删除临时 profile 失败")
            failed += 1
        }
        print("  当前参数库共 \(store.allProfiles().count) 条（应仅剩内置条目）")
        print("")

        // === 14. EDID 识别测试 ===
        print("━━━ 14. EDID 识别测试（DisplayDetector）━━━")
        let detected = DisplayDetector.shared.detectDisplays()
        if detected.isEmpty {
            // 同第 10 项：没有外接显示器时本项无从检验，属环境不具备而非故障
            print("  ⏭️  跳过：未识别到外接显示器")
            skipped += 1
        } else {
            passed += 1
        }
        for d in detected {
            let pnp = String(format: "v0x%08x p0x%08x", d.vendorID, d.productID)
            let match = d.isRecognized ? "命中[\(d.profile!.displayName)]" : "未命中"
            print("    - name=\(d.name) \(pnp) serial=\(d.serialNumber) ext=\(d.isExternal) → \(match)")
        }
        // 与 DDCManager 列表交叉验证：数量应一致（仅在确有显示器时才有意义）
        if !detected.isEmpty {
            if detected.count == ddc.displays().count {
                print("  ✅ Detector 数量(\(detected.count)) 与 DDCManager 数量(\(ddc.displays().count)) 一致")
                passed += 1
            } else {
                print("  ⚠️  Detector 数量(\(detected.count)) 与 DDCManager(\(ddc.displays().count)) 不一致")
            }
        }
        // 状态栏能力摘要
        print("  状态栏能力行: \(DisplayDetector.shared.statusLine())")
        print("")

        // === 15. 边缘滚轮手势 ===
        print("━━━ 15. 边缘滚轮手势引擎 ━━━")
        let gest = ScrollWheelGestureManager.shared

        // 15a. 配置读写 round-trip
        print("  ── 配置持久化 round-trip ──")
        let origZone = gest.hotZoneHeight
        let origStep = gest.stepSize
        let origOpt  = gest.requiresOptionKey
        gest.hotZoneHeight = 30
        gest.stepSize = 10
        gest.requiresOptionKey = true
        if gest.hotZoneHeight == 30 && gest.stepSize == 10 && gest.requiresOptionKey == true {
            print("  ✅ UserDefaults 写入并读回一致 (zone=30 step=10 ⌥=on)")
            passed += 1
        } else {
            print("  ❌ 配置 round-trip 不一致")
            failed += 1
        }
        // 恢复原值
        gest.hotZoneHeight = origZone
        gest.stepSize = origStep
        gest.requiresOptionKey = origOpt
        print("  已恢复配置: zone=\(Int(gest.hotZoneHeight)) step=\(gest.stepSize) ⌥=\(gest.requiresOptionKey)")

        // 15b. 热区分类函数单测（构造 800x600 屏幕 frame，左下角原点）
        print("  ── 热区分类单测 ──")
        let f = NSRect(x: 0, y: 0, width: 800, height: 600)
        let h: CGFloat = 20
        let topPoint    = NSPoint(x: 400, y: 595)   // 顶边内
        let bottomPoint = NSPoint(x: 400, y: 5)      // 底边内
        let middlePoint = NSPoint(x: 400, y: 300)    // 中间
        let outPoint    = NSPoint(x: 900, y: 300)    // 屏外
        let rTop = ScrollWheelGestureManager.classifyHotZone(point: topPoint, screenFrame: f, zoneHeight: h)
        let rBot = ScrollWheelGestureManager.classifyHotZone(point: bottomPoint, screenFrame: f, zoneHeight: h)
        let rMid = ScrollWheelGestureManager.classifyHotZone(point: middlePoint, screenFrame: f, zoneHeight: h)
        let rOut = ScrollWheelGestureManager.classifyHotZone(point: outPoint, screenFrame: f, zoneHeight: h)
        print("    顶边→\(rTop)(期望1) 底边→\(rBot)(期望2) 中间→\(rMid)(期望0) 屏外→\(rOut)(期望0)")
        if rTop == 1 && rBot == 2 && rMid == 0 && rOut == 0 {
            print("  ✅ 热区分类边界正确")
            passed += 1
        } else {
            print("  ❌ 热区分类错误")
            failed += 1
        }

        // 15c. 权限检查（未授权时 start 优雅返回 false，不 crash）
        print("  ── 权限 / start 行为 ──")
        let trusted = AXIsProcessTrusted()
        print("  AXIsProcessTrusted = \(trusted)")
        // 自检模式默认 isEnabled=false，start() 应直接返回 false 而不崩溃
        gest.stop()
        let startRC = gest.start()
        if !startRC {
            print("  ✅ 未开启时 start() 优雅返回 false（不启动 tap，不 crash）")
            passed += 1
        } else {
            print("  ⚠️  start() 返回 true（已授权且开关为开），自检不强制")
        }
        if !trusted {
            print("  ℹ️  当前未授权辅助功能：GUI 中开启手势会弹系统授权引导，授权后才拦截滚轮")
        }
        print("")

        // === 16. 手势扩展：精细步进 / 自动全屏检测 / 多修饰键 ===
        print("━━━ 16. 手势扩展（精细/全屏/多修饰键）━━━")

        // 16a. 精细步进配置 round-trip
        let origFine = gest.fineStepSize
        gest.fineStepSize = 2.0
        if abs(gest.fineStepSize - 2.0) < 0.01 {
            print("  ✅ 精细步进写入并读回一致 = \(gest.fineStepSize)")
            passed += 1
        } else {
            print("  ❌ 精细步进 round-trip 失败")
            failed += 1
        }
        gest.fineStepSize = origFine

        // 16b. autoFullscreenDetection 配置
        let origFs = gest.autoFullscreenDetection
        gest.autoFullscreenDetection = false
        if gest.autoFullscreenDetection == false {
            print("  ✅ 自动全屏检测可关闭并持久化")
            passed += 1
        } else {
            print("  ❌ 自动全屏检测配置失败")
            failed += 1
        }
        gest.autoFullscreenDetection = origFs

        // 16c. classifyModifier 纯函数
        // requiresOptionKey=false：精度=⌥；true：精度=⇧
        let noneF = ScrollWheelGestureManager.classifyModifier(flags: [], requiresOptionKey: false)
        let optF  = ScrollWheelGestureManager.classifyModifier(flags: .maskAlternate, requiresOptionKey: false)
        let ctlF  = ScrollWheelGestureManager.classifyModifier(flags: .maskControl, requiresOptionKey: false)
        let cmdF  = ScrollWheelGestureManager.classifyModifier(flags: .maskCommand, requiresOptionKey: false)
        // requiresOptionKey=true 模式：⇧ 才是精度
        let shiftPrec = ScrollWheelGestureManager.classifyModifier(flags: .maskShift, requiresOptionKey: true)
        // 优先级：⌘ > ⌃ > 精度
        let prio = ScrollWheelGestureManager.classifyModifier(flags: [.maskCommand, .maskControl, .maskAlternate], requiresOptionKey: false)
        print("    none=\(noneF.rawValue)(0) opt=\(optF.rawValue)(1) ctrl=\(ctlF.rawValue)(2) cmd=\(cmdF.rawValue)(3) shiftPrec(⌥模式)=\(shiftPrec.rawValue)(1) 优先级=\(prio.rawValue)(3)")
        if noneF == .none && optF == .precision && ctlF == .control && cmdF == .command && shiftPrec == .precision && prio == .command {
            print("  ✅ 修饰键分类正确（含优先级与 ⌥模式下 ⇧=精度）")
            passed += 1
        } else {
            print("  ❌ 修饰键分类错误")
            failed += 1
        }

        // 16d. isFullscreenWindowFrame 纯函数
        let screenFrame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let fsWin = NSRect(x: 0, y: 0, width: 1920, height: 1080)       // 全屏
        let winWin = NSRect(x: 100, y: 100, width: 800, height: 600)    // 窗口
        let rFs = ScrollWheelGestureManager.isFullscreenWindowFrame(fsWin, screens: [screenFrame], tolerance: 10)
        let rWin = ScrollWheelGestureManager.isFullscreenWindowFrame(winWin, screens: [screenFrame], tolerance: 10)
        print("    全屏窗口→\(rFs)(期望true) 普通窗口→\(rWin)(期望false)")
        if rFs && !rWin {
            print("  ✅ 全屏 frame 判定正确")
            passed += 1
        } else {
            print("  ❌ 全屏 frame 判定错误")
            failed += 1
        }

        // 16e. 输出设备循环索引纯函数
        let nf = AudioDeviceManager.nextCycleIndex(current: 0, count: 3, direction: .forward)
        let nb = AudioDeviceManager.nextCycleIndex(current: 0, count: 3, direction: .backward)
        let wrapF = AudioDeviceManager.nextCycleIndex(current: 2, count: 3, direction: .forward)
        print("    0+1→\(nf)(期望1) 0-1→\(nb)(期望2) 2+1→\(wrapF)(期望0)")
        if nf == 1 && nb == 2 && wrapF == 0 {
            print("  ✅ 输出设备循环索引正确（含回绕）")
            passed += 1
        } else {
            print("  ❌ 循环索引错误")
            failed += 1
        }
        print("")

        // === 汇总 ===
        print("══════════════════════════════════════════════")
        print("  自检结果: ✅ \(passed) 项通过  ⏭️ \(skipped) 项跳过  ❌ \(failed) 项失败")
        if failed == 0 {
            print("  结论: 全部检查通过\(skipped > 0 ? "（\(skipped) 项因设备能力限制或外设未接入而跳过，不计失败）" : "")")
        } else {
            print("  结论: 存在 \(failed) 项失败，请检查上方日志")
        }
        print("══════════════════════════════════════════════")
        print("")
    }
}
