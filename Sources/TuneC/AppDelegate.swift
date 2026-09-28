import AppKit
import AVFoundation
import TuneCCore

// MARK: - 应用代理

@main
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// 静态单例，确保代理在整个进程生命周期内不被释放
    static let shared = AppDelegate()

    /// 内部可访问（手势引擎回调亮度调节时复用状态栏控制器的权威亮度状态）
    private(set) var statusBarController: StatusBarController?

    static func main() {
        // GUI 进程上下文自动测试：/tmp/tunec-autotest 存在时读取秒数 → 跑环回测试 → 退出。
        // 用途：`open` 启动本 App 时，音频输入权限归因于 App 自身（与终端直跑不同），
        //       这条路径可无人工干预地验证"GUI 上下文"下采集是否真的拿到信号。
        if let s = try? String(contentsOfFile: "/tmp/tunec-autotest", encoding: .utf8) {
            try? FileManager.default.removeItem(atPath: "/tmp/tunec-autotest")
            let sec = Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 12
            loopbackCLITest(seconds: sec)
            return
        }

        // CLI 自检模式
        if CommandLine.arguments.contains("--selfcheck") {
            SelfCheck.run()
            return
        }

        // CLI 环回端到端测试模式：--loopback-test [秒数，默认 25]
        if CommandLine.arguments.contains("--loopback-test") {
            let sec: Int = {
                if let i = CommandLine.arguments.firstIndex(of: "--loopback-test"),
                   i + 1 < CommandLine.arguments.count, let v = Int(CommandLine.arguments[i + 1]) {
                    return v
                }
                return 25
            }()
            loopbackCLITest(seconds: sec)
            return
        }

        // CLI 采集后端端到端测试：--tap-test [秒数，默认 20] / --bh-test [秒数，默认 20]
        //   用途：不改动 UserDefaults，临时强制指定采集后端跑一次回环，
        //        客观读取 diag 行的 cap/capE/tapPeak/mixE 判断链路是否真的通。
        if CommandLine.arguments.contains("--tap-test") || CommandLine.arguments.contains("--bh-test") {
            let flag = CommandLine.arguments.contains("--tap-test") ? "--tap-test" : "--bh-test"
            let sec: Int = {
                if let i = CommandLine.arguments.firstIndex(of: flag),
                   i + 1 < CommandLine.arguments.count, let v = Int(CommandLine.arguments[i + 1]) {
                    return v
                }
                return 20
            }()
            let backend: CaptureBackend = (flag == "--tap-test") ? .processTap : .blackHole
            captureBackendCLITest(backend: backend, seconds: sec)
            return
        }

        let app = NSApplication.shared
        app.delegate = shared
        // LSUIElement 已在 Info.plist 中设置，这里再确保一次
        app.setActivationPolicy(.accessory)
        app.run()
    }

    /// 无 GUI 环回测试：启动引擎 → 播放持续音 → 观察 diag → 恢复现场 → 退出
    private static func loopbackCLITest(seconds: Int) {
        log("=== loopback-test 开始（\(seconds)s）===")
        let mgr = AudioDeviceManager.shared

        // 选物理目标：排除 BlackHole / eqMac / 名字含 Virtual 的输出
        let physical = mgr.outputDevices().first { d in
            !d.name.localizedCaseInsensitiveContains("BlackHole")
                && !d.name.localizedCaseInsensitiveContains("eqMac")
                && d.name != "eqMac Export"
        }
        guard let target = physical else {
            log("loopback-test: 未找到物理输出设备")
            exit(2)
        }
        log("loopback-test: 目标=\(target.name)(id=\(target.id))")

        let engine = VirtualAudioEngine.shared
        guard engine.start(physicalOutput: target) else {
            log("loopback-test: 引擎启动失败")
            exit(3)
        }

        // 播放持续测试音（若存在），不存在则用 say 生成持续音源
        let tone = "/tmp/tone30.wav"
        if FileManager.default.fileExists(atPath: tone) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
            p.arguments = [tone]
            try? p.run()
            log("loopback-test: 已启动 afplay \(tone)")
        } else {
            log("loopback-test: 缺少 \(tone)，仅静音链路验证")
        }

        let half = seconds / 2
        Thread.sleep(forTimeInterval: TimeInterval(half))
        engine.setGain(0.3)
        log("loopback-test: 已切 gain=0.3（验证音量链路）")
        Thread.sleep(forTimeInterval: TimeInterval(seconds - half))
        engine.stop()
        log("=== loopback-test 结束（详见 diag 行）===")
        exit(0)
    }

    /// 采集后端端到端测试：强制指定后端跑一次回环（不改动 UserDefaults），打印客观 diag 后退出。
    ///
    /// 判读要点（对照 diag 行）：
    ///   · cap / capE > 0  → 采集侧真的拿到了音频样本
    ///   · tapPeak > 0     → Tap 回调里确实有非零样本（Tap 后端专属）
    ///   · mixE > 0        → 播放图内部产生了输出
    ///   · Tap 后端下应观察到"默认输出未被改动"
    private static func captureBackendCLITest(backend: CaptureBackend, seconds: Int) {
        let saved = CaptureBackend.current
        CaptureBackend.current = backend
        log("=== \(backend == .processTap ? "tap-test" : "bh-test") 开始（\(seconds)s，后端=\(backend.displayName)）===")
        defer { CaptureBackend.current = saved }

        let mgr = AudioDeviceManager.shared
        let physical = mgr.outputDevices().first { d in
            !d.name.localizedCaseInsensitiveContains("BlackHole")
                && !d.name.localizedCaseInsensitiveContains("eqMac")
                && d.name != "eqMac Export"
        }
        guard let target = physical else {
            log("capture-test: 未找到物理输出设备"); exit(2)
        }
        let defaultBefore = mgr.defaultOutputDevice()?.name ?? "?"
        log("capture-test: 目标=\(target.name)(id=\(target.id)) 启动前默认输出=\(defaultBefore)")
        guard backend.isAvailable else {
            log("capture-test: 后端「\(backend.displayName)」不可用，中止"); exit(4)
        }

        let engine = VirtualAudioEngine.shared
        guard engine.start(physicalOutput: target) else {
            log("capture-test: ❌ 引擎启动失败（后端=\(backend.displayName)）"); exit(3)
        }

        let tone = "/tmp/tone30.wav"
        if FileManager.default.fileExists(atPath: tone) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
            p.arguments = [tone]
            try? p.run()
            log("capture-test: 已启动外部进程 afplay \(tone)（用于验证能否采到其他进程的声音）")
        } else {
            log("capture-test: 缺少 \(tone)，仅验证静音链路")
        }

        let half = max(1, seconds / 2)
        Thread.sleep(forTimeInterval: TimeInterval(half))
        engine.setGain(0.3)
        log("capture-test: 已切 gain=0.3")
        Thread.sleep(forTimeInterval: TimeInterval(seconds - half))

        let defaultDuring = mgr.defaultOutputDevice()?.name ?? "?"
        engine.stop()
        let defaultAfter = mgr.defaultOutputDevice()?.name ?? "?"
        log("capture-test: 默认输出 启动前=\(defaultBefore) 运行中=\(defaultDuring) 停止后=\(defaultAfter)")
        log("=== \(backend == .processTap ? "tap-test" : "bh-test") 结束（详见 diag 行）===")
        exit(0)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        log("=== TuneC launching ===")
        log("macOS version: \(ProcessInfo.processInfo.operatingSystemVersionString)")

        // ★ 音频输入授权（TCC）：**仅 BlackHole 采集路径需要**。
        //   BlackHole 后端要读虚拟输入设备 → 归入 kTCCServiceMicrophone → 菜单栏出现橙色麦克风指示点。
        //   Tap 后端走 kTCCServiceAudioCapture（"屏幕与系统音频录制"），不碰麦克风，
        //   故此处**不能**再无条件申请麦克风授权，否则等于白拿一次麦克风占用。
        if CaptureBackend.current == .blackHole {
            let authStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            log("TuneC: ❖ BlackHole 采集后端 → 音频输入授权状态 = \(VirtualAudioEngine.audioInputAuthorizationLabel())")
            if authStatus == .notDetermined {
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    log("TuneC: 音频输入授权请求结果 = \(granted ? "已允许 ✅" : "被拒绝 ❌")")
                }
            } else if authStatus != .authorized {
                log("TuneC: ⚠️ 音频输入未授权，BlackHole 环回将无法采集到声音。请到「系统设置 → 隐私与安全性 → 麦克风」勾选 TuneC")
            }
        } else {
            log("TuneC: ❖ 系统音频采集后端（Process Tap）→ 无需麦克风授权，不申请")
            log("TuneC:   首次启用环回时系统会询问「屏幕与系统音频录制」权限，请点「允许」")
        }

        // 初始化状态栏
        statusBarController = StatusBarController()

        // 注册 CoreAudio 变更监听
        AudioDeviceManager.shared.registerListeners()

        // 声音黑洞恢复：上次异常退出后默认输出可能仍卡在 BlackHole 而引擎未运行
        VolumeRouter.shared.recoverFromBlackHoleIfNeeded()

        // 初始音量路由决策（同步探测 DDC 能力前先给个默认后端）
        VolumeRouter.shared.refreshRouting()

        // 注册全局快捷键
        HotKeyManager.shared.registerAll()

        // 启动时识别显示器 + 注册热插拔回调，并据此初始化亮度滑块
        RegisterDisplayHotplugCallback()
        statusBarController?.setupBrightnessControl()

        // 边缘滚轮手势：若上次为开启且已授权则恢复 CGEventTap
        ScrollWheelGestureManager.shared.restoreIfEnabled()

        // 初始刷新菜单
        statusBarController?.refreshMenu()

        // 输出当前状态
        if let output = AudioDeviceManager.shared.defaultOutputDevice() {
            log("Current output: \(output.name) (volume=\(String(format: "%.0f%%", VolumeRouter.shared.outputVolume() * 100)), muted=\(VolumeRouter.shared.isOutputMuted()), backend=\(VolumeRouter.shared.backend))")
        }
        if let input = AudioDeviceManager.shared.defaultInputDevice() {
            log("Current input: \(input.name)")
        }
        log("Output devices: \(AudioDeviceManager.shared.outputDevices().map { $0.name })")
        log("Input devices: \(AudioDeviceManager.shared.inputDevices().map { $0.name })")
        log("=== TuneC ready ===")
    }

    func applicationWillTerminate(_ notification: Notification) {
        log("=== TuneC terminating ===")
        // 退出前务必停掉环回：否则默认输出会残留指向 BlackHole，系统声音被灌进黑洞无人搬运
        if VolumeRouter.shared.virtualAudioActive {
            VolumeRouter.shared.disableVirtualAudio()
            log("TuneC: 退出时已停用虚拟音频环回并恢复默认输出")
        }
        HotKeyManager.shared.unregisterAll()
        ScrollWheelGestureManager.shared.stop()
    }
}
