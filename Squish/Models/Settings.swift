import Foundation
import UniformTypeIdentifiers

/// Output image format. Native ImageIO-encodable formats only.
enum OutputFormat: String, CaseIterable, Identifiable {
    case jpeg, heic, png
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .jpeg: return "JPEG"
        case .heic: return "HEIC"
        case .png:  return "PNG"
        }
    }

    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .heic: return "heic"
        case .png:  return "png"
        }
    }

    var utType: UTType {
        switch self {
        case .jpeg: return .jpeg
        case .heic: return UTType("public.heic") ?? .heic
        case .png:  return .png
        }
    }

    /// Lossy formats accept a 0...1 quality and can be size-targeted by quality search.
    var isLossy: Bool { self != .png }
}

enum DimensionMode: String, CaseIterable, Identifiable {
    case maxLongSide, maxWidth, maxHeight, fit
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .maxLongSide: return "Max long side"
        case .maxWidth:    return "Max width"
        case .maxHeight:   return "Max height"
        case .fit:         return "Fit within W×H"
        }
    }
}

enum OutputMode: String, CaseIterable, Identifiable {
    case auto, choose
    var id: String { rawValue }
}

enum SizeUnit: String, CaseIterable, Identifiable {
    case kb = "KB", mb = "MB"
    var id: String { rawValue }
    var multiplier: Int { self == .mb ? 1_000_000 : 1_000 }
}

/// User-facing, persisted configuration. Backed by `UserDefaults`.
@MainActor
final class SquishSettings: ObservableObject {
    // File-size target
    @Published var sizeTargetEnabled: Bool { didSet { save() } }
    @Published var sizeValue: Double        { didSet { save() } }
    @Published var sizeUnit: SizeUnit        { didSet { save() } }

    // Dimension target
    @Published var dimensionEnabled: Bool   { didSet { save() } }
    @Published var dimensionMode: DimensionMode { didSet { save() } }
    @Published var longSide: Int            { didSet { save() } }
    @Published var maxWidth: Int            { didSet { save() } }
    @Published var maxHeight: Int           { didSet { save() } }
    @Published var fitWidth: Int            { didSet { save() } }
    @Published var fitHeight: Int           { didSet { save() } }

    // Format
    @Published var formatEnabled: Bool      { didSet { save() } }
    @Published var format: OutputFormat     { didSet { save() } }

    // Output placement
    @Published var outputMode: OutputMode   { didSet { save() } }
    @Published var chosenFolderPath: String { didSet { save() } }

    /// Default auto-naming suffix for single files and containers.
    let suffix = " (squished)"

    /// At least one transform must be active before we can process.
    var isActionable: Bool { sizeTargetEnabled || dimensionEnabled || formatEnabled }

    /// Target size in bytes (decimal KB/MB to match Finder's display).
    var targetBytes: Int { Int(sizeValue) * sizeUnit.multiplier }

    var chosenFolder: URL? {
        chosenFolderPath.isEmpty ? nil : URL(fileURLWithPath: chosenFolderPath, isDirectory: true)
    }

    private let d = UserDefaults.standard

    init() {
        d.register(defaults: [
            "sizeValue": 500.0,
            "longSide": 2048, "maxWidth": 1920, "maxHeight": 1080,
            "fitWidth": 1920, "fitHeight": 1080,
            // Sensible first-run preset so a drop works immediately:
            // scale to a max long side of 2048 and convert to JPEG.
            "dimensionEnabled": true,
            "formatEnabled": true,
        ])
        sizeTargetEnabled = d.bool(forKey: "sizeTargetEnabled")
        sizeValue        = d.double(forKey: "sizeValue")
        sizeUnit         = SizeUnit(rawValue: d.string(forKey: "sizeUnit") ?? "KB") ?? .kb
        dimensionEnabled = d.bool(forKey: "dimensionEnabled")
        dimensionMode    = DimensionMode(rawValue: d.string(forKey: "dimensionMode") ?? "") ?? .maxLongSide
        longSide         = d.integer(forKey: "longSide")
        maxWidth         = d.integer(forKey: "maxWidth")
        maxHeight        = d.integer(forKey: "maxHeight")
        fitWidth         = d.integer(forKey: "fitWidth")
        fitHeight        = d.integer(forKey: "fitHeight")
        formatEnabled    = d.bool(forKey: "formatEnabled")
        format           = OutputFormat(rawValue: d.string(forKey: "format") ?? "") ?? .jpeg
        outputMode       = OutputMode(rawValue: d.string(forKey: "outputMode") ?? "") ?? .auto
        chosenFolderPath = d.string(forKey: "chosenFolderPath") ?? ""
    }

    private func save() {
        d.set(sizeTargetEnabled, forKey: "sizeTargetEnabled")
        d.set(sizeValue, forKey: "sizeValue")
        d.set(sizeUnit.rawValue, forKey: "sizeUnit")
        d.set(dimensionEnabled, forKey: "dimensionEnabled")
        d.set(dimensionMode.rawValue, forKey: "dimensionMode")
        d.set(longSide, forKey: "longSide")
        d.set(maxWidth, forKey: "maxWidth")
        d.set(maxHeight, forKey: "maxHeight")
        d.set(fitWidth, forKey: "fitWidth")
        d.set(fitHeight, forKey: "fitHeight")
        d.set(formatEnabled, forKey: "formatEnabled")
        d.set(format.rawValue, forKey: "format")
        d.set(outputMode.rawValue, forKey: "outputMode")
        d.set(chosenFolderPath, forKey: "chosenFolderPath")
    }
}
