import AppKit
import SwiftUI

/// What a recipe menu needs to build its live dial and report previews.
@MainActor
struct RecipeMenuContext {
    let field: RecipeField
    let settings: SquishSettings
    let preview: (RecipePreview?) -> Void
}

/// Builds native NSMenus from recipe options: right-aligned values, preset
/// icons, a Presets submenu, and the live dial at the top.
@MainActor
enum RecipeMenuBuilder {
    /// Horizontal distance from a menu item's edge to its title text.
    static let titleInset: CGFloat = 22
    /// Tag for the "Any …" item so the dial can update its checkmark.
    static let anyTag = 1

    static func menu(for options: [RecipeOption], context: RecipeMenuContext,
                     delegate: NSMenuDelegate) -> (NSMenu, NSMenuItem?) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = delegate
        let font = NSFont.menuFont(ofSize: 0)
        let titleWidth = options.map { ($0.title as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        let detailWidth = options.compactMap { $0.detail }.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        let para = NSMutableParagraphStyle()
        para.tabStops = [NSTextTab(textAlignment: .right, location: ceil(titleWidth + 32 + detailWidth))]

        var selected: NSMenuItem?
        for option in options {
            switch option.kind {
            case .separator:
                menu.addItem(.separator())
            case .dial:
                let item = NSMenuItem()
                item.view = RecipeDialView(context: context)
                menu.addItem(item)
            case .submenu:
                let item = NSMenuItem(title: option.title, action: nil, keyEquivalent: "")
                let (sub, _) = Self.menu(for: option.children, context: context, delegate: delegate)
                item.submenu = sub
                item.representedObject = PreviewBox(option.preview)
                menu.addItem(item)
            case .choice, .command:
                let item = ClosureMenuItem(title: option.title, handler: option.action)
                if let detail = option.detail {
                    let title = NSMutableAttributedString(string: option.title, attributes: [.font: font, .paragraphStyle: para])
                    title.append(NSAttributedString(string: "\t" + detail, attributes: [
                        .font: font, .paragraphStyle: para, .foregroundColor: NSColor.secondaryLabelColor,
                    ]))
                    item.attributedTitle = title
                }
                if let symbol = option.symbol {
                    item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                        .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
                }
                item.representedObject = PreviewBox(option.preview)
                if option.isAny { item.tag = Self.anyTag }
                item.state = option.checked ? .on : .off
                if option.checked, selected == nil { selected = item }
                menu.addItem(item)
            }
        }
        return (menu, selected)
    }
}

/// Carries a preview through `representedObject`.
final class PreviewBox {
    let preview: RecipePreview?
    init(_ preview: RecipePreview?) { self.preview = preview }
}

/// Reports hover previews to the window and clears them when the menu closes.
@MainActor
final class RecipeMenuController: NSObject, NSMenuDelegate {
    private let report: (RecipePreview?) -> Void
    weak var root: NSMenu?

    init(report: @escaping (RecipePreview?) -> Void) { self.report = report }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        guard let item else { return }  // Leaving an item (e.g. onto the dial) keeps the last preview.
        report((item.representedObject as? PreviewBox)?.preview)
    }

    func menuDidClose(_ menu: NSMenu) {
        if menu === root { report(nil) }
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func fire() { handler() }
}

// MARK: - The dial

/// The live control at the top of the File Size and Dimensions menus: a mini
/// clamp, the value in big type, and a log-scale slider with detents at the
/// presets and an orange "no limit" dot at its far end. Dragging applies immediately, like the volume slider in Control
/// Center, and the menu stays open.
@MainActor
final class RecipeDialView: NSView {
    private let context: RecipeMenuContext
    private var settings: SquishSettings { context.settings }
    private var isSize: Bool { context.field == .size }

    private let clamp = NSHostingView(rootView: ClampView(squeeze: 0))
    private let big = NSTextField(labelWithString: "")
    private let why = NSTextField(labelWithString: "")
    private let slider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let anyDot = AnyDot()
    private var mode: NSSegmentedControl?
    private var snapped: String?

    private static let width: CGFloat = 300
    private static let inset: CGFloat = 14
    /// Distance from the slider's edge to the centre of its knob at either end.
    private static let knobInset: CGFloat = 10
    private static let snapWindow = 0.022
    /// The slider position of the largest limit; past it, the track ends at "Any".
    private static let limitEnd = 0.9
    /// Slider positions beyond this snap to "Any"; between it and `limitEnd`, to the largest limit.
    private static let anyThreshold = 0.95

    override var isFlipped: Bool { true }

    init(context: RecipeMenuContext) {
        self.context = context
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: context.field == .size ? 104 : 136))
        build()
        sync(fromSettings: true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Scale

    private var range: (lo: Double, hi: Double) {
        isSize ? (log(100_000), log(50_000_000)) : (log(320), log(8192))
    }
    private func fraction(_ v: Double) -> Double {
        min(1, max(0, (log(max(v, 1)) - range.lo) / (range.hi - range.lo)))
    }
    private func value(at f: Double) -> Double { exp(range.lo + f * (range.hi - range.lo)) }
    /// Where a limit sits on the slider, leaving the far end for "Any".
    private func position(_ v: Double) -> Double { fraction(v) * Self.limitEnd }
    private func value(atPosition p: Double) -> Double { value(at: min(p, Self.limitEnd) / Self.limitEnd) }

    private var presetValues: [(name: String, value: Double)] {
        isSize ? settings.sortedSizePresets.map { ($0.name, Double($0.bytes)) }
               : settings.sortedDimensionPresets.map { ($0.name, Double($0.pixels)) }
    }

    // MARK: Layout

    private func build() {
        let x = Self.inset, w = Self.width - Self.inset * 2

        clamp.frame = NSRect(x: x, y: 10, width: 46, height: 50)
        addSubview(clamp)

        let rounded = NSFont.systemFont(ofSize: 22, weight: .bold)
        big.font = rounded.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 22) } ?? rounded
        big.textColor = .squishInk
        big.frame = NSRect(x: x + 58, y: 12, width: w - 58, height: 28)
        big.lineBreakMode = .byTruncatingTail
        addSubview(big)

        why.font = .systemFont(ofSize: 11)
        why.textColor = .secondaryLabelColor
        why.frame = NSRect(x: x + 58, y: 40, width: w - 58, height: 16)
        why.lineBreakMode = .byTruncatingTail
        addSubview(why)

        var y: CGFloat = 70
        if !isSize {
            let seg = NSSegmentedControl(labels: ["Long Side", "Width", "Height"], trackingMode: .selectOne,
                                         target: self, action: #selector(modeChanged))
            seg.controlSize = .small
            seg.segmentDistribution = .fillEqually
            seg.frame = NSRect(x: x, y: y, width: w, height: 22)
            addSubview(seg)
            mode = seg
            y += 32
        }

        slider.frame = NSRect(x: x, y: y, width: w, height: 20)
        slider.isContinuous = true
        // Menus never become key, so the default fill would draw grey.
        slider.trackFillColor = NSColor(named: "AccentColor")
        slider.target = self
        slider.action = #selector(sliderChanged)
        slider.setAccessibilityLabel(isSize ? "File size limit" : "Dimension limit")
        addSubview(slider)

        // Detents at each preset, under the track.
        for preset in presetValues {
            let tick = NSView(frame: NSRect(x: 0, y: y + 21, width: 2, height: 6))
            tick.wantsLayer = true
            tick.layer?.backgroundColor = NSColor.tertiaryLabelColor.cgColor
            tick.layer?.cornerRadius = 1
            tick.frame.origin.x = trackX(position(preset.value)) - 1
            addSubview(tick)
        }

        // The orange dot at the end of the track means "no limit".
        anyDot.frame = NSRect(x: trackX(1) - 8, y: y + 20, width: 16, height: 10)
        anyDot.label = isSize ? "Any file size" : "Any dimensions"
        anyDot.onClick = { [weak self] in self?.chooseAny() }
        addSubview(anyDot)
    }

    /// The x coordinate of the knob's centre at a slider position.
    private func trackX(_ p: Double) -> CGFloat {
        slider.frame.minX + Self.knobInset + p * (slider.frame.width - Self.knobInset * 2)
    }

    // MARK: Actions

    @objc private func sliderChanged() {
        if slider.doubleValue > Self.anyThreshold {
            slider.doubleValue = 1
            if isOn { chooseAny() }
            return
        }
        if slider.doubleValue > Self.limitEnd { slider.doubleValue = Self.limitEnd }
        var v = value(atPosition: slider.doubleValue)
        var snap: (name: String, value: Double)?
        for p in presetValues where abs(position(p.value) - slider.doubleValue) < Self.snapWindow { snap = p }
        if let snap {
            v = snap.value
            slider.doubleValue = position(v)
            if snapped != snap.name {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        }
        snapped = snap?.name

        if isSize { setBytes(v, preset: snap?.name) } else { setPixels(Int((v / 16).rounded()) * 16, preset: snap?.name) }
        sync(fromSettings: false)
        context.preview(currentPreview)
    }

    private func chooseAny() {
        if isSize { settings.sizeTargetEnabled = false } else { settings.dimensionEnabled = false }
        snapped = nil
        slider.doubleValue = 1
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        sync(fromSettings: false)
        context.preview(currentPreview)
    }

    @objc private func modeChanged() {
        guard let mode else { return }
        let px = settings.activePixels
        settings.dimensionMode = [.maxLongSide, .maxWidth, .maxHeight][max(mode.selectedSegment, 0)]
        if settings.dimensionEnabled { setPixels(px, preset: nil) }
        sync(fromSettings: true)
        context.preview(currentPreview)
    }

    private func setBytes(_ bytes: Double, preset: String?) {
        if let preset, let p = settings.sizePresets.first(where: { $0.name == preset }) {
            settings.sizeValue = p.value
            settings.sizeUnit = p.unit
        } else if bytes >= 1_000_000 {
            settings.sizeUnit = .mb
            settings.sizeValue = bytes >= 10_000_000 ? (bytes / 1_000_000).rounded() : (bytes / 100_000).rounded() / 10
        } else {
            settings.sizeUnit = .kb
            settings.sizeValue = max(10, (bytes / 10_000).rounded() * 10)
        }
        settings.sizeTargetEnabled = true
    }

    private func setPixels(_ px: Int, preset: String?) {
        if settings.dimensionMode == .fit { settings.dimensionMode = .maxLongSide }
        switch settings.dimensionMode {
        case .maxLongSide: settings.longSide = px
        case .maxWidth:    settings.maxWidth = px
        case .maxHeight:   settings.maxHeight = px
        case .fit:         break
        }
        settings.dimensionEnabled = true
    }

    // MARK: Display

    private var currentValue: Double {
        isSize ? Double(settings.targetBytes) : Double(settings.activePixels)
    }
    private var isOn: Bool { isSize ? settings.sizeTargetEnabled : settings.dimensionEnabled }

    private func sync(fromSettings: Bool) {
        if fromSettings {
            slider.doubleValue = isOn ? position(currentValue) : 1
            snapped = presetValues.first { abs($0.value - currentValue) < 1 && (isSize || settings.dimensionMode == .maxLongSide) }?.name
        }
        if let mode {
            switch settings.dimensionMode {
            case .maxLongSide: mode.selectedSegment = 0
            case .maxWidth:    mode.selectedSegment = 1
            case .maxHeight:   mode.selectedSegment = 2
            case .fit:         mode.selectedSegment = -1
            }
        }
        updateCheckmarks()
        anyDot.isOn = !isOn
        let p = currentPreview
        big.stringValue = p.title
        why.stringValue = p.detail
        clamp.rootView = ClampView(squeeze: p.squeeze ?? 0, photoScale: p.photoScale ?? 1)
        slider.setAccessibilityValueDescription(p.title)
    }

    /// Keeps the rest of the menu honest while dragging: "Any …" unchecks and
    /// the matching preset in the submenu gains its checkmark.
    private func updateCheckmarks() {
        guard let menu = enclosingMenuItem?.menu else { return }
        for item in menu.items {
            if item.tag == RecipeMenuBuilder.anyTag { item.state = isOn ? .off : .on }
            for sub in item.submenu?.items ?? [] {
                sub.state = isOn && sub.title == snapped ? .on : .off
            }
        }
    }

    private var currentPreview: RecipePreview {
        let phrase = isSize ? settings.sizePhrase : settings.dimensionPhrase
        let title = isOn ? phrase : (isSize ? "Any file size" : "Any dimensions")
        let detail: String
        if let snapped, isOn {
            detail = "\(snapped) preset · " + (isSize ? PresetInfo.blurb(size: snapped) : PresetInfo.blurb(pixels: snapped))
        } else {
            detail = isOn ? "Drag to the dot at the end for no limit" : "Drag left to set a limit"
        }
        if isSize {
            return RecipePreview(squeeze: isOn ? RecipeScale.squeeze(bytes: settings.targetBytes) : 0,
                                 title: title, detail: detail)
        }
        return RecipePreview(squeeze: 0.3, photoScale: isOn ? RecipeScale.photoScale(pixels: settings.activePixels) : 1,
                             title: title, detail: detail)
    }
}

/// The "no limit" detent at the end of the dial's track: a solid orange dot
/// when there's no limit, a ring when there is one.
@MainActor
final class AnyDot: NSView {
    var onClick: () -> Void = {}
    var label = "" { didSet { toolTip = label; setAccessibilityLabel(label) } }
    var isOn = false { didSet { needsDisplay = true; setAccessibilityValue(isOn ? "On" : "Off") } }
    private var hovering = false { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.checkBox)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick() }
    }
    override func accessibilityPerformPress() -> Bool { onClick(); return true }

    override func draw(_ dirtyRect: NSRect) {
        let orange = NSColor(named: "AccentColor") ?? .systemOrange
        let d: CGFloat = hovering ? 9 : 7
        let rect = NSRect(x: (bounds.width - d) / 2, y: (bounds.height - d) / 2, width: d, height: d)
        if isOn {
            let glow = NSShadow()
            glow.shadowColor = orange.withAlphaComponent(0.6)
            glow.shadowBlurRadius = 3
            glow.set()
            orange.setFill()
            NSBezierPath(ovalIn: rect).fill()
        } else {
            orange.withAlphaComponent(hovering ? 0.35 : 0.15).setFill()
            NSBezierPath(ovalIn: rect).fill()
            let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
            ring.lineWidth = 1
            orange.setStroke()
            ring.stroke()
        }
    }
}
