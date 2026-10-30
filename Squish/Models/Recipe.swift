import Foundation

/// The four settings that make up a squish "recipe", as they appear in the
/// sentence in the main window and in the Recipe menu.
enum RecipeField: String, CaseIterable, Identifiable {
    case size, dimensions, format, location
    var id: String { rawValue }

    var title: String {
        switch self {
        case .size:       return "File Size"
        case .dimensions: return "Dimensions"
        case .format:     return "Format"
        case .location:   return "Save To"
        }
    }
}

/// What the window's press and caption show while a choice is being considered
/// (a highlighted menu item, or the dial mid-drag).
struct RecipePreview: Equatable {
    var squeeze: Double?
    var title: String
    var detail: String
}

/// One entry in a recipe menu. The same model feeds the pop-up menus in the
/// window and the Recipe menu in the menu bar.
struct RecipeOption: Identifiable {
    enum Kind { case choice, command, separator, submenu, dial }

    let id = UUID()
    var kind: Kind
    var title = ""
    var detail: String?
    var checked = false
    /// The "Any File Size" / "Any Dimensions" item, which the dial unchecks live.
    var isAny = false
    /// Opens a popover on the sentence, so it only works while the sentence is on screen.
    var editsInSentence = false
    var preview: RecipePreview?
    var children: [RecipeOption] = []
    var action: () -> Void = {}

    static func choice(_ title: String, detail: String? = nil, checked: Bool,
                       preview: RecipePreview? = nil, action: @escaping () -> Void) -> RecipeOption {
        RecipeOption(kind: .choice, title: title, detail: detail, checked: checked, preview: preview, action: action)
    }
    static func command(_ title: String, preview: RecipePreview? = nil, action: @escaping () -> Void) -> RecipeOption {
        RecipeOption(kind: .command, title: title, preview: preview, action: action)
    }
    static func submenu(_ title: String, preview: RecipePreview? = nil, _ children: [RecipeOption]) -> RecipeOption {
        RecipeOption(kind: .submenu, title: title, preview: preview, children: children)
    }
    static var dial: RecipeOption { RecipeOption(kind: .dial) }
    static var separator: RecipeOption { RecipeOption(kind: .separator) }
}

/// Things a recipe menu can ask the UI to do that settings can't do alone.
struct RecipeActions {
    var editCustom: (RecipeField) -> Void
    var editPresets: (RecipeField) -> Void
    /// Asks for an output folder, as a sheet on the window the menu belongs to.
    var chooseFolder: () async -> URL?
}

/// Where a recipe menu is shown. The sentence's pop-ups lead with a live dial
/// and tuck presets into a submenu; the menu bar lists everything flat.
enum RecipeMenuStyle { case popUp, menuBar }

/// How hard the press squeezes for a limit: the smaller the file size or
/// pixel limit, the deeper. Both run on a log scale from the jaws just
/// touching the card (80 MB, 8192 px) to the deepest squeeze (500 KB,
/// 640 px), so the presets land at Uploads 0.26, Print 0.37, Share 0.52,
/// Email 0.63, Web 0.89, Small 1, and 4K 0.40, Large 0.55, Web 0.65,
/// Medium 0.78, Thumbnail 1. Shared by the window, the dials, the hover
/// previews and the About window's detents.
enum RecipeScale {
    static func squeeze(bytes: Int) -> Double {
        depth(Double(max(bytes, 1)), from: 80_000_000, to: 500_000)
    }

    static func squeeze(pixels: Int) -> Double {
        depth(Double(max(pixels, 1)), from: 8192, to: 640)
    }

    /// 0 open, `PressView.contact` at `loose`, 1 at `tight` and below.
    private static func depth(_ value: Double, from loose: Double, to tight: Double) -> Double {
        let t = min(max(log(loose / value) / log(loose / tight), 0), 1)
        return PressView.contact + (1 - PressView.contact) * t
    }
}

extension SquishSettings {

    // MARK: - Sentence phrases

    var sizePhrase: String {
        sizeTargetEnabled ? "under \(SizeUnit.label(sizeValue, sizeUnit))" : "any file size"
    }

    var dimensionPhrase: String {
        guard dimensionEnabled else { return "any dimensions" }
        switch dimensionMode {
        case .maxLongSide: return "max \(longSide) px"
        case .maxWidth:    return "max \(maxWidth) px wide"
        case .maxHeight:   return "max \(maxHeight) px tall"
        case .fit:         return "within \(fitWidth) × \(fitHeight)"
        }
    }

    var formatPhrase: String { format.displayName }

    var locationPhrase: String {
        switch outputMode {
        case .auto:   return "next to the originals"
        case .choose: return "in \(Self.shorten(chosenFolder?.lastPathComponent ?? "a folder"))"
        }
    }

    /// Keeps long folder names from stretching the sentence: "Holiday Ph…2026".
    private static func shorten(_ name: String, max: Int = 22) -> String {
        guard name.count > max else { return name }
        let half = (max - 1) / 2
        return "\(name.prefix(half))…\(name.suffix(half))"
    }

    func phrase(for field: RecipeField) -> String {
        switch field {
        case .size:       return sizePhrase
        case .dimensions: return dimensionPhrase
        case .format:     return formatPhrase
        case .location:   return locationPhrase
        }
    }

    /// How deep the press squeezes while a batch runs: the deeper of the two
    /// limits, or the icon's pose when neither is on.
    var pressDepth: Double {
        let size = sizeTargetEnabled ? RecipeScale.squeeze(bytes: targetBytes) : 0
        let pixels = dimensionEnabled ? RecipeScale.squeeze(pixels: activePixels) : 0
        let depth = max(size, pixels)
        return depth > 0 ? depth : PressView.pose
    }

    /// The pixel limit currently in effect, for the dial and previews.
    var activePixels: Int {
        switch dimensionMode {
        case .maxLongSide: return longSide
        case .maxWidth:    return maxWidth
        case .maxHeight:   return maxHeight
        case .fit:         return max(fitWidth, fitHeight)
        }
    }

    // MARK: - Menu options

    func options(for field: RecipeField, style: RecipeMenuStyle, actions: RecipeActions) -> [RecipeOption] {
        switch field {
        case .size:       return sizeOptions(style, actions)
        case .dimensions: return dimensionOptions(style, actions)
        case .format:     return formatOptions()
        case .location:   return locationOptions(actions)
        }
    }

    private func sizeOptions(_ style: RecipeMenuStyle, _ actions: RecipeActions) -> [RecipeOption] {
        var any = RecipeOption.choice("Any File Size", checked: !sizeTargetEnabled,
                                      preview: .init(squeeze: 0, title: "Any file size",
                                                     detail: "High quality, wherever the size lands")) {
            self.sizeTargetEnabled = false
        }
        any.isAny = true
        let presets: [RecipeOption] = sortedSizePresets.map { p in
            RecipeOption.choice(p.name, detail: p.valueLabel,
                                checked: sizeTargetEnabled && p.bytes == targetBytes,
                                preview: .init(squeeze: RecipeScale.squeeze(bytes: p.bytes),
                                               title: "\(p.name) · \(p.valueLabel)",
                                               detail: PresetInfo.blurb(size: p.name))) {
                self.sizeValue = p.value
                self.sizeUnit = p.unit
                self.sizeTargetEnabled = true
            }
        }
        let edit = RecipeOption.command("Edit Presets…",
                                        preview: .init(title: "Edit presets", detail: "Add, rename or remove sizes in Settings")) {
            actions.editPresets(.size)
        }

        var custom = RecipeOption.command("Custom Size…") { actions.editCustom(.size) }
        custom.editsInSentence = true

        switch style {
        case .popUp:
            return [.dial, .separator,
                    .submenu("Presets", preview: .init(title: "Presets", detail: "Uploads, Email, Web and your own"), presets),
                    edit]
        case .menuBar:
            return [any, .separator] + presets + [
                .separator,
                custom,
                edit,
            ]
        }
    }

    private func dimensionOptions(_ style: RecipeMenuStyle, _ actions: RecipeActions) -> [RecipeOption] {
        var any = RecipeOption.choice("Any Dimensions", checked: !dimensionEnabled,
                                      preview: .init(squeeze: 0, title: "Any dimensions", detail: "Keeps every pixel")) {
            self.dimensionEnabled = false
        }
        any.isAny = true
        let presets: [RecipeOption] = sortedDimensionPresets.map { p in
            let o = RecipeOption.choice(p.name, detail: "\(p.pixels) px",
                                        checked: dimensionEnabled && dimensionMode == .maxLongSide && longSide == p.pixels,
                                        preview: .init(squeeze: RecipeScale.squeeze(pixels: p.pixels),
                                                       title: "\(p.name) · \(p.pixels) px",
                                                       detail: PresetInfo.blurb(pixels: p.name))) {
                self.dimensionMode = .maxLongSide
                self.longSide = p.pixels
                self.dimensionEnabled = true
            }
            return o
        }
        var fit = RecipeOption.command("Custom Dimensions…",
                                       preview: .init(title: "Custom dimensions", detail: "Type a long side, width, height, or a box to fit")) {
            actions.editCustom(.dimensions)
        }
        fit.editsInSentence = true
        let edit = RecipeOption.command("Edit Presets…",
                                        preview: .init(title: "Edit presets", detail: "Add, rename or remove sizes in Settings")) {
            actions.editPresets(.dimensions)
        }

        switch style {
        case .popUp:
            return [.dial, .separator,
                    .submenu("Presets", preview: .init(title: "Presets", detail: "4K, Web, Thumbnail and your own"), presets),
                    fit, edit]
        case .menuBar:
            return [any, .separator] + presets + [.separator, fit, edit]
        }
    }

    private func formatOptions() -> [RecipeOption] {
        OutputFormat.allCases.map { f in
            .choice(f.displayName, checked: format == f) { self.format = f }
        }
    }

    private func locationOptions(_ actions: RecipeActions) -> [RecipeOption] {
        var items: [RecipeOption] = [
            .choice("Next to the Originals", checked: outputMode == .auto) { self.outputMode = .auto },
        ]
        if let folder = chosenFolder {
            items.append(.choice(folder.lastPathComponent, detail: folder.deletingLastPathComponent().abbreviatedPath,
                                 checked: outputMode == .choose) { self.outputMode = .choose })
        }
        items.append(.separator)
        items.append(.command(chosenFolder == nil ? "Choose Folder…" : "Choose Another Folder…") {
            Task {
                guard let url = await actions.chooseFolder() else { return }
                self.chosenFolderPath = url.path
                self.outputMode = .choose
            }
        })
        if outputMode == .choose, let folder = chosenFolder {
            items.append(.command("Show Folder in Finder") { Platform.reveal([folder]) })
        }
        return items
    }
}

/// Plain-English purpose for the built-in presets. User-made
/// presets fall back to a generic description.
enum PresetInfo {
    static func blurb(size name: String) -> String {
        switch name.lowercased() {
        case "uploads": return "Fits most upload limits"
        case "print":   return "Plenty for high-quality prints"
        case "share":   return "Messages, Discord and most forms"
        case "email":   return "Comfortable as an attachment"
        case "web":     return "Fast-loading web pages"
        case "small":   return "Chat, forms and thumbnails"
        default:        return "Your preset"
        }
    }

    static func blurb(pixels name: String) -> String {
        switch name.lowercased() {
        case "4k":        return "Big screens and projectors"
        case "large":     return "Sharp on Retina displays"
        case "web":       return "Full-width web images"
        case "medium":    return "Blogs, docs and slides"
        case "thumbnail": return "Previews and avatars"
        default:          return "Your preset"
        }
    }
}

extension URL {
    /// "~/Pictures" style path for display.
    var abbreviatedPath: String { (path as NSString).abbreviatingWithTildeInPath }
}
