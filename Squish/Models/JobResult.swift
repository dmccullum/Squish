import Foundation
import CoreGraphics

/// The outcome of squishing a single file.
struct JobResult: Identifiable {
    enum Status {
        case success
        case skipped(String)
        case failed(String)
    }

    let id = UUID()
    let source: URL
    var output: URL?
    var originalBytes: Int = 0
    var finalBytes: Int = 0
    var originalSize: CGSize?
    var finalSize: CGSize?
    var status: Status
    var note: String?

    var name: String { source.lastPathComponent }

    var savedBytes: Int { max(0, originalBytes - finalBytes) }

    var savedPercent: Double {
        guard originalBytes > 0 else { return 0 }
        return Double(originalBytes - finalBytes) / Double(originalBytes) * 100
    }

    var isSuccess: Bool {
        if case .success = status { return true }
        return false
    }
}

/// Human-readable byte formatting (decimal, Finder-style).
enum ByteFormat {
    static func string(_ bytes: Int) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: Int64(bytes))
    }
}
