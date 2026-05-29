import Foundation

/// How a drop arrived, which determines the default (auto) output placement.
enum DropInput {
    case single(URL)          // one image file → sibling, renamed
    case group([URL])         // several items  → "Squished" subfolder in common parent
    case folder(URL)          // one folder     → sibling "<name> (squished)" folder

    /// Classify a set of dropped URLs. Returns nil if nothing usable was dropped.
    static func classify(_ urls: [URL]) -> DropInput? {
        let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { return nil }

        if existing.count == 1 {
            let url = existing[0]
            return url.isDirectory ? .folder(url) : .single(url)
        }
        return .group(existing)
    }
}

extension URL {
    var isDirectory: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }
}
