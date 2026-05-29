import Foundation
import UniformTypeIdentifiers

/// Output image format. Native, lossy, ImageIO-encodable formats only.
enum OutputFormat: String, CaseIterable, Identifiable, Codable {
    case jpeg, heic
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .jpeg: return "JPEG"
        case .heic: return "HEIC"
        }
    }

    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .heic: return "heic"
        }
    }

    var utType: UTType {
        switch self {
        case .jpeg: return .jpeg
        case .heic: return UTType("public.heic") ?? .heic
        }
    }
}

enum DimensionMode: String, CaseIterable, Identifiable, Codable {
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
    var shortName: String {
        switch self {
        case .maxLongSide: return "Long side"
        case .maxWidth:    return "Width"
        case .maxHeight:   return "Height"
        case .fit:         return "Fit"
        }
    }
}

enum OutputMode: String, CaseIterable, Identifiable, Codable {
    case auto, choose
    var id: String { rawValue }
}

enum SizeUnit: String, CaseIterable, Identifiable, Codable {
    case kb = "KB", mb = "MB"
    var id: String { rawValue }
    var multiplier: Int { self == .mb ? 1_000_000 : 1_000 }
}

/// How a multi-image batch is compressed.
enum CompressionStrategy: String, CaseIterable, Identifiable, Codable {
    case prioritizeSize, matchQuality
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .prioritizeSize: return "Prioritize file size"
        case .matchQuality:   return "Match quality across batch"
        }
    }
    var detail: String {
        switch self {
        case .prioritizeSize:
            return "Every image is squished to the target individually."
        case .matchQuality:
            return "Find the quality that lands the largest image on target, then apply it to all so they look consistent."
        }
    }
}

/// Which on-screen control treatment to use for the three knobs.
enum ControlStyle: String, CaseIterable, Identifiable, Codable {
    case popover, dial
    var id: String { rawValue }
    var displayName: String { self == .popover ? "Popovers & sliders" : "Rotary dials" }
}

/// A named max-long-side pixel preset.
struct DimensionPreset: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var name: String
    var pixels: Int
}

/// A named file-size limit preset.
struct SizePreset: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var name: String
    var value: Double
    var unit: SizeUnit
    var bytes: Int { Int(value) * unit.multiplier }
    var valueLabel: String {
        let v = value.rounded() == value ? String(Int(value)) : String(value)
        return "\(v) \(unit.rawValue)"
    }
}

/// User-facing, persisted configuration. Backed by `UserDefaults`.
@MainActor
final class SquishSettings: ObservableObject {
    // File-size target
    @Published var sizeTargetEnabled: Bool { didSet { save() } }
    @Published var sizeValue: Double         { didSet { save() } }
    @Published var sizeUnit: SizeUnit        { didSet { save() } }

    // Dimension target
    @Published var dimensionEnabled: Bool    { didSet { save() } }
    @Published var dimensionMode: DimensionMode { didSet { save() } }
    @Published var longSide: Int             { didSet { save() } }
    @Published var maxWidth: Int             { didSet { save() } }
    @Published var maxHeight: Int            { didSet { save() } }
    @Published var fitWidth: Int             { didSet { save() } }
    @Published var fitHeight: Int            { didSet { save() } }

    // Format (per-job override of the default)
    @Published var formatEnabled: Bool       { didSet { save() } }
    @Published var format: OutputFormat      { didSet { save() } }

    // Output placement
    @Published var outputMode: OutputMode    { didSet { save() } }
    @Published var chosenFolderPath: String  { didSet { save() } }

    // Preferences (Settings window)
    @Published var defaultFormat: OutputFormat       { didSet { save() } }
    @Published var strategy: CompressionStrategy      { didSet { save() } }
    @Published var controlStyle: ControlStyle         { didSet { save() } }
    @Published var dimensionPresets: [DimensionPreset] { didSet { save() } }
    @Published var sizePresets: [SizePreset]           { didSet { save() } }

    /// Default auto-naming suffix for single files and containers.
    let suffix = " (squished)"

    /// At least one transform must be active before we can process.
    var isActionable: Bool { sizeTargetEnabled || dimensionEnabled || formatEnabled }

    /// Target size in bytes (decimal KB/MB to match Finder's display).
    var targetBytes: Int { Int(sizeValue) * sizeUnit.multiplier }

    /// The format used when the per-job Format toggle is off.
    var effectiveFormat: OutputFormat { formatEnabled ? format : defaultFormat }

    var chosenFolder: URL? {
        chosenFolderPath.isEmpty ? nil : URL(fileURLWithPath: chosenFolderPath, isDirectory: true)
    }

    private let d = UserDefaults.standard

    init() {
        d.register(defaults: [
            "sizeValue": 1.0,
            "sizeUnit": SizeUnit.mb.rawValue,
            "longSide": 2048, "maxWidth": 1920, "maxHeight": 1080,
            "fitWidth": 1920, "fitHeight": 1080,
            // Sensible first-run preset so a drop works immediately.
            "dimensionEnabled": true,
            "formatEnabled": false,
        ])
        sizeTargetEnabled = d.bool(forKey: "sizeTargetEnabled")
        sizeValue        = d.double(forKey: "sizeValue")
        sizeUnit         = SizeUnit(rawValue: d.string(forKey: "sizeUnit") ?? "MB") ?? .mb
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
        defaultFormat    = OutputFormat(rawValue: d.string(forKey: "defaultFormat") ?? "") ?? .jpeg
        strategy         = CompressionStrategy(rawValue: d.string(forKey: "strategy") ?? "") ?? .prioritizeSize
        controlStyle     = ControlStyle(rawValue: d.string(forKey: "controlStyle") ?? "") ?? .popover
        dimensionPresets = Self.decode([DimensionPreset].self, d.data(forKey: "dimensionPresets"))
            ?? SquishSettings.defaultDimensionPresets
        sizePresets      = Self.decode([SizePreset].self, d.data(forKey: "sizePresets"))
            ?? SquishSettings.defaultSizePresets
    }

    static let defaultDimensionPresets: [DimensionPreset] = [
        .init(name: "Original-ish", pixels: 4096),
        .init(name: "Large", pixels: 2560),
        .init(name: "Web", pixels: 1920),
        .init(name: "Medium", pixels: 1280),
        .init(name: "Thumbnail", pixels: 640),
    ]
    static let defaultSizePresets: [SizePreset] = [
        .init(name: "Email", value: 5, unit: .mb),
        .init(name: "Web", value: 1, unit: .mb),
        .init(name: "Small", value: 500, unit: .kb),
    ]

    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
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
        d.set(defaultFormat.rawValue, forKey: "defaultFormat")
        d.set(strategy.rawValue, forKey: "strategy")
        d.set(controlStyle.rawValue, forKey: "controlStyle")
        d.set(try? JSONEncoder().encode(dimensionPresets), forKey: "dimensionPresets")
        d.set(try? JSONEncoder().encode(sizePresets), forKey: "sizePresets")
    }
}
