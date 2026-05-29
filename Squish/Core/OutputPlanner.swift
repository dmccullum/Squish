import Foundation

/// Value snapshot of placement-related settings.
struct OutputConfig {
    var suffix: String
    var outputMode: OutputMode
    var chosenFolder: URL?

    @MainActor init(_ s: SquishSettings) {
        suffix = s.suffix
        outputMode = s.outputMode
        chosenFolder = s.chosenFolder
    }
}

/// Computes destination URLs for a batch, mirroring how the drop arrived.
/// Use serially — it reserves names to avoid intra-batch collisions.
final class OutputPlanner {
    private let input: DropInput
    private let config: OutputConfig
    private let containerDir: URL?
    private let folderRoot: URL?
    private var reserved = Set<String>()
    private let fm = FileManager.default

    init(input: DropInput, config: OutputConfig) {
        self.input = input
        self.config = config
        let (container, root) = OutputPlanner.resolveContainer(input: input, config: config)
        self.folderRoot = root
        self.containerDir = container.map { OutputPlanner.uniqueDirectory($0) }
    }

    /// The top-level folder we'll be writing into (for "Reveal in Finder").
    var revealRoot: URL? {
        switch input {
        case .single: return containerDir
        case .group, .folder: return containerDir
        }
    }

    /// Destination URL for a single source file at its resolved format.
    func destination(for source: URL, format: OutputFormat) -> URL? {
        guard let containerDir else { return nil }
        let base = source.deletingPathExtension().lastPathComponent
        let ext = format.fileExtension

        let proposed: URL
        switch input {
        case .single:
            proposed = containerDir.appendingPathComponent(base + config.suffix + "." + ext)
        case .group:
            proposed = containerDir.appendingPathComponent(base + "." + ext)
        case .folder:
            let relDir = relativeDirectory(of: source)
            proposed = containerDir
                .appendingPathComponent(relDir, isDirectory: true)
                .appendingPathComponent(base + "." + ext)
        }
        return reserveUnique(proposed)
    }

    // MARK: - Container resolution

    private static func resolveContainer(input: DropInput, config: OutputConfig) -> (URL?, URL?) {
        switch config.outputMode {
        case .choose:
            guard let base = config.chosenFolder else { return (nil, nil) }
            switch input {
            case .single, .group:
                return (base, nil)
            case .folder(let f):
                return (base.appendingPathComponent(f.lastPathComponent, isDirectory: true), f)
            }
        case .auto:
            switch input {
            case .single(let u):
                return (u.deletingLastPathComponent(), nil)
            case .group(let urls):
                let parent = commonParent(of: urls) ?? urls[0].deletingLastPathComponent()
                return (parent.appendingPathComponent("Squished", isDirectory: true), nil)
            case .folder(let f):
                let sibling = f.deletingLastPathComponent()
                    .appendingPathComponent(f.lastPathComponent + config.suffix, isDirectory: true)
                return (sibling, f)
            }
        }
    }

    private static func commonParent(of urls: [URL]) -> URL? {
        let parents = urls.map { $0.deletingLastPathComponent().standardizedFileURL.pathComponents }
        guard var prefix = parents.first else { return nil }
        for comps in parents.dropFirst() {
            var i = 0
            while i < prefix.count, i < comps.count, prefix[i] == comps[i] { i += 1 }
            prefix = Array(prefix.prefix(i))
        }
        guard !prefix.isEmpty else { return nil }
        return URL(fileURLWithPath: NSString.path(withComponents: prefix), isDirectory: true)
    }

    // MARK: - Paths & uniqueness

    private func relativeDirectory(of source: URL) -> String {
        guard let folderRoot else { return "" }
        let rootComps = folderRoot.standardizedFileURL.pathComponents
        let dirComps = source.deletingLastPathComponent().standardizedFileURL.pathComponents
        guard dirComps.count > rootComps.count else { return "" }
        return dirComps.suffix(from: rootComps.count).joined(separator: "/")
    }

    private func reserveUnique(_ url: URL) -> URL {
        let dir = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent

        var candidate = url
        var n = 2
        while reserved.contains(candidate.standardizedFileURL.path.lowercased())
                || fm.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(stem) \(n).\(ext)")
            n += 1
        }
        reserved.insert(candidate.standardizedFileURL.path.lowercased())
        return candidate
    }

    private static func uniqueDirectory(_ url: URL) -> URL {
        let fm = FileManager.default
        var candidate = url
        var n = 2
        let parent = url.deletingLastPathComponent()
        let name = url.lastPathComponent
        while fm.fileExists(atPath: candidate.path) {
            candidate = parent.appendingPathComponent("\(name) \(n)", isDirectory: true)
            n += 1
        }
        return candidate
    }
}
