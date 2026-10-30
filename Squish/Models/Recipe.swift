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
    var photoScale: Double?
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

/// How hard the press squeezes for a byte target, and how big the photo is
/// for a pixel target. Shared by the dial and the hover previews.
enum RecipeScale {
    static func squeeze(bytes: Int) -> Double {
        let hi = log(50_000_000.0), lo = log(300_000.0)
        return min(1, max(0.08, (hi - log(Double(max(bytes, 1)))) / (hi - lo)))
    }
    static func photoScale(pixels: Int) -> Double {
        0.42 + 0.58 * (min(Double(pixels), 4096) / 4096).squareRoot()
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
                                      preview: .init(photoScale: 1, title: "Any dimensions", detail: "Keeps every pixel")) {
            self.dimensionEnabled = false
        }
        any.isAny = true
        let presets: [RecipeOption] = sortedDimensionPresets.map { p in
            let o = RecipeOption.choice(p.name, detail: "\(p.pixels) px",
                                        checked: dimensionEnabled && dimensionMode == .maxLongSide && longSide == p.pixels,
                                        preview: .init(photoScale: RecipeScale.photoScale(pixels: p.pixels),
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
