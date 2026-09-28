import AppKit
import CoreAudio
import TuneCCore

// MARK: - 状态栏控制器

/// 管理状态栏图标、菜单及用户交互
final class StatusBarController: NSObject, NSMenuDelegate {

    private let statusItem: NSStatusItem
    private let audioManager = AudioDeviceManager.shared
    private let hotKeyManager = HotKeyManager.shared
    private let router = VolumeRouter.shared

    // 菜单引用（用于动态刷新）
    private var volumeSliderItem: NSMenuItem?
    private var volumeSlider: NSSlider?
    private var muteMenuItem: NSMenuItem?
    private var backendMenuItem: NSMenuItem?
    private var virtualAudioToggleItem: NSMenuItem?
    private var virtualAudioHintItem: NSMenuItem?
    private var installBlackHoleItem: NSMenuItem?
    /// 「采集方式」子菜单（Tap / BlackHole 二选一，持久化）
    private var captureBackendItem: NSMenuItem?

    // === 亮度控制 ===
    /// 顶部识别状态行（型号 + 能力标签）
    private var statusLineItem: NSMenuItem?
    /// 亮度分组（标题 + 滑块，仅检测到外接显示器时显示）
    private var brightnessHeaderItem: NSMenuItem?
    private var brightnessSliderItem: NSMenuItem?
    private var brightnessSlider: NSSlider?
    private var brightnessSeparatorItem: NSMenuItem?
    /// 当前控制的外接显示器 uuid（DDC 操作按 uuid 寻址）
    private var brightnessUUID: String?
    /// 内存镜像的当前亮度（0-100），热键步进用
    private var brightnessValue: Int = 50
    /// DDC 写操作后台队列（I2C 阻塞，不能卡主线程）
    private let ddcWorkQueue = DispatchQueue(label: "com.tunec.brightness", qos: .userInitiated)
    /// 滑块拖时节流：未决写任务与最新待写值
    private var brightnessWriteWork: DispatchWorkItem?
    private var pendingBrightness: Int?

    // === 边缘滚轮手势菜单引用 ===
    private var gestureToggleItem: NSMenuItem?
    private var gesturePermissionItem: NSMenuItem?
    private var gestureZoneItem: NSMenuItem?
    private var gestureStepItem: NSMenuItem?
    private var gestureRequireOptionItem: NSMenuItem?
    private var gestureAutoFullscreenItem: NSMenuItem?
    private var gestureFineStepItem: NSMenuItem?

    override init() {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureStatusItem()
        setupAudioCallbacks()
        setupHotKeyCallbacks()
        setupDisplayChangeObserver()
    }

    /// 监听显示器热插拔，重新识别并刷新亮度分组/状态行
    private func setupDisplayChangeObserver() {
        NotificationCenter.default.addObserver(
            forName: .tunecDisplaysChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.setupBrightnessControl()
            log("Display changed: UI refreshed")
        }
        // 全屏状态变化时刷新顶部手势模式显示
        NotificationCenter.default.addObserver(
            forName: .tunecGestureModeChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshGestureMenu()
        }
        // 应用从系统设置授权回来激活时，自动补启动手势
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            if ScrollWheelGestureManager.shared.recoverIfAuthorized() {
                log("应用激活检测到授权生效，手势已自动启动")
            }
            self?.refreshMenu()
        }
    }

    // MARK: - 状态栏配置

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        // 使用 SF Symbol 图标
        if let image = NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: "TuneC") {
            image.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeft
        }
        button.toolTip = "TuneC - 音频设备切换与音量控制"

        // 构建菜单
        let menu = buildMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    // MARK: - 菜单构建

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // === 顶部：已识别显示器型号与能力标签 ===
        let statusItem = NSMenuItem(title: "识别中…", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        self.statusLineItem = statusItem

        menu.addItem(NSMenuItem.separator())

        // === 输出设备 ===
        menu.addItem(withTitle: "输出设备", action: nil, keyEquivalent: "")
        menu.items.last?.isEnabled = false

        menu.addItem(NSMenuItem.separator())

        // === 输入设备 ===
        menu.addItem(withTitle: "输入设备", action: nil, keyEquivalent: "")
        menu.items.last?.isEnabled = false

        menu.addItem(NSMenuItem.separator())

        // === 音量控制 ===
        menu.addItem(withTitle: "音量", action: nil, keyEquivalent: "")
        menu.items.last?.isEnabled = false

        // 后端能力标签已并入"虚拟音频"组动态小字，此处保留隐藏占位
        let backendItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        backendItem.isEnabled = false
        backendItem.isHidden = true
        menu.addItem(backendItem)
        self.backendMenuItem = backendItem

        // 音量滑条（自定义 view，高度留足圆形旋钮，避免上边缘被裁）
        let sliderContainer = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 36))
        let slider = NSSlider(frame: NSRect(x: 16, y: 7, width: 188, height: 22))
        slider.minValue = 0
        slider.maxValue = 100
        slider.floatValue = Float(router.outputVolume() * 100)
        slider.target = self
        slider.action = #selector(volumeSliderChanged(_:))
        sliderContainer.addSubview(slider)
        self.volumeSlider = slider

        let sliderItem = NSMenuItem()
        sliderItem.view = sliderContainer
        menu.addItem(sliderItem)
        self.volumeSliderItem = sliderItem

        // 静音（打勾 ✓）
        let muteItem = NSMenuItem(title: "静音", action: #selector(toggleMute(_:)), keyEquivalent: "")
        muteItem.target = self
        menu.addItem(muteItem)
        self.muteMenuItem = muteItem

        menu.addItem(NSMenuItem.separator())

        // === 显示器亮度（仅外接显示器时显示）===
        let brightHeader = NSMenuItem(title: "亮度", action: nil, keyEquivalent: "")
        brightHeader.isEnabled = false
        brightHeader.isHidden = true
        menu.addItem(brightHeader)
        self.brightnessHeaderItem = brightHeader

        let brightContainer = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 36))
        let brightSlider = NSSlider(frame: NSRect(x: 16, y: 7, width: 188, height: 22))
        brightSlider.minValue = 0
        brightSlider.maxValue = 100
        brightSlider.integerValue = 50
        brightSlider.target = self
        brightSlider.action = #selector(brightnessSliderChanged(_:))
        brightContainer.addSubview(brightSlider)
        self.brightnessSlider = brightSlider

        let brightSliderItem = NSMenuItem()
        brightSliderItem.view = brightContainer
        brightSliderItem.isHidden = true
        menu.addItem(brightSliderItem)
        self.brightnessSliderItem = brightSliderItem

        let brightSep = NSMenuItem.separator()
        brightSep.isHidden = true
        menu.addItem(brightSep)
        self.brightnessSeparatorItem = brightSep

        // === 虚拟音频（系统音频采集 / BlackHole 环回）===
        menu.addItem(withTitle: "虚拟音频", action: nil, keyEquivalent: "")
        menu.items.last?.isEnabled = false

        let toggleItem = NSMenuItem(title: "虚拟音频环回", action: #selector(toggleVirtualAudio(_:)), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)
        self.virtualAudioToggleItem = toggleItem

        let hintItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        hintItem.isEnabled = false
        hintItem.isHidden = true
        menu.addItem(hintItem)
        self.virtualAudioHintItem = hintItem

        // 采集方式子菜单：系统音频采集（Core Audio Process Tap，无需驱动、不占用麦克风）
        //                / BlackHole 虚拟设备（兼容回退）
        let backendSubItem = NSMenuItem(title: "采集方式", action: nil, keyEquivalent: "")
        let backendSubMenu = NSMenu()
        for b in CaptureBackend.allCases {
            let it = NSMenuItem(title: b.displayName,
                                action: #selector(selectCaptureBackend(_:)),
                                keyEquivalent: "")
            it.target = self
            it.representedObject = b.rawValue
            backendSubMenu.addItem(it)
        }
        backendSubMenu.addItem(NSMenuItem.separator())
        let backendNote = NSMenuItem(title: "环回运行中不可切换，请先停止环回", action: nil, keyEquivalent: "")
        backendNote.isEnabled = false
        backendSubMenu.addItem(backendNote)
        backendSubItem.submenu = backendSubMenu
        menu.addItem(backendSubItem)
        self.captureBackendItem = backendSubItem

        let installItem = NSMenuItem(
            title: "安装 BlackHole…",
            action: #selector(showInstallBlackHole(_:)),
            keyEquivalent: ""
        )
        installItem.target = self
        menu.addItem(installItem)
        self.installBlackHoleItem = installItem

        menu.addItem(NSMenuItem.separator())

        // === 手势 ===
        menu.addItem(withTitle: "手势", action: nil, keyEquivalent: "")
        menu.items.last?.isEnabled = false

        let gestToggle = NSMenuItem(title: "边缘滚轮手势", action: #selector(toggleGesture(_:)), keyEquivalent: "")
        gestToggle.target = self
        menu.addItem(gestToggle)
        self.gestureToggleItem = gestToggle

        // 设置子菜单：按逻辑分类收纳（辅助功能 → 触发方式 → 灵敏度）
        let settingsItem = NSMenuItem(title: "设置", action: nil, keyEquivalent: "")
        let settingsMenu = NSMenu()

        // ── ① 辅助功能授权（始终显示状态，未授权时点击引导）──
        let gestPermItem = NSMenuItem(
            title: "⚠️ 需要辅助功能权限",
            action: #selector(requestGestureAccess(_:)),
            keyEquivalent: ""
        )
        gestPermItem.target = self
        settingsMenu.addItem(gestPermItem)
        self.gesturePermissionItem = gestPermItem

        settingsMenu.addItem(NSMenuItem.separator())

        // ── ② 触发方式（勾选项）──
        let optItem = NSMenuItem(title: "按住 ⌥ 才响应", action: #selector(toggleGestureRequireOption(_:)), keyEquivalent: "")
        optItem.target = self
        settingsMenu.addItem(optItem)
        self.gestureRequireOptionItem = optItem

        let fsItem = NSMenuItem(title: "自动全屏检测", action: #selector(toggleGestureAutoFullscreen(_:)), keyEquivalent: "")
        fsItem.target = self
        settingsMenu.addItem(fsItem)
        self.gestureAutoFullscreenItem = fsItem

        settingsMenu.addItem(NSMenuItem.separator())

        // ── ③ 灵敏度参数（子菜单）──
        let zoneItem = NSMenuItem(title: "热区高度", action: nil, keyEquivalent: "")
        let zoneMenu = NSMenu()
        for h in [10, 20, 30, 40, 50] {
            let item = NSMenuItem(title: "\(h)px", action: #selector(setGestureZoneHeight(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = h
            zoneMenu.addItem(item)
        }
        zoneItem.submenu = zoneMenu
        settingsMenu.addItem(zoneItem)
        self.gestureZoneItem = zoneItem

        let stepItem = NSMenuItem(title: "调节步进", action: nil, keyEquivalent: "")
        let stepMenu = NSMenu()
        for s in [3, 5, 10] {
            let item = NSMenuItem(title: "\(s)%", action: #selector(setGestureStep(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = s
            stepMenu.addItem(item)
        }
        stepItem.submenu = stepMenu
        settingsMenu.addItem(stepItem)
        self.gestureStepItem = stepItem

        let fineItem = NSMenuItem(title: "精细步进", action: nil, keyEquivalent: "")
        let fineMenu = NSMenu()
        for v in [0.5, 1.0, 2.0] {
            let item = NSMenuItem(title: String(format: "%.1f%%", v), action: #selector(setGestureFineStep(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = v
            fineMenu.addItem(item)
        }
        fineItem.submenu = fineMenu
        settingsMenu.addItem(fineItem)
        self.gestureFineStepItem = fineItem

        settingsItem.submenu = settingsMenu
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // === 快捷键信息（子菜单收起，避免主菜单臃肿）===
        // 注意：标题项必须保持可用，否则 macOS 禁用态 item 悬停不会展开子菜单
        let hotkeyTitle = NSMenuItem(title: "快捷键", action: nil, keyEquivalent: "")
        let hotkeySubmenu = NSMenu()
        for config in hotKeyManager.allConfigs() {
            let item = NSMenuItem(
                title: "\(config.modifierDisplay) \(keyDisplay(config.keyCode))  —  \(config.action.displayName)",
                action: nil,
                keyEquivalent: ""
            )
            item.isEnabled = false
            hotkeySubmenu.addItem(item)
        }
        hotkeyTitle.submenu = hotkeySubmenu
        menu.addItem(hotkeyTitle)

        menu.addItem(NSMenuItem.separator())

        // === 关于 / 退出 ===
        let aboutItem = NSMenuItem(title: "关于 TuneC", action: #selector(showAbout(_:)), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "退出 TuneC", action: #selector(quit(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - 菜单刷新

    /// 刷新设备列表和音量显示
    func refreshMenu() {
        refreshOutputDevices()
        refreshInputDevices()
        refreshVolume()
        refreshGestureMenu()
    }

    // MARK: - NSMenuDelegate（每次弹出菜单时刷新勾选/权限态）
    func menuWillOpen(_ menu: NSMenu) {
        // 用户从系统设置授权回来后，打开菜单时检测并自动补启动手势
        if ScrollWheelGestureManager.shared.recoverIfAuthorized() {
            log("菜单打开检测到授权生效，手势已自动启动")
        }
        // 每次打开菜单整体刷新：设备勾选、虚拟音频状态、后端标签、手势开关文字全部实时
        refreshMenu()
    }

    private func refreshOutputDevices() {
        guard let menu = statusItem.menu,
              let index = menu.items.firstIndex(where: { $0.title == "输出设备" }) else { return }

        // 移除旧的设备项（标题之后、分隔线之前）
        let removeIndex = index + 1
        while removeIndex < menu.items.count, !menu.items[removeIndex].isSeparatorItem {
            menu.removeItem(at: removeIndex)
        }

        // 插入新的设备项：只显示真实物理设备，过滤掉 BlackHole 等虚拟设备
        let allOut = audioManager.outputDevices()
        let devices = allOut.filter { !isVirtualNoSoundDevice($0.name) }
        let current = audioManager.defaultOutputDevice()

        // 环回运行中：默认输出是 BlackHole（已被过滤），用户视角的"当前输出"=环回物理目标
        let loopbackTargetID = router.virtualAudioPhysicalDevice?.id

        for (i, device) in devices.enumerated() {
            var title = device.name
            // 选中态：默认输出匹配；或环回运行中该设备=环回物理目标
            let isCurrent = (device.id == current?.id)
                || (router.virtualAudioActive && device.id == loopbackTargetID)
            // 仅 BlackHole 后端会把默认输出切走；此时若默认输出已回到物理设备 → 标注已失效。
            // （Tap 后端本就不切默认输出，不适用该标注）
            if isCurrent && router.virtualAudioActive
                && router.captureBackend == .blackHole && !isDefaultOutputBlackHole {
                title += "（虚拟音频已不生效）"
            }
            let item = NSMenuItem(
                title: title,
                action: #selector(selectOutputDevice(_:)),
                keyEquivalent: i < 9 ? "\(i + 1)" : ""
            )
            item.target = self
            item.representedObject = device
            item.state = isCurrent ? .on : .off
            menu.insertItem(item, at: removeIndex + i)
        }

        if devices.isEmpty {
            let item = NSMenuItem(title: "无输出设备", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.insertItem(item, at: removeIndex)
        }
    }

    private func refreshInputDevices() {
        guard let menu = statusItem.menu,
              let index = menu.items.firstIndex(where: { $0.title == "输入设备" }) else { return }

        let removeIndex = index + 1
        while removeIndex < menu.items.count, !menu.items[removeIndex].isSeparatorItem {
            menu.removeItem(at: removeIndex)
        }

        let devices = audioManager.inputDevices().filter { !isVirtualNoSoundDevice($0.name) }
        let current = audioManager.defaultInputDevice()

        for (i, device) in devices.enumerated() {
            let item = NSMenuItem(
                title: device.name,
                action: #selector(selectInputDevice(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = device
            item.state = (device.id == current?.id) ? .on : .off
            menu.insertItem(item, at: removeIndex + i)
        }

        if devices.isEmpty {
            let item = NSMenuItem(title: "无输入设备", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.insertItem(item, at: removeIndex)
        }
    }

    private func refreshVolume() {
        let volume = router.outputVolume()
        volumeSlider?.floatValue = Float(volume * 100)
        muteMenuItem?.state = router.isOutputMuted() ? .on : .off
        // 后端标签：若环回未启用而默认输出是虚拟设备，额外提示不发声
        if !router.virtualAudioActive,
           let defName = audioManager.defaultOutputDevice()?.name,
           isVirtualNoSoundDevice(defName) {
            backendMenuItem?.title = "音量后端: 虚拟设备直连·不发声（请开启虚拟音频环回）"
        } else {
            backendMenuItem?.title = router.backendLabel
        }
        refreshVirtualAudioMenu()
        updateStatusItemTitle(volume: volume)
    }

    /// 刷新虚拟音频菜单项的勾选/可用状态
    private func refreshVirtualAudioMenu() {
        guard let toggle = virtualAudioToggleItem else { return }
        let tapMode = (router.captureBackend == .processTap)
        let available = router.canEnableVirtualAudio
        // 开关状态反映引擎真实是否在跑（而非仅用户意图）
        let active = router.virtualAudioActive && router.virtualEngineRunning
        toggle.isEnabled = available || active
        toggle.title = "虚拟音频环回"

        let curDefault = audioManager.defaultOutputDevice()?.name ?? ""

        if active {
            toggle.state = .on
            // ★ Tap 后端不切默认输出，"默认输出是否为 BlackHole" 不构成失效判据
            let hijacked = tapMode ? false : !isDefaultOutputBlackHole
            if hijacked {
                virtualAudioHintItem?.title = "⚠ 环回已失效：默认输出被切到 \(curDefault)，点上方开关恢复"
                virtualAudioHintItem?.isHidden = false
            } else if router.noSoundDetected {
                virtualAudioHintItem?.title = tapMode
                    ? "⚠ 未采集到系统音频，请确认有应用正在播放声音"
                    : "⚠ 未检测到声音进入 BlackHole，请重启播放或重选音频源"
                virtualAudioHintItem?.isHidden = false
            } else {
                virtualAudioHintItem?.isHidden = true
            }
        } else if available {
            toggle.state = .off
            if !tapMode && isVirtualNoSoundDevice(curDefault) {
                virtualAudioHintItem?.title = "⚠ 当前默认输出是 \(curDefault)（虚拟设备），不会发声——请开启环回或切回物理显示器"
                virtualAudioHintItem?.isHidden = false
            } else {
                virtualAudioHintItem?.isHidden = true
            }
        } else {
            toggle.state = .off
            toggle.title = tapMode ? "虚拟音频环回（系统不支持 Tap）" : "虚拟音频环回（未安装 BlackHole）"
            virtualAudioHintItem?.title = tapMode
                ? "⚠ 系统音频采集需 macOS 14.2 及以上，请改用 BlackHole 方式"
                : "⚠ 需先安装 BlackHole 才能软件控制音量"
            virtualAudioHintItem?.isHidden = false
        }
        installBlackHoleItem?.isHidden = VirtualAudioEngine.shared.isBlackHoleInstalled
        refreshCaptureBackendMenu()
    }

    /// 刷新「采集方式」子菜单（勾选当前后端；环回运行中禁止切换）
    private func refreshCaptureBackendMenu() {
        guard let item = captureBackendItem, let sub = item.submenu else { return }
        let cur = router.captureBackend
        let running = router.virtualAudioActive
        item.title = "采集方式: \(cur.displayName)"
        for it in sub.items {
            guard let raw = it.representedObject as? String,
                  let b = CaptureBackend(rawValue: raw) else { continue }
            it.state = (b == cur) ? .on : .off
            it.title = b.isAvailable ? b.displayName : "\(b.displayName)（不可用）"
            it.isEnabled = b.isAvailable && !running
        }
    }

    /// 切换采集后端（持久化；需停止环回后重新启用才生效）
    @objc private func selectCaptureBackend(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let b = CaptureBackend(rawValue: raw) else { return }
        guard !router.virtualAudioActive else {
            log("采集方式切换被忽略：环回运行中，请先停止环回")
            return
        }
        guard b.isAvailable else {
            log("采集方式「\(b.displayName)」当前不可用，未切换")
            return
        }
        CaptureBackend.current = b
        log("采集方式已切换为：\(b.displayName)")
        refreshVirtualAudioMenu()
    }

    /// 当前默认输出是否就是 BlackHole（按名字识别，不硬编码 id）
    private var isDefaultOutputBlackHole: Bool {
        audioManager.defaultOutputDevice()?.name.localizedCaseInsensitiveContains("BlackHole") ?? false
    }

    /// 判断是否为"虚拟/不发声"输出设备（手动选中时需提示）
    private func isVirtualNoSoundDevice(_ name: String) -> Bool {
        let n = name.lowercased()
        return n.contains("blackhole") || n.contains("virtual") || n.contains("cadefault")
    }

    private func updateStatusItemTitle(volume: Float32) {
        guard let button = statusItem.button else { return }
        // 状态栏显示音量百分比（可选，图标+文字）
        let percent = Int(round(volume * 100))
        button.title = " \(percent)%"
    }

    /// 快捷键调节音量后显示 HUD 反馈（读取当前音量百分比）
    private func showVolumeHUD() {
        let pct = router.outputVolume() * 100.0
        ScrollHUD.shared.show(type: .volume, value: Float(pct), fine: false)
    }

    // MARK: - 回调设置

    private func setupAudioCallbacks() {
        audioManager.onDevicesChanged = { [weak self] in
            self?.refreshMenu()
            log("Devices changed, menu refreshed")
        }
        audioManager.onDefaultOutputChanged = { [weak self] _ in
            VolumeRouter.shared.refreshRouting()
            self?.refreshMenu()
            log("Default output changed, menu refreshed")
        }
        audioManager.onDefaultInputChanged = { [weak self] _ in
            self?.refreshMenu()
            log("Default input changed, menu refreshed")
        }
        audioManager.onOutputVolumeChanged = { [weak self] volume in
            self?.refreshVolume()
        }
        audioManager.onOutputMuteChanged = { [weak self] _ in
            self?.refreshVolume()
        }
    }

    private func setupHotKeyCallbacks() {
        hotKeyManager.onHotKey = { [weak self] action in
            guard let self = self else { return }
            switch action {
            case .switchOutput:
                self.audioManager.cycleToNextOutputDevice()
            case .switchInput:
                self.audioManager.cycleToNextInputDevice()
            case .volumeUp:
                self.router.increaseOutputVolume()
                self.showVolumeHUD()
            case .volumeDown:
                self.router.decreaseOutputVolume()
                self.showVolumeHUD()
            case .mute:
                self.router.toggleOutputMute()
            case .brightnessUp:
                self.adjustBrightness(delta: 5)
            case .brightnessDown:
                self.adjustBrightness(delta: -5)
            }
        }
        router.onBackendChanged = { [weak self] _ in
            self?.refreshVolume()
        }
    }

    // MARK: - 亮度控制

    /// 启动/热插拔后：识别主外接显示器，绑定 DDC uuid，读取初始亮度
    func setupBrightnessControl() {
        let displays = DisplayDetector.shared.detectDisplays()
        // 顶部状态行
        statusLineItem?.title = "输出: \(audioManager.defaultOutputDevice()?.name ?? "—")"

        guard let primary = DisplayDetector.shared.primaryExternalDisplay() else {
            setBrightnessSectionVisible(false, displayName: nil)
            brightnessUUID = nil
            log("Brightness: 未检测到外接显示器，隐藏亮度滑块")
            return
        }

        brightnessUUID = primary.uuid
        let name = primary.profile?.displayName ?? primary.name
        brightnessDisplayBaseName = name
        setBrightnessSectionVisible(true, displayName: name)
        log("Brightness: 控制对象 = \(name) (uuid=\(primary.uuid))，共 \(displays.count) 台显示器")

        // 后台读初始亮度，避免阻塞 UI
        ddcWorkQueue.async { [weak self] in
            guard let self = self else { return }
            if let v = DDCManager.shared.readVCP(uuid: primary.uuid, code: DDCVCP.luminance) {
                DispatchQueue.main.async {
                    self.brightnessValue = v.cur
                    self.brightnessSlider?.integerValue = v.cur
                    self.brightnessHeaderItem?.title = "亮度 · \(name)（\(v.cur)）"
                }
                log("Brightness: 读回初始值 cur=\(v.cur) max=\(v.max)")
            } else {
                log("Brightness: 读 VCP 0x10 失败（该显示器 DDC 亮度不可用）")
            }
        }
    }

    /// 显示/隐藏亮度分组
    private func setBrightnessSectionVisible(_ visible: Bool, displayName: String?) {
        brightnessHeaderItem?.isHidden = !visible
        brightnessSliderItem?.isHidden = !visible
        brightnessSeparatorItem?.isHidden = !visible
        if visible, let name = displayName {
            brightnessHeaderItem?.title = "亮度 · \(name)"
        }
    }

    /// 滑块拖动回调（NSSlider 连续触发，做 100ms 节流）
    @objc private func brightnessSliderChanged(_ sender: NSSlider) {
        brightnessValue = sender.integerValue
        brightnessHeaderItem?.title = "亮度 · \(brightnessHeaderItemTitle())（\(brightnessValue)）"
        scheduleBrightnessWrite(brightnessValue)
    }

    /// 热键步进（±5，边界夹紧）
    private func adjustBrightness(delta: Int) {
        guard brightnessUUID != nil else {
            log("Brightness hotkey: 无外接显示器，忽略")
            return
        }
        let next = max(0, min(100, brightnessValue + delta))
        log("Brightness hotkey: \(delta > 0 ? "↑" : "↓") \(brightnessValue) → \(next)")
        brightnessValue = next
        brightnessSlider?.integerValue = next
        brightnessHeaderItem?.title = "亮度 · \(brightnessHeaderItemTitle())（\(next)）"
        scheduleBrightnessWrite(next)
        // HUD 反馈
        ScrollHUD.shared.show(type: .brightness, value: Float(next), fine: false)
    }

    /// 边缘滚轮手势调用：在权威 brightnessValue 上做浮点步进（粗调/精细），复用同一写路径与缓存。
    /// 必须在主线程调用。返回最终百分比（无外接显示器返回 nil）。
    @discardableResult
    func gestureAdjustBrightness(deltaPercent: Float, fine: Bool) -> Float? {
        guard brightnessUUID != nil else {
            log("Gesture brightness: 无外接显示器，忽略")
            return nil
        }
        let cur = Float(brightnessValue)
        let next = max(0, min(100, cur + deltaPercent))
        let intNext = Int(next.rounded())
        log("Gesture brightness: \(String(format: "%.1f", cur)) → \(String(format: "%.1f", next)) (fine=\(fine))")
        brightnessValue = intNext
        brightnessSlider?.integerValue = intNext
        brightnessHeaderItem?.title = "亮度 · \(brightnessHeaderItemTitle())（\(intNext)）"
        scheduleBrightnessWrite(intNext)
        ScrollHUD.shared.show(type: .brightness, value: next, fine: fine)
        return next
    }

    /// 节流：100ms 窗口内合并多次写，只发最新值，避免 I2C 总线拥塞
    private func scheduleBrightnessWrite(_ value: Int) {
        pendingBrightness = value
        brightnessWriteWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, let v = self.pendingBrightness else { return }
            self.pendingBrightness = nil
            self.performBrightnessWrite(v)
        }
        brightnessWriteWork = work
        ddcWorkQueue.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    /// 实际下发 DDC 写 VCP 0x10（后台队列）
    private func performBrightnessWrite(_ value: Int) {
        guard let uuid = brightnessUUID else { return }
        let ok = DDCManager.shared.writeVCP(uuid: uuid, code: DDCVCP.luminance, value: UInt16(value))
        log("Brightness write VCP 0x10 = \(value) → \(ok ? "OK" : "FAIL")")
    }

    /// 亮度标题里的基础显示器名（不含括号里的数值），
    /// 由 setupBrightnessControl 写入，标题行每次拼接为 "亮度 · <name>（<值>）"
    private func brightnessHeaderItemTitle() -> String {
        brightnessDisplayBaseName
    }

    /// 亮度分组标题的基础名（不含数值）
    private var brightnessDisplayBaseName: String = ""

    // MARK: - 动作

    @objc private func selectOutputDevice(_ sender: NSMenuItem) {
        guard let device = sender.representedObject as? AudioDevice else { return }
        audioManager.setDefaultOutputDevice(device)
    }

    @objc private func selectInputDevice(_ sender: NSMenuItem) {
        guard let device = sender.representedObject as? AudioDevice else { return }
        audioManager.setDefaultInputDevice(device)
    }

    @objc private func volumeSliderChanged(_ sender: NSSlider) {
        let volume = Float32(sender.floatValue / 100.0)
        router.setOutputVolume(volume)
    }

    @objc private func toggleMute(_ sender: NSMenuItem) {
        router.toggleOutputMute()
    }

    @objc private func toggleVirtualAudio(_ sender: NSMenuItem) {
        if router.virtualAudioActive {
            // ★ 仅 BlackHole 后端会切默认输出；失效态下点击先恢复默认输出，而非停环回。
            //   Tap 后端不动默认输出，直接停环回即可（否则会把默认输出劫持到 BlackHole）。
            if router.captureBackend == .blackHole,
               !isDefaultOutputBlackHole,
               let bh = VirtualAudioEngine.shared.findBlackHoleDevice() {
                audioManager.setDefaultOutputDevice(bh)
                log("虚拟音频失效：已恢复默认输出到 BlackHole(\(bh.id))")
            } else {
                router.disableVirtualAudio()
            }
        } else {
            router.enableVirtualAudio()
        }
        refreshVolume()
    }

    @objc private func showInstallBlackHole(_ sender: NSMenuItem) {
        let msg = """
BlackHole 2ch 虚拟音频驱动未安装。

安装步骤（需要 sudo 密码）：
  1. 在项目根目录执行：
       bash scripts/install_blackhole.sh
  2. 脚本会自动从 BlackHole 官方 Releases 下载最新的 pkg（无需手动准备）
  3. 输入 sudo 密码，等待 coreaudiod 重启
  4. 回到本菜单重新点击「启用虚拟音频环回」

查看脚本全部选项：
  bash scripts/install_blackhole.sh --help

官方下载页：
  https://github.com/ExistentialAudio/BlackHole/releases

此命令仅输出到日志，不自动执行 sudo。
"""
        log("安装 BlackHole 引导:\n\(msg)")
        let alert = NSAlert()
        alert.messageText = "安装 BlackHole 虚拟音频驱动"
        alert.informativeText = msg
        alert.alertStyle = .informational
        alert.addButton(withTitle: "复制脚本命令")
        alert.addButton(withTitle: "关闭")
        if alert.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("bash scripts/install_blackhole.sh", forType: .string)
        }
    }

    // MARK: - 边缘滚轮手势动作

    /// 刷新手势菜单的勾选/权限可见状态（菜单每次弹出时调用）
    func refreshGestureMenu() {
        let g = ScrollWheelGestureManager.shared
        gestureToggleItem?.state = g.isEnabled ? .on : .off
        gestureRequireOptionItem?.state = g.requiresOptionKey ? .on : .off
        // 权限项：始终显示授权状态（已授权✓ / 未授权⚠）
        gesturePermissionItem?.isHidden = false
        gesturePermissionItem?.title = g.isTrusted
            ? "✅ 辅助功能已授权"
            : "⚠️ 辅助功能未授权 — 点此授权"
        // 子菜单勾选
        gestureZoneItem?.title = "热区高度（\(Int(g.hotZoneHeight))px）"
        gestureZoneItem?.submenu?.items.forEach { item in
            if let h = item.representedObject as? Int {
                item.state = (Int(g.hotZoneHeight) == h) ? .on : .off
            }
        }
        gestureStepItem?.title = "调节步进（\(g.stepSize)%）"
        gestureStepItem?.submenu?.items.forEach { item in
            if let st = item.representedObject as? Int {
                item.state = (g.stepSize == st) ? .on : .off
            }
        }
        gestureAutoFullscreenItem?.state = g.autoFullscreenDetection ? .on : .off
        gestureFineStepItem?.title = String(format: "精细步进（%.1f%%）", g.fineStepSize)
        gestureFineStepItem?.submenu?.items.forEach { item in
            if let v = item.representedObject as? Double {
                item.state = (abs(g.fineStepSize - Float(v)) < 0.01) ? .on : .off
            }
        }
        // 顶部识别行追加当前手势模式
        statusLineItem?.title = "输出: \(audioManager.defaultOutputDevice()?.name ?? "—")"
    }

    @objc private func toggleGesture(_ sender: NSMenuItem) {
        let g = ScrollWheelGestureManager.shared
        let wantOn = !g.isEnabled
        log("Gesture 开关点击: wantOn=\(wantOn) 当前 isTrusted=\(g.isTrusted) isRunning=\(g.isRunning)")
        if wantOn && !g.isTrusted {
            // 仍持久化用户开启意图（pendingOn），授权生效后自动补启动
            g.isEnabled = true
            g.requestAccessibilityPermission()
            let alert = NSAlert()
            alert.messageText = "需要辅助功能权限"
            alert.informativeText = """
            边缘滚轮手势需要辅助功能（Accessibility）权限才能拦截滚轮事件。

            已为你打开系统设置，请在「隐私与安全性 → 辅助功能」中允许 TuneC。
            授权后回到本应用无需重启，手势会自动开启。
            """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "好")
            alert.runModal()
            log("Gesture: 已记录开启意图(pendingOn)，等待授权")
            refreshGestureMenu()
            return
        }
        g.isEnabled = wantOn
        log("Gesture 开关: \(wantOn ? "开启" : "关闭")")
        refreshGestureMenu()
    }

    @objc private func requestGestureAccess(_ sender: NSMenuItem) {
        ScrollWheelGestureManager.shared.requestAccessibilityPermission()
    }

    @objc private func setGestureZoneHeight(_ sender: NSMenuItem) {
        guard let h = sender.representedObject as? Int else { return }
        ScrollWheelGestureManager.shared.hotZoneHeight = CGFloat(h)
        log("Gesture 热区高度: \(h)px")
        refreshGestureMenu()
    }

    @objc private func setGestureStep(_ sender: NSMenuItem) {
        guard let st = sender.representedObject as? Int else { return }
        ScrollWheelGestureManager.shared.stepSize = st
        log("Gesture 步进: \(st)%")
        refreshGestureMenu()
    }

    @objc private func toggleGestureRequireOption(_ sender: NSMenuItem) {
        let g = ScrollWheelGestureManager.shared
        g.requiresOptionKey.toggle()
        log("Gesture 按住⌥模式: \(g.requiresOptionKey ? "开" : "关")")
        refreshGestureMenu()
    }

    @objc private func toggleGestureAutoFullscreen(_ sender: NSMenuItem) {
        let g = ScrollWheelGestureManager.shared
        g.autoFullscreenDetection.toggle()
        log("Gesture 自动全屏检测: \(g.autoFullscreenDetection ? "开" : "关")")
        refreshGestureMenu()
    }

    @objc private func setGestureFineStep(_ sender: NSMenuItem) {
        guard let v = sender.representedObject as? Double else { return }
        ScrollWheelGestureManager.shared.fineStepSize = Float(v)
        log("Gesture 精细步进: \(v)%")
        refreshGestureMenu()
    }

    @objc private func showAbout(_ sender: NSMenuItem) {
        let alert = NSAlert()
        alert.messageText = "TuneC"
        alert.informativeText = """
        简易音频设备切换与音量控制工具

        状态栏常驻 · 全局快捷键 · 默认不占用麦克风

        采集系统音频需授权「屏幕与系统音频录制」；边缘滚轮手势需授权「辅助功能」；
        使用 BlackHole 采集方式时另需麦克风权限。以上权限均按需申请。
        macOS 13 上虚拟音频环回需先安装 BlackHole 驱动。

        最低支持 macOS 13
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }

    @objc private func quit(_ sender: NSMenuItem) {
        log("Quit requested")
        hotKeyManager.unregisterAll()
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - 工具函数
//   热键短名 keyDisplay(_:) 定义在 HotKeyManager.swift，模块内共用。
