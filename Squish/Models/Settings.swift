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

    /// "1 MB", "2.5 MB", "500 KB".
    static func label(_ value: Double, _ unit: SizeUnit) -> String {
        let v = value.rounded() == value ? String(Int(value)) : String(value)
        return "\(v) \(unit.rawValue)"
    }
}

/// How a multi-image batch is compressed.
enum CompressionStrategy: String, CaseIterable, Identifiable, Codable {
    case prioritizeSize, matchQuality
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .prioritizeSize: return "Same file size"
        case .matchQuality:   return "Same quality setting"
        }
    }
    var detail: String {
        switch self {
        case .prioritizeSize:
            return "Every image is squished to the same target file size."
        case .matchQuality:
            return "Find the quality that lands the largest image on target, then apply that same quality to every image."
        }
    }
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
    var bytes: Int { Int((value * Double(unit.multiplier)).rounded()) }
    var valueLabel: String { SizeUnit.label(value, unit) }
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

    // Format — always applied (the output is always JPEG or HEIC).
    @Published var format: OutputFormat      { didSet { save() } }

    // Output placement
    @Published var outputMode: OutputMode    { didSet { save() } }
    @Published var chosenFolderPath: String  { didSet { save() } }

    // Preferences (Settings window)
    @Published var strategy: CompressionStrategy      { didSet { save() } }
    @Published var dimensionPresets: [DimensionPreset] { didSet { save() } }
    @Published var sizePresets: [SizePreset]           { didSet { save() } }
    @Published var playSound: Bool                     { didSet { save() } }

    /// Default auto-naming suffix for single files and containers.
    let suffix = " (squished)"

    /// Target size in bytes (decimal KB/MB to match Finder's display).
    var targetBytes: Int { Int((sizeValue * Double(sizeUnit.multiplier)).rounded()) }

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
            // First run: File size on (1 MB). Format always applies.
            "sizeTargetEnabled": true,
            "playSound": true,
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
        format           = OutputFormat(rawValue: d.string(forKey: "format") ?? "") ?? .jpeg
        outputMode       = OutputMode(rawValue: d.string(forKey: "outputMode") ?? "") ?? .auto
        chosenFolderPath = d.string(forKey: "chosenFolderPath") ?? ""
        strategy         = CompressionStrategy(rawValue: d.string(forKey: "strategy") ?? "") ?? .prioritizeSize
        dimensionPresets = Self.decode([DimensionPreset].self, d.data(forKey: "dimensionPresets"))
            ?? SquishSettings.defaultDimensionPresets
        sizePresets      = Self.migrated(Self.decode([SizePreset].self, d.data(forKey: "sizePresets"))
            ?? SquishSettings.defaultSizePresets)
        playSound        = d.bool(forKey: "playSound")
    }

    static let defaultDimensionPresets: [DimensionPreset] = [
        .init(name: "4K", pixels: 4096),
        .init(name: "Large", pixels: 2560),
        .init(name: "Web", pixels: 1920),
        .init(name: "Medium", pixels: 1280),
        .init(name: "Thumbnail", pixels: 640),
    ]
    static let defaultSizePresets: [SizePreset] = [
        .init(name: "Uploads", value: 50, unit: .mb),
        .init(name: "Print", value: 25, unit: .mb),
        .init(name: "Email", value: 5, unit: .mb),
        .init(name: "Web", value: 1, unit: .mb),
        .init(name: "Small", value: 500, unit: .kb),
    ]

    /// Presets sorted largest → smallest for display.
    var sortedSizePresets: [SizePreset] { sizePresets.sorted { $0.bytes > $1.bytes } }
    var sortedDimensionPresets: [DimensionPreset] { dimensionPresets.sorted { $0.pixels > $1.pixels } }

    /// "Canva · 50 MB" was Canva's upload ceiling, not a recommendation; it
    /// shipped under that name before 2026-10, so rename untouched copies.
    private static func migrated(_ presets: [SizePreset]) -> [SizePreset] {
        presets.map { p in
            var p = p
            if p.name == "Canva", p.bytes == 50_000_000 { p.name = "Uploads" }
            return p
        }
    }

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
        d.set(format.rawValue, forKey: "format")
        d.set(outputMode.rawValue, forKey: "outputMode")
        d.set(chosenFolderPath, forKey: "chosenFolderPath")
        d.set(strategy.rawValue, forKey: "strategy")
        d.set(try? JSONEncoder().encode(dimensionPresets), forKey: "dimensionPresets")
        d.set(try? JSONEncoder().encode(sizePresets), forKey: "sizePresets")
        d.set(playSound, forKey: "playSound")
    }
}
