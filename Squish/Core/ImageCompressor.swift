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
    }
}

struct CompressionOutput {
    var data: Data
    var format: OutputFormat
    var originalSize: CGSize
    var finalSize: CGSize
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
    private static let defaultQuality = 0.85

    /// The concrete output format for a source: explicit choice, else keep the
    /// original when it's natively encodable, else fall back to JPEG.
    static func resolveFormat(source: URL, request: CompressionRequest) -> OutputFormat {
        if request.formatEnabled { return request.format }
        switch source.pathExtension.lowercased() {
        case "png":          return .png
        case "heic", "heif": return .heic
        default:             return .jpeg
        }
    }

    static func compress(source: URL, request: CompressionRequest) throws -> CompressionOutput {
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
        let format = resolveFormat(source: source, request: request)

        // Apply the dimension target up front.
        var working = decoded
        let target = targetSize(for: originalSize, request: request)
        if target != originalSize, let resized = resize(decoded, to: target) {
            working = resized
        }

        let byteTarget: Int? = request.sizeTargetEnabled ? request.targetBytes : nil
        var note: String?
        var resultData: Data?

        for step in 0...maxDownscaleSteps {
            let longSide = CGFloat(max(working.width, working.height))

            if format.isLossy {
                if let byteTarget {
                    let (data, fits) = bestQualityData(working, format: format, target: byteTarget)
                    if fits || longSide <= minLongSide || step == maxDownscaleSteps {
                        resultData = data
                        break
                    }
                } else {
                    resultData = encode(working, format: format, quality: defaultQuality)
                    break
                }
            } else { // PNG — lossless, can only approach a target by resizing.
                guard let data = encode(working, format: format, quality: nil) else {
                    throw CompressError.cannotEncode
                }
                resultData = data
                if let byteTarget, data.count > byteTarget,
                   longSide > minLongSide, step < maxDownscaleSteps {
                    note = "PNG is lossless — resized to approach the target."
                } else {
                    break
                }
            }

            // Still over target: downscale and try again.
            if let smaller = resize(working, to: scaled(CGSize(width: working.width, height: working.height),
                                                        by: downscaleFactor)) {
                working = smaller
            } else {
                break
            }
        }

        guard let data = resultData else { throw CompressError.cannotEncode }
        return CompressionOutput(
            data: data,
            format: format,
            originalSize: originalSize,
            finalSize: CGSize(width: working.width, height: working.height),
            note: note
        )
    }

    // MARK: - Encoding

    /// Binary-searches quality for the highest setting whose encoded size fits
    /// the target. Returns the chosen data and whether it actually fit.
    private static func bestQualityData(_ image: CGImage, format: OutputFormat, target: Int) -> (Data, Bool) {
        var lo = 0.0, hi = 1.0
        var best: Data?
        var smallest: Data?

        for _ in 0..<qualityIterations {
            let mid = (lo + hi) / 2
            guard let data = encode(image, format: format, quality: mid) else { break }
            if smallest == nil || data.count < (smallest?.count ?? .max) { smallest = data }
            if data.count <= target {
                best = data
                lo = mid
            } else {
                hi = mid
            }
        }

        if let best { return (best, true) }
        // Nothing fit; hand back the smallest we managed (caller may downscale).
        let fallback = smallest ?? encode(image, format: format, quality: 0.0) ?? Data()
        return (fallback, false)
    }

    private static func encode(_ image: CGImage, format: OutputFormat, quality: Double?) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, format.utType.identifier as CFString, 1, nil) else {
            return nil
        }
        var options: [CFString: Any] = [:]
        if let quality { options[kCGImageDestinationLossyCompressionQuality] = quality }
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
