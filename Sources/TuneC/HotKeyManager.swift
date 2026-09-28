import Foundation
import Carbon
import TuneCCore

// MARK: - 热键标识

enum HotKeyAction: UInt32, CaseIterable {
    case switchOutput = 1
    case switchInput  = 2
    case volumeUp     = 3
    case volumeDown   = 4
    case mute         = 5
    case brightnessUp   = 6
    case brightnessDown = 7

    var displayName: String {
        switch self {
        case .switchOutput: return "切换输出设备"
        case .switchInput:  return "切换输入设备"
        case .volumeUp:     return "音量增加"
        case .volumeDown:   return "音量减少"
        case .mute:         return "静音切换"
        case .brightnessUp:   return "亮度增加"
        case .brightnessDown: return "亮度减少"
        }
    }
}

/// 单个热键配置
struct HotKeyConfig {
    let action: HotKeyAction
    let keyCode: UInt32       // 虚拟键码
    let modifiers: UInt32     // 修饰键（Carbon 常量）

    /// 修饰键显示字符串
    var modifierDisplay: String {
        var parts: [String] = []
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        return parts.joined()
    }
}

// MARK: - 热键管理器

final class HotKeyManager {

    static let shared = HotKeyManager()

    /// 热键触发回调
    var onHotKey: ((HotKeyAction) -> Void)?

    /// 默认热键配置（均含 ⌃，满足 macOS 15+ 要求）
    static let defaultConfigs: [HotKeyConfig] = [
        HotKeyConfig(action: .switchOutput, keyCode: 0x1F, modifiers: UInt32(controlKey | optionKey)),           // ⌃⌥ O
        HotKeyConfig(action: .switchInput,  keyCode: 0x22, modifiers: UInt32(controlKey | optionKey)),           // ⌃⌥ I
        HotKeyConfig(action: .volumeUp,     keyCode: 0x7E, modifiers: UInt32(controlKey | optionKey)),           // ⌃⌥ ↑
        HotKeyConfig(action: .volumeDown,   keyCode: 0x7D, modifiers: UInt32(controlKey | optionKey)),           // ⌃⌥ ↓
        HotKeyConfig(action: .mute,         keyCode: 0x2D, modifiers: UInt32(controlKey | optionKey)),           // ⌃⌥ M
        HotKeyConfig(action: .brightnessUp,   keyCode: 0x7C, modifiers: UInt32(controlKey | optionKey)),           // ⌃⌥ →
        HotKeyConfig(action: .brightnessDown, keyCode: 0x7B, modifiers: UInt32(controlKey | optionKey)),           // ⌃⌥ ←
    ]

    private var hotKeyRefs: [HotKeyAction: EventHotKeyRef] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private var registered = false

    private init() {}

    // MARK: - 注册/注销

    /// 注册所有全局热键
    func registerAll() {
        guard !registered else {
            log("HotKeys already registered")
            return
        }

        // 安装事件处理器
        installEventHandler()

        // 注册每个热键
        for config in HotKeyManager.defaultConfigs {
            register(config: config)
        }

        registered = true
        log("All hotkeys registered (\(hotKeyRefs.count) active)")
    }

    /// 注销所有热键
    func unregisterAll() {
        for (_, ref) in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()

        if let handlerRef = eventHandlerRef {
            RemoveEventHandler(handlerRef)
            eventHandlerRef = nil
        }

        registered = false
        log("All hotkeys unregistered")
    }

    // MARK: - 单个热键注册

    private func register(config: HotKeyConfig) {
        let hotKeyID = EventHotKeyID(signature: fourCharCode("ATOL"), id: config.action.rawValue)
        var ref: EventHotKeyRef?

        let status = RegisterEventHotKey(
            config.keyCode,
            config.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        if status == noErr, let ref = ref {
            hotKeyRefs[config.action] = ref
            log("HotKey registered: \(config.action.displayName) [\(config.modifierDisplay)+\(keyDisplay(config.keyCode))] id=\(config.action.rawValue)")
        } else {
            log("HotKey FAILED: \(config.action.displayName) status=\(status) (0x\(String(status, radix: 16)))")
        }
    }

    // MARK: - 事件处理器

    private func installEventHandler() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let userData = Unmanaged.passUnretained(self).toOpaque()

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventHandler,
            1,
            &eventSpec,
            userData,
            &eventHandlerRef
        )

        if status == noErr {
            log("Event handler installed for hotkey press events")
        } else {
            log("Failed to install event handler: \(status)")
        }
    }

    // MARK: - 配置查询

    /// 获取所有热键配置（用于 UI 显示）
    func allConfigs() -> [HotKeyConfig] {
        HotKeyManager.defaultConfigs
    }

    /// 检查是否已注册
    var isRegistered: Bool { registered }
}

// MARK: - Carbon 事件回调（C 函数指针，不能捕获上下文）

private let hotKeyEventHandler: EventHandlerUPP = { (_, event, userData) -> OSStatus in
    guard let userData = userData else { return noErr }
    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()

    var hotKeyID = EventHotKeyID()
    var size = MemoryLayout<EventHotKeyID>.size
    let status = GetEventParameter(
        event,
        UInt32(kEventParamDirectObject),
        UInt32(typeEventHotKeyID),
        nil,
        size,
        &size,
        &hotKeyID
    )

    guard status == noErr else {
        log("GetEventParameter failed: \(status)")
        return noErr
    }

    guard let action = HotKeyAction(rawValue: hotKeyID.id) else {
        log("Unknown hotkey ID: \(hotKeyID.id)")
        return noErr
    }

    log("HotKey pressed: \(action.displayName) (id=\(action.rawValue))")
    DispatchQueue.main.async {
        manager.onHotKey?(action)
    }

    return noErr
}

// MARK: - 工具函数

/// 构造 FourCharCode
private func fourCharCode(_ string: String) -> FourCharCode {
    var result: FourCharCode = 0
    for char in string.utf8 {
        result = (result << 8) | FourCharCode(char)
    }
    return result
}

/// 虚拟键码 → 短名（日志与菜单共用，模块内可见）。
/// 覆盖 `HotKeyManager.defaultConfigs` 中的全部 7 个热键：
/// 0x1F=O / 0x22=I / 0x2D=M / 0x7E=↑ / 0x7D=↓ / 0x7B=← / 0x7C=→
func keyDisplay(_ code: UInt32) -> String {
    switch Int(code) {
    case 0x1F: return "O"
    case 0x22: return "I"
    case 0x2D: return "M"
    case 0x7E: return "↑"
    case 0x7D: return "↓"
    case 0x7B: return "←"
    case 0x7C: return "→"
    default: return "Key(\(code))"
    }
}
