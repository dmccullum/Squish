import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

/// A value-type snapshot of the settings, safe to pass to background work.
struct CompressionRequest {
    var sizeTargetEnabled: Bool
    var targetBytes: Int
    var dimensionEnabled: Bool
    var dimensionMode: DimensionMode
    var longSide: Int
    var maxWidth: Int
    var maxHeight: Int
    var fitWidth: Int
    var fitHeight: Int
    var formatEnabled: Bool
    var format: OutputFormat
    var defaultFormat: OutputFormat

    @MainActor init(_ s: SquishSettings) {
        sizeTargetEnabled = s.sizeTargetEnabled
        targetBytes = s.targetBytes
        dimensionEnabled = s.dimensionEnabled
        dimensionMode = s.dimensionMode
        longSide = s.longSide
        maxWidth = s.maxWidth
        maxHeight = s.maxHeight
        fitWidth = s.fitWidth
        fitHeight = s.fitHeight
        formatEnabled = s.formatEnabled
        format = s.format
        defaultFormat = s.defaultFormat
    }
}

struct CompressionOutput {
    var data: Data
    var format: OutputFormat
    var originalSize: CGSize
    var finalSize: CGSize
    var qualityUsed: Double
    var note: String?
}

enum CompressError: LocalizedError {
    case cannotRead
    case cannotEncode

    var errorDescription: String? {
        switch self {
        case .cannotRead:   return "Couldn't read the image."
        case .cannotEncode: return "Couldn't encode the image."
        }
    }
}

/// Stateless image-compression engine built on ImageIO / CoreGraphics.
enum ImageCompressor {
    private static let minLongSide: CGFloat = 64
    private static let qualityIterations = 8
    private static let maxDownscaleSteps = 6
    private static let downscaleFactor: CGFloat = 0.85
    static let defaultQuality = 0.85

    /// The concrete output format: explicit per-job choice, else the default.
    static func resolveFormat(request: CompressionRequest) -> OutputFormat {
        request.formatEnabled ? request.format : request.defaultFormat
    }

    /// Compress one image. If `overrideQuality` is given, that exact quality is
    /// used (no size-target search) — used to keep a batch visually consistent.
    static func compress(source: URL, request: CompressionRequest, overrideQuality: Double? = nil) throws -> CompressionOutput {
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil),
              CGImageSourceGetCount(src) > 0 else { throw CompressError.cannotRead }

        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let pw = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let ph = props?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let maxDim = max(pw, ph, 1)

        // Decode at full size while baking in EXIF orientation.
        let decodeOpts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDim,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(src, 0, decodeOpts as CFDictionary) else {
            throw CompressError.cannotRead
        }

        let originalSize = CGSize(width: decoded.width, height: decoded.height)
        let format = resolveFormat(request: request)

        // Apply the dimension target up front (never upscales).
        var working = decoded
        let target = targetSize(for: originalSize, request: request)
        if target != originalSize, let resized = resize(decoded, to: target) {
            working = resized
        }

        // Fixed-quality path (batch consistency).
        if let q = overrideQuality {
            guard let data = encode(working, format: format, quality: q) else { throw CompressError.cannotEncode }
            return CompressionOutput(data: data, format: format, originalSize: originalSize,
                                     finalSize: CGSize(width: working.width, height: working.height),
                                     qualityUsed: q, note: nil)
        }

        // No size target: encode at a high default quality.
        guard request.sizeTargetEnabled else {
            guard let data = encode(working, format: format, quality: defaultQuality) else { throw CompressError.cannotEncode }
            return CompressionOutput(data: data, format: format, originalSize: originalSize,
                                     finalSize: CGSize(width: working.width, height: working.height),
                                     qualityUsed: defaultQuality, note: nil)
        }

        // Size target: search quality, downscaling if the floor still overshoots.
        var resultData: Data?
        var resultQuality = 0.0
        for step in 0...maxDownscaleSteps {
            let (data, quality, fits) = searchQuality(working, format: format, target: request.targetBytes)
            let longSide = CGFloat(max(working.width, working.height))
            if fits || longSide <= minLongSide || step == maxDownscaleSteps {
                resultData = data
                resultQuality = quality
                break
            }
            guard let smaller = resize(working, to: scaled(CGSize(width: working.width, height: working.height), by: downscaleFactor)) else {
                resultData = data; resultQuality = quality; break
            }
            working = smaller
        }

        guard let data = resultData else { throw CompressError.cannotEncode }
        return CompressionOutput(data: data, format: format, originalSize: originalSize,
                                 finalSize: CGSize(width: working.width, height: working.height),
                                 qualityUsed: resultQuality, note: nil)
    }

    // MARK: - Encoding

    /// Binary-searches quality for the highest setting whose encoded size fits
    /// the target. Returns the chosen data, the quality, and whether it fit.
    private static func searchQuality(_ image: CGImage, format: OutputFormat, target: Int) -> (Data, Double, Bool) {
        var lo = 0.0, hi = 1.0
        var best: (Data, Double)?
        var smallest: (Data, Double)?

        for _ in 0..<qualityIterations {
            let mid = (lo + hi) / 2
            guard let data = encode(image, format: format, quality: mid) else { break }
            if smallest == nil || data.count < smallest!.0.count { smallest = (data, mid) }
            if data.count <= target {
                best = (data, mid)
                lo = mid
            } else {
                hi = mid
            }
        }

        if let best { return (best.0, best.1, true) }
        let fallback = smallest ?? (encode(image, format: format, quality: 0.0) ?? Data(), 0.0)
        return (fallback.0, fallback.1, false)
    }

    private static func encode(_ image: CGImage, format: OutputFormat, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, format.utType.identifier as CFString, 1, nil) else {
            return nil
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    // MARK: - Resizing

    private static func resize(_ image: CGImage, to size: CGSize) -> CGImage? {
        let w = Int(size.width.rounded()), h = Int(size.height.rounded())
        guard w > 0, h > 0 else { return nil }
        if w == image.width, h == image.height { return image }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    private static func scaled(_ size: CGSize, by factor: CGFloat) -> CGSize {
        CGSize(width: floor(size.width * factor), height: floor(size.height * factor))
    }

    private static func targetSize(for original: CGSize, request: CompressionRequest) -> CGSize {
        guard request.dimensionEnabled else { return original }
        let w = original.width, h = original.height
        guard w > 0, h > 0 else { return original }

        switch request.dimensionMode {
        case .maxLongSide:
            let m = CGFloat(request.longSide), long = max(w, h)
            guard long > m else { return original }
            return scaled(original, by: m / long)
        case .maxWidth:
            let m = CGFloat(request.maxWidth)
            guard w > m else { return original }
            return scaled(original, by: m / w)
        case .maxHeight:
            let m = CGFloat(request.maxHeight)
            guard h > m else { return original }
            return scaled(original, by: m / h)
        case .fit:
            let s = min(CGFloat(request.fitWidth) / w, CGFloat(request.fitHeight) / h, 1)
            guard s < 1 else { return original }
            return scaled(original, by: s)
        }
    }
}
