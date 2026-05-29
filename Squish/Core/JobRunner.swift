import Foundation
import UniformTypeIdentifiers

/// Orchestrates a batch squish: expands the drop, plans destinations,
/// compresses concurrently, and publishes progress + results to the UI.
@MainActor
final class JobRunner: ObservableObject {
    @Published var isRunning = false
    @Published var progress: Double = 0
    @Published var currentFile = ""
    @Published var totalFiles = 0
    @Published var results: [JobResult] = []
    @Published var hasFinished = false
    @Published var revealRoot: URL?
    @Published var emptyDrop = false

    private let fm = FileManager.default

    func run(input: DropInput, settings: SquishSettings) {
        guard !isRunning else { return }

        let request = CompressionRequest(settings)
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
            let format = ImageCompressor.resolveFormat(source: source, request: request)
            return Job(source: source, format: format, destination: planner.destination(for: source, format: format))
        }

        emptyDrop = false
        hasFinished = false
        isRunning = true
        progress = 0
        totalFiles = jobs.count
        results = []
        currentFile = ""

        Task.detached(priority: .userInitiated) {
            let collected = await JobRunner.process(jobs: jobs, request: request) { done, total, name in
                await MainActor.run {
                    self.progress = Double(done) / Double(max(total, 1))
                    self.currentFile = name
                }
            }
            await MainActor.run {
                self.results = collected
                self.isRunning = false
                self.hasFinished = true
                self.progress = 1
            }
        }
    }

    func reset() {
        results = []
        hasFinished = false
        emptyDrop = false
        progress = 0
        currentFile = ""
        revealRoot = nil
    }

    // MARK: - Batch processing (off the main actor)

    private struct Job: Sendable {
        let source: URL
        let format: OutputFormat
        let destination: URL?
    }

    private nonisolated static func process(
        jobs: [Job],
        request: CompressionRequest,
        progress: @escaping @Sendable (Int, Int, String) async -> Void
    ) async -> [JobResult] {
        let total = jobs.count
        let maxConcurrent = max(1, ProcessInfo.processInfo.activeProcessorCount)
        var collected: [JobResult] = []
        var index = 0

        await withTaskGroup(of: JobResult.self) { group in
            func addNext() {
                guard index < jobs.count else { return }
                let job = jobs[index]
                index += 1
                group.addTask { processOne(job, request: request) }
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

    private nonisolated static func processOne(_ job: Job, request: CompressionRequest) -> JobResult {
        let fm = FileManager.default
        var result = JobResult(source: job.source, status: .success)
        result.originalBytes = (try? job.source.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0

        guard let dest = job.destination else {
            result.status = .failed("No output location.")
            return result
        }

        do {
            let output = try ImageCompressor.compress(source: job.source, request: request)
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try output.data.write(to: dest, options: .atomic)
            result.output = dest
            result.finalBytes = output.data.count
            result.originalSize = output.originalSize
            result.finalSize = output.finalSize
            result.note = output.note
            result.status = .success
        } catch {
            result.status = .failed(error.localizedDescription)
        }
        return result
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
