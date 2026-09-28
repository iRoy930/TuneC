import AppKit
import TuneCCore

// MARK: - 边缘滚轮 / 快捷键 HUD 反馈
//
// 极简版本：半透明深色圆角胶囊（无毛玻璃、无实心底），
// 水平居中，垂直在屏幕高度 61.8%（黄金分割点）。
// 图标 + 百分比 + 细进度条；仅进度条与百分比随值实时变化，
// 无缩放/弹跳动画，只有淡入（0.15s）→ 停留 1.0s → 淡出（0.35s）。

final class ScrollHUD {

    enum HUDType {
        case brightness, contrast, volume, device, mute
    }

    static let shared = ScrollHUD()

    // 两种尺寸：数值型带进度条略高，文本型（切设备/静音）略矮
    private let numericSize = NSSize(width: 200, height: 72)
    private let textSize     = NSSize(width: 190, height: 58)
    private let cornerRadius: CGFloat = 14

    private var panel: NSPanel?
    private var card: NSView?            // 半透明圆角底
    private var iconView: NSImageView?
    private var titleLabel: NSTextField?
    private var bar: HUDProgressBar?

    private var fadeTimer: Timer?
    private var generation: Int = 0      // 连续触发时取消上一次淡出

    private init() {}

    // MARK: - 数值型 HUD（亮度/对比度/音量）

    func show(type: HUDType, value: Float, fine: Bool) {
        switch type {
        case .brightness, .contrast, .volume:
            let pct = CGFloat(max(0, min(100, value)))
            let text = fine ? String(format: "%.1f%%", pct)
                            : String(format: "%.0f%%", pct.rounded())
            present(type: type, mainText: text, progress: pct / 100.0)
        default: return
        }
    }

    // MARK: - 文本型 HUD（切设备 / 静音）

    func show(type: HUDType, text: String) {
        switch type {
        case .device, .mute:
            present(type: type, mainText: text, progress: nil)
        default: return
        }
    }

    // MARK: - 呈现

    //   HUD 位置与触发它的热区无关：统一显示在鼠标所在屏幕的水平中线、
    //   垂直 61.8%（黄金分割点）处，故不需要 zone 参数。
    private func present(type: HUDType, mainText: String, progress: CGFloat?) {
        ensurePanel()
        guard let panel = panel,
              let card = card,
              let iconView = iconView,
              let titleLabel = titleLabel,
              let bar = bar else { return }

        let isNumeric = progress != nil
        let size = isNumeric ? numericSize : textSize

        // 鼠标所在屏幕（回退主屏）；中心 = 水平中线、垂直 61.8%
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
                     ?? NSScreen.main ?? NSScreen.screens[0]
        let f = screen.frame
        let cx = f.midX
        let cy = f.minY + f.height * 0.618
        let origin = NSPoint(x: cx - size.width / 2, y: cy - size.height / 2)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)

        // 内容（静态部分不重复动画）
        configureIcon(type: type, iconView: iconView)
        titleLabel.stringValue = mainText
        if let progress = progress {
            bar.isHidden = false
            bar.value = progress
        } else {
            bar.isHidden = true
        }
        layoutContent(isNumeric: isNumeric, in: card.bounds)
        applyAppearance() // 跟随系统亮/暗色

        // 取消上一次淡出，重置透明度（连续触发不闪烁）
        generation += 1
        fadeTimer?.invalidate()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        panel.alphaValue = 1.0
        CATransaction.commit()
        panel.orderFrontRegardless()

        // 淡入（仅透明度，无缩放）
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
        }

        // 停留 1.0s 后淡出（仅透明度，无缩放）
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            guard let self = self, let panel = self.panel else { return }
            // 硬性超时：即使 generation 不匹配（期间有新触发），新触发也会重建 timer，
            // 这里只负责把旧面板收起；若期间有新面板正在显示，跳过即可。
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.35
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0.0
            } completionHandler: {
                if panel.alphaValue == 0.0 {
                    panel.orderOut(nil)
                }
            }
        }
    }

    private func configureIcon(type: HUDType, iconView: NSImageView) {
        let name: String
        switch type {
        case .brightness: name = "sun.max.fill"
        case .contrast:   name = "circle.lefthalf.fill"
        case .volume:     name = "speaker.wave.2.fill"
        case .mute:       name = "speaker.slash.fill"
        case .device:     name = "rectangle.on.rectangle.fill"
        }
        let cfg = NSImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        iconView.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg)
    }

    /// 跟随系统外观：暗色→黑底白字；亮色→白底黑字
    private func applyAppearance() {
        guard let card = card, let iconView = iconView, let titleLabel = titleLabel, let bar = bar else { return }
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        card.layer?.backgroundColor = NSColor(calibratedWhite: isDark ? 0.0 : 1.0, alpha: isDark ? 0.30 : 0.55).cgColor
        iconView.contentTintColor = isDark ? .white : .black
        titleLabel.textColor = isDark ? .white : .black
        bar.isDark = isDark
        bar.needsDisplay = true
    }

    private func layoutContent(isNumeric: Bool, in bounds: NSRect) {
        guard let iconView = iconView, let titleLabel = titleLabel, let bar = bar else { return }
        let W = bounds.width, H = bounds.height

        // 图标：左侧垂直居中
        let iconSide: CGFloat = 26
        iconView.frame = CGRect(x: 18, y: (H - iconSide) / 2, width: iconSide, height: iconSide)

        // 右列：紧贴图标右侧
        let textX: CGFloat = 56
        let textW = W - textX - 18
        if isNumeric {
            // 数值 + 进度条作为一组垂直居中
            let titleH: CGFloat = 20
            let barH: CGFloat = 5
            let gap: CGFloat = 6
            let groupH = titleH + gap + barH
            let startY = (H - groupH) / 2
            titleLabel.frame = CGRect(x: textX, y: startY + barH + gap, width: textW, height: titleH)
            bar.frame = CGRect(x: textX, y: startY, width: textW, height: barH)
            titleLabel.font = .monospacedDigitSystemFont(ofSize: 17, weight: .semibold)
        } else {
            titleLabel.frame = CGRect(x: textX, y: (H - 20) / 2, width: textW, height: 20)
            titleLabel.font = .systemFont(ofSize: 13.5, weight: .medium)
        }
    }

    private func ensurePanel() {
        guard panel == nil else { return }

        let style: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: numericSize.width, height: numericSize.height),
            styleMask: style, backing: .buffered, defer: false
        )
        p.isFloatingPanel = true
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.collectionBehavior = [.fullScreenAuxiliary, .stationary]
        p.ignoresMouseEvents = true

        // 半透明圆角底：极淡，确保真透明感
        let card = NSView(frame: p.contentView!.bounds)
        card.autoresizingMask = [.width, .height]
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor(calibratedWhite: 0.0, alpha: 0.30).cgColor
        card.layer?.cornerRadius = cornerRadius
        card.layer?.masksToBounds = true

        // 图标
        let iconView = NSImageView(frame: .zero)
        iconView.imageScaling = .scaleProportionallyDown
        card.addSubview(iconView)

        // 数值 / 文本
        let tf = NSTextField(labelWithString: "")
        tf.textColor = .white
        tf.alignment = .left
        tf.isBezeled = false
        tf.drawsBackground = false
        tf.isEditable = false
        tf.lineBreakMode = .byTruncatingTail
        card.addSubview(tf)

        // 细进度条
        let bar = HUDProgressBar(frame: .zero)
        card.addSubview(bar)

        p.contentView = card

        panel = p
        self.card = card
        self.iconView = iconView
        self.titleLabel = tf
        self.bar = bar
    }
}

// MARK: - 细圆角进度条
final class HUDProgressBar: NSView {
    /// 0...1
    var value: CGFloat = 0 { didSet { needsDisplay = true } }
    /// 亮/暗色模式（由 HUD 在每次显示前设置）
    var isDark: Bool = true { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds
        let radius = r.height / 2
        let fgColor: NSColor = isDark ? .white : .black
        // 轨道：半透明
        let bg = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
        fgColor.withAlphaComponent(isDark ? 0.22 : 0.25).set()
        bg.fill()
        // 填充：近实色
        let fillW = max(bounds.width * value, r.height)
        var fr = r
        fr.size.width = min(fillW, r.width)
        let fg = NSBezierPath(roundedRect: fr, xRadius: radius, yRadius: radius)
        fgColor.withAlphaComponent(isDark ? 0.92 : 0.90).set()
        fg.fill()
    }
}
