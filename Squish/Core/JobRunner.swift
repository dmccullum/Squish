import AppKit
import DMKit
import Observation
import UniformTypeIdentifiers

/// Orchestrates a batch squish: expands the drop, plans destinations,
/// compresses concurrently, and publishes progress + results to the UI.
@Observable
final class JobRunner {
    var isRunning = false
    var progress: Double = 0
    var currentFile = ""
    var totalFiles = 0
    var results: [JobResult] = []
    var hasFinished = false
    var revealRoot: URL?
    var emptyDrop = false
    var completed = 0
    var wasCancelled = false

    @ObservationIgnored private let fm = FileManager.default
    @ObservationIgnored private var task: Task<Void, Never>?

    /// The single entry point for files from anywhere: drops, ⌘O, the Dock,
    /// Open With and the Services menu.
    func accept(_ urls: [URL], settings: SquishSettings) {
        guard !isRunning else { NSSound.beep(); return }
        guard let input = DropInput.classify(urls) else { return }
        run(input: input, settings: settings)
    }

    func cancel() {
        task?.cancel()
    }

    func run(input: DropInput, settings: SquishSettings) {
        guard !isRunning else { return }
        let playSound = settings.playSound

        let request = CompressionRequest(settings)
        let strategy = settings.strategy
        let config = OutputConfig(settings)
        let sources = JobRunner.expand(input, fm: fm)

        guard !sources.isEmpty else {
            results = []
            emptyDrop = true
            hasFinished = true
            revealRoot = nil
            return
        }

        let planner = OutputPlanner(input: input, config: config)
        revealRoot = planner.revealRoot

        let jobs: [Job] = sources.map { source in
            let format = ImageCompressor.resolveFormat(request: request)
            return Job(source: source, format: format, destination: planner.destination(for: source, format: format))
        }

        emptyDrop = false
        hasFinished = false
        wasCancelled = false
        isRunning = true
        progress = 0
        completed = 0
        totalFiles = jobs.count
        results = []
        currentFile = jobs.first?.source.lastPathComponent ?? ""
        // A ✓ left from a batch that finished in the background would otherwise
        // clear this batch's count when the app is next activated.
        DockBadge.shared.clear()
        updateDockTile()

        task = Task.detached(priority: .userInitiated) {
            let collected = await JobRunner.process(jobs: jobs, request: request, strategy: strategy) { done, total, name in
                await MainActor.run {
                    self.completed = done
                    self.progress = Double(done) / Double(max(total, 1))
                    self.currentFile = name
                    self.updateDockTile()
                }
            }
            let cancelled = Task.isCancelled
            await MainActor.run {
                self.results = collected
                self.wasCancelled = cancelled
                self.isRunning = false
                self.hasFinished = true
                self.progress = 1
                self.task = nil
                self.finish(playSound: playSound, cancelled: cancelled)
            }
        }
    }

    // MARK: - Dock & sound

    /// A multi-file batch shows its progress on the Dock icon as a bar and a
    /// done/total badge, whether or not Squish is in front.
    private func updateDockTile() {
        guard isRunning, totalFiles > 1 else { return }
        DockProgress.shared.show(progress)
        // TODO(DMKit): DockBadge only badges while the app is inactive; the running
        // count shows in front too, so it sets the tile's badge directly.
        NSApp.dockTile.badgeLabel = "\(completed)/\(totalFiles)"
    }

    private func finish(playSound: Bool, cancelled: Bool) {
        DockProgress.shared.hide()
        NSApp.dockTile.badgeLabel = nil
        guard !cancelled else { return }
        if playSound { NSSound(named: "Pop")?.play() }
        if !NSApp.isActive {
            // Let people know a long batch finished while they were elsewhere.
            // DockBadge clears the ✓ when Squish is activated.
            DockBadge.shared.showWhileInactive("✓")
            NSApp.requestUserAttention(.informationalRequest)
        }
    }

    func reset() {
        results = []
        hasFinished = false
        emptyDrop = false
        wasCancelled = false
        progress = 0
        completed = 0
        currentFile = ""
        revealRoot = nil
    }

    /// Successfully written files, for Show in Finder.
    var outputs: [URL] { results.filter(\.isSuccess).compactMap(\.output) }

    // MARK: - Batch processing (off the main actor)

    private nonisolated struct Job: Sendable {
        let source: URL
        let format: OutputFormat
        let destination: URL?
    }

    private nonisolated static func process(
        jobs: [Job],
        request: CompressionRequest,
        strategy: CompressionStrategy,
        progress: @escaping @Sendable (Int, Int, String) async -> Void
    ) async -> [JobResult] {
        let total = jobs.count

        // "Match quality across batch": find the quality that lands the largest
        // (heaviest) image on target, then reuse it for everyone.
        let overrideQuality: Double?
        if strategy == .matchQuality, request.sizeTargetEnabled, jobs.count > 1,
           let heaviest = jobs.max(by: { fileSize($0.source) < fileSize($1.source) }) {
            overrideQuality = (try? ImageCompressor.compress(source: heaviest.source, request: request))?.qualityUsed
        } else {
            overrideQuality = nil
        }

        let maxConcurrent = max(1, ProcessInfo.processInfo.activeProcessorCount)
        var collected: [JobResult] = []
        var index = 0

        await withTaskGroup(of: JobResult.self) { group in
            func addNext() {
                guard index < jobs.count, !Task.isCancelled else { return }
                let job = jobs[index]
                index += 1
                group.addTask { processOne(job, request: request, overrideQuality: overrideQuality) }
            }
            for _ in 0..<min(maxConcurrent, jobs.count) { addNext() }
            for await result in group {
                collected.append(result)
                await progress(collected.count, total, result.name)
                addNext()
            }
        }

        return collected.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private nonisolated static func processOne(_ job: Job, request: CompressionRequest, overrideQuality: Double?) -> JobResult {
        let fm = FileManager.default
        var result = JobResult(source: job.source, status: .success)
        result.originalBytes = fileSize(job.source)

        guard let dest = job.destination else {
            result.status = .failed("No output location.")
            return result
        }

        do {
            let output = try ImageCompressor.compress(source: job.source, request: request, overrideQuality: overrideQuality)
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)

            let unchangedDimensions = output.finalSize == output.originalSize
            let wouldGrow = output.data.count >= result.originalBytes && result.originalBytes > 0

            if wouldGrow, unchangedDimensions, sameFormat(job.source, output.format) {
                // Re-encoding would only bloat it — keep the original bytes.
                try Data(contentsOf: job.source).write(to: dest, options: .atomic)
                result.finalBytes = result.originalBytes
                result.note = "Already optimized — kept original"
            } else {
                try output.data.write(to: dest, options: .atomic)
                result.finalBytes = output.data.count
                result.note = wouldGrow ? "Larger as \(output.format.displayName)" : output.note
            }
            result.output = dest
            result.originalSize = output.originalSize
            result.finalSize = output.finalSize
            result.status = .success
        } catch {
            result.status = .failed(error.localizedDescription)
        }
        return result
    }

    private nonisolated static func fileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
    }

    private nonisolated static func sameFormat(_ url: URL, _ format: OutputFormat) -> Bool {
        let ext = url.pathExtension.lowercased()
        switch format {
        case .jpeg: return ext == "jpg" || ext == "jpeg"
        case .heic: return ext == "heic" || ext == "heif"
        }
    }

    // MARK: - Expansion

    private nonisolated static func expand(_ input: DropInput, fm: FileManager) -> [URL] {
        switch input {
        case .single(let url):
            return isImage(url) ? [url] : []
        case .group(let urls):
            return urls.flatMap { url -> [URL] in
                url.isDirectory ? imagesInDirectory(url, fm: fm) : (isImage(url) ? [url] : [])
            }
        case .folder(let url):
            return imagesInDirectory(url, fm: fm)
        }
    }

    private nonisolated static func imagesInDirectory(_ dir: URL, fm: FileManager) -> [URL] {
        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var found: [URL] = []
        for case let url as URL in enumerator where isImage(url) {
            found.append(url)
        }
        return found
    }

    private nonisolated static func isImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return false }
        return type.conforms(to: .image)
    }
}
