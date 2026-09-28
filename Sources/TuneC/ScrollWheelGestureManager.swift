import AppKit
import CoreGraphics
import ApplicationServices
import TuneCCore

// MARK: - 全局边缘滚轮手势引擎
//
// 设计参考 WGestures：
//   - CGEventTap(.cgSessionEventTap) 拦截全系统滚轮事件
//   - 顶部热区 → 显示相关（亮度 / ⌃对比度）
//   - 底部热区 → 音频相关（音量 / ⌃切设备 / ⌘静音）
//   - 中间区域滚轮原样透传
//
// 修饰键精度模式：
//   - requiresOptionKey=false（默认纯滚轮）：⌥ = 精细
//   - requiresOptionKey=true（⌥ 是触发前提）：⇧ = 精细
// 全屏自动检测开启时，全屏前台应用内必须按住精度修饰键才响应。

// MARK: - 修饰键功能分类（纯函数，可自检）

enum GestureModifier: Int {
    case none = 0      // 无修饰：粗调
    case precision = 1 // 精度修饰（⌥ 或 ⇧）：精细调节
    case control = 2   // ⌃：对比度 / 切输出设备
    case command = 3   // ⌘：预留 / 静音
}

final class ScrollWheelGestureManager {

    static let shared = ScrollWheelGestureManager()

    // MARK: - 持久化键

    private enum Keys {
        static let enabled = "gesture.isEnabled"
        static let zoneHeight = "gesture.hotZoneHeight"
        static let stepSize = "gesture.stepSize"
        static let requireOption = "gesture.requiresOptionKey"
        static let fineStep = "gesture.fineStepSize"
        static let autoFullscreen = "gesture.autoFullscreenDetection"
    }

    private let defaults = UserDefaults.standard

    // MARK: - 配置（持久化）

    var isEnabled: Bool {
        get { defaults.bool(forKey: Keys.enabled) }
        set {
            defaults.set(newValue, forKey: Keys.enabled)
            if newValue { _ = start() } else { stop() }
        }
    }

    var hotZoneHeight: CGFloat {
        get { let v = defaults.double(forKey: Keys.zoneHeight); return v == 0 ? 20 : CGFloat(v) }
        set { defaults.set(Double(min(50, max(10, newValue))), forKey: Keys.zoneHeight) }
    }

    /// 粗调步进（%，3/5/10，默认 5）
    var stepSize: Int {
        get { let v = defaults.integer(forKey: Keys.stepSize); return v == 0 ? 5 : v }
        set { defaults.set(newValue, forKey: Keys.stepSize) }
    }

    var requiresOptionKey: Bool {
        get { defaults.bool(forKey: Keys.requireOption) }
        set { defaults.set(newValue, forKey: Keys.requireOption) }
    }

    /// 精细步进（%，0.5/1.0/2.0，默认 1.0）
    var fineStepSize: Float {
        get { let v = defaults.double(forKey: Keys.fineStep); return v == 0 ? 1.0 : Float(v) }
        set { defaults.set(Double(newValue), forKey: Keys.fineStep) }
    }

    /// 自动全屏检测（默认开）
    var autoFullscreenDetection: Bool {
        get {
            let v = defaults.object(forKey: Keys.autoFullscreen) as? Bool
            return v ?? true   // 默认 true
        }
        set { defaults.set(newValue, forKey: Keys.autoFullscreen) }
    }

    // MARK: - 内部状态

    private var tap: CFMachPort?
    private var runloopSource: CFRunLoopSource?
    private let workQueue = DispatchQueue(label: "com.tunec.gesture", qos: .userInitiated)
    private var lastTriggerTime: TimeInterval = 0
    /// 亮度/对比度当前值缓存（-1 = 未知，首次触发读回）
    private var brightnessCache: Float = -1
    private var contrastCache: Float = -1

    private let throttleInterval: TimeInterval = 0.05

    /// 当前前台应用是否处于全屏
    private(set) var isFullscreenActive: Bool = false {
        didSet {
            if oldValue != isFullscreenActive {
                log("Gesture: 全屏状态 → \(isFullscreenActive ? "全屏（需精度键才响应）" : "窗口（正常）")")
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .tunecGestureModeChanged, object: nil)
                }
            }
        }
    }
    private var fullscreenTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []

    private init() {}

    // MARK: - 权限

    var isTrusted: Bool { AXIsProcessTrusted() }

    func requestAccessibilityPermission() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
        log("Gesture: 请求辅助功能权限")
    }

    // MARK: - 启动 / 停止

    @discardableResult
    func start() -> Bool {
        guard isEnabled else { log("Gesture: 开关关闭，不启动 tap"); return false }
        guard AXIsProcessTrusted() else {
            log("Gesture: 未授权辅助功能，start() 失败"); return false
        }
        guard tap == nil else { return true }

        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        guard let t = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                ScrollWheelGestureManager.shared.handle(proxy: proxy, type: type, event: event)
            }, userInfo: nil
        ) else {
            log("Gesture: CGEvent.tapCreate 失败"); return false
        }
        tap = t
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        runloopSource = src
        CGEvent.tapEnable(tap: t, enable: true)
        startFullscreenMonitoring()
        log("Gesture: CGEventTap 已启动（zone=\(hotZoneHeight)px coarse=\(stepSize)% fine=\(fineStepSize)% ⌥=\(requiresOptionKey) 全屏检测=\(autoFullscreenDetection)）")
        return true
    }

    func stop() {
        if let t = tap {
            CGEvent.tapEnable(tap: t, enable: false)
            CFMachPortInvalidate(t)
        }
        tap = nil
        if let s = runloopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes)
        }
        runloopSource = nil
        stopFullscreenMonitoring()
        log("Gesture: CGEventTap 已停止")
    }

    func restoreIfEnabled() {
        log("Gesture: 启动恢复 — isEnabled=\(isEnabled) isTrusted=\(AXIsProcessTrusted())")
        if isEnabled { _ = start() }
    }

    /// tap 是否正在运行
    var isRunning: Bool { tap != nil }

    /// 授权后自动补启动：用户意图开启但当时未授权 → 授权生效后调用此方法补启动。
    /// 返回是否本次真的启动了 tap。
    @discardableResult
    func recoverIfAuthorized() -> Bool {
        guard isEnabled, !isRunning else { return false }
        guard AXIsProcessTrusted() else { return false }
        log("Gesture: 检测到授权已生效，自动启动 tap（pendingOn 恢复）")
        let ok = start()
        log("Gesture: 自动启动结果 = \(ok)")
        return ok
    }

    // MARK: - 修饰键分类（纯函数）

    /// 把事件 flags 分类为功能修饰键。优先级：⌘ > ⌃ > 精度键 > 无。
    /// requiresOptionKey=true 时 ⌥ 是触发前提，精度键为 ⇧；否则精度键为 ⌥。
    static func classifyModifier(flags: CGEventFlags, requiresOptionKey: Bool) -> GestureModifier {
        if flags.contains(.maskCommand) { return .command }
        if flags.contains(.maskControl) { return .control }
        let precision: CGEventFlags = requiresOptionKey ? .maskShift : .maskAlternate
        if flags.contains(precision) { return .precision }
        return .none
    }

    // MARK: - 事件处理

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }
        guard isEnabled else { return Unmanaged.passUnretained(event) }

        // 全屏自动检测：全屏中必须按住精度修饰键才响应，否则透传
        if autoFullscreenDetection && isFullscreenActive {
            let prec: CGEventFlags = requiresOptionKey ? .maskShift : .maskAlternate
            guard event.flags.contains(prec) else {
                return Unmanaged.passUnretained(event)
            }
        } else if requiresOptionKey {
            // 常规修饰键模式：必须按住 ⌥
            guard event.flags.contains(.maskAlternate) else {
                return Unmanaged.passUnretained(event)
            }
        }

        let location = event.location
        guard let zone = hotZone(containing: location) else {
            return Unmanaged.passUnretained(event)
        }

        let delta = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        guard delta != 0 else { return Unmanaged.passUnretained(event) }
        let direction: Int = delta > 0 ? 1 : -1

        let modifier = Self.classifyModifier(flags: event.flags, requiresOptionKey: requiresOptionKey)
        // ⌘ 在顶部热区为预留（透传）；底部热区为静音
        if modifier == .command && zone == .top {
            return Unmanaged.passUnretained(event)
        }

        let now = Date().timeIntervalSinceReferenceDate
        if now - lastTriggerTime >= throttleInterval {
            lastTriggerTime = now
            let zoneCopy = zone
            let fine = (modifier == .precision)
            let coarse = Float(stepSize)
            let step = fine ? fineStepSize : coarse
            workQueue.async {
                self.apply(zone: zoneCopy, direction: direction, modifier: modifier, step: step, fine: fine)
            }
        }
        return nil  // consume
    }

    private enum HotZone { case top, bottom }

    private func hotZone(containing point: CGPoint) -> HotZone? {
        let h = hotZoneHeight
        for screen in NSScreen.screens {
            let f = screen.frame
            guard f.contains(point) else { continue }
            if point.y >= f.maxY - h { return .top }
            if point.y <= f.minY + h { return .bottom }
            return nil
        }
        return nil
    }

    static func classifyHotZone(point: NSPoint, screenFrame: NSRect, zoneHeight: CGFloat) -> Int {
        guard screenFrame.contains(point) else { return 0 }
        if point.y >= screenFrame.maxY - zoneHeight { return 1 }
        if point.y <= screenFrame.minY + zoneHeight { return 2 }
        return 0
    }

    // MARK: - 实际动作（后台队列）

    private func apply(zone: HotZone, direction: Int, modifier: GestureModifier, step: Float, fine: Bool) {
        switch zone {
        case .top:
            switch modifier {
            case .control:  adjustContrast(direction: direction, step: step, fine: fine)
            default:        adjustBrightness(direction: direction, step: step, fine: fine)
            }
        case .bottom:
            switch modifier {
            case .control:  cycleOutput(direction: direction)
            case .command:  toggleMute()
            default:        adjustVolume(direction: direction, step: step, fine: fine)
            }
        }
    }

    private var displayUUID: String? {
        DisplayDetector.shared.primaryExternalDisplay()?.uuid
    }

    /// 顶部：亮度 VCP 0x10
    /// 委托给 StatusBarController 的权威 brightnessValue（与滑块/快捷键同一路径），
    /// 避免手势自身读 VCP 时被「部分显示器读回不实时」污染缓存。在主线程执行。
    private func adjustBrightness(direction: Int, step: Float, fine: Bool) {
        let delta = Float(direction) * step
        DispatchQueue.main.async {
            if let sb = AppDelegate.shared.statusBarController {
                sb.gestureAdjustBrightness(deltaPercent: delta, fine: fine)
            } else {
                log("Gesture brightness: 状态栏控制器未就绪")
            }
        }
    }

    /// 顶部 + ⌃：对比度 VCP 0x12
    private func adjustContrast(direction: Int, step: Float, fine: Bool) {
        guard let uuid = displayUUID else { return }
        if contrastCache < 0 {
            contrastCache = DDCManager.shared.readVCP(uuid: uuid, code: DDCVCP.contrast)
                .map { Float($0.cur) } ?? 50
        }
        let next = max(0, min(100, contrastCache + Float(direction) * step))
        guard abs(next - contrastCache) > 0.01 else { return }
        let ok = DDCManager.shared.writeVCP(uuid: uuid, code: DDCVCP.contrast, value: UInt16(next.rounded()))
        contrastCache = next
        log("Gesture: 对比度 → \(next) (写\(ok ? "OK" : "FAIL"))")
        DispatchQueue.main.async {
            ScrollHUD.shared.show(type: .contrast, value: next, fine: fine)
        }
    }

    /// 底部：音量
    private func adjustVolume(direction: Int, step: Float, fine: Bool) {
        let router = VolumeRouter.shared
        let cur = router.outputVolume()
        let delta = step / 100.0
        let next = max(0.0, min(1.0, cur + Float32(direction) * delta))
        guard abs(next - cur) > 0.001 else { return }
        router.setOutputVolume(next)
        let pct = next * 100
        log("Gesture: 音量 → \(pct)%")
        DispatchQueue.main.async {
            ScrollHUD.shared.show(type: .volume, value: pct, fine: fine)
        }
    }

    /// 底部 + ⌃：切换输出设备（上滚=下一个，下滚=上一个）
    private func cycleOutput(direction: Int) {
        let d = direction > 0 ? AudioDeviceManager.CycleDirection.forward : .backward
        if let name = AudioDeviceManager.shared.cycleOutputDevice(direction: d) {
            log("Gesture: 切换输出 → \(name)")
            DispatchQueue.main.async {
                ScrollHUD.shared.show(type: .device, text: "输出：\(name)")
            }
        } else {
            log("Gesture: 切输出失败（仅一台设备或虚拟音频环回中）")
        }
    }

    /// 底部 + ⌘：静音切换
    private func toggleMute() {
        VolumeRouter.shared.toggleOutputMute()
        let muted = VolumeRouter.shared.isOutputMuted()
        log("Gesture: 静音 → \(muted ? "开" : "关")")
        DispatchQueue.main.async {
            ScrollHUD.shared.show(type: .mute, text: muted ? "已静音" : "已取消静音")
        }
    }

    // MARK: - 全屏检测

    private func startFullscreenMonitoring() {
        stopFullscreenMonitoring()
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateFullscreenState()
        }
        fullscreenTimer = timer
        let nc = NotificationCenter.default
        let frontNote = nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.updateFullscreenState()
        }
        let screenNote = nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.updateFullscreenState()
        }
        workspaceObservers = [frontNote, screenNote]
        updateFullscreenState()
    }

    private func stopFullscreenMonitoring() {
        fullscreenTimer?.invalidate()
        fullscreenTimer = nil
        for o in workspaceObservers { NotificationCenter.default.removeObserver(o) }
        workspaceObservers.removeAll()
    }

    /// 实时全屏检测：前台窗口 frame 是否近似某屏幕全屏
    private func updateFullscreenState() {
        guard autoFullscreenDetection else {
            isFullscreenActive = false
            return
        }
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            isFullscreenActive = false; return
        }
        let ownerName = frontApp.localizedName ?? ""
        let screenFrames = NSScreen.screens.map { $0.frame }

        var found = false
        if let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] {
            for w in list {
                guard let layer = w[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
                guard let owner = w[kCGWindowOwnerName as String] as? String, owner == ownerName else { continue }
                guard let bounds = w[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
                let frame = NSRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0,
                                   width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
                if Self.isFullscreenWindowFrame(frame, screens: screenFrames, tolerance: 10) {
                    found = true; break
                }
            }
        }
        // 注：CGDisplayIsCaptured 在当前 SDK 已不可用，全屏判定以前台窗口 frame 比对屏幕 frame 为准
        isFullscreenActive = found
    }

    /// 纯函数：窗口 frame 是否近似某个屏幕 frame（误差 tolerance px）
    static func isFullscreenWindowFrame(_ frame: NSRect, screens: [NSRect], tolerance: CGFloat = 10) -> Bool {
        for s in screens {
            if abs(frame.minX - s.minX) <= tolerance &&
               abs(frame.minY - s.minY) <= tolerance &&
               abs(frame.width - s.width) <= tolerance &&
               abs(frame.height - s.height) <= tolerance {
                return true
            }
        }
        return false
    }
}

/// 手势模式变化通知（状态栏顶部刷新用）
extension Notification.Name {
    static let tunecGestureModeChanged = Notification.Name("TuneCGestureModeChanged")
}
