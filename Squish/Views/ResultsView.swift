import SwiftUI
import QuickLook
import QuickLookThumbnailing

/// The selected results, published to the File and Edit menus.
struct ResultSelection {
    var urls: [URL]
    var quickLook: () -> Void
}

extension FocusedValues {
    @Entry var resultSelection: ResultSelection?
}

struct ResultsView: View {
    @Environment(JobRunner.self) private var runner
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var released = false
    @State private var shownPercent = 0.0
    @State private var selection = Set<JobResult.ID>()
    @State private var preview: URL?

    private var successes: [JobResult] { runner.results.filter(\.isSuccess) }
    private var failures: [JobResult] { runner.results.filter { !$0.isSuccess } }
    private var totalOriginal: Int { successes.reduce(0) { $0 + $1.originalBytes } }
    private var totalFinal: Int { successes.reduce(0) { $0 + $1.finalBytes } }
    private var savedBytes: Int { max(0, totalOriginal - totalFinal) }
    private var savedPercent: Double {
        totalOriginal > 0 ? Double(savedBytes) / Double(totalOriginal) * 100 : 0
    }
    /// Files the new format made larger than the originals.
    private var grown: [JobResult] { successes.filter { $0.finalBytes > $0.originalBytes } }
    private var addedBytes: Int { max(0, totalFinal - totalOriginal) }

    var body: some View {
        VStack(spacing: 0) {
            if runner.emptyDrop {
                emptyState
            } else {
                header
                list
            }
            footer
        }
        .focusedSceneValue(\.resultSelection, ResultSelection(urls: outputs(for: selection)) {
            preview = outputs(for: selection).first
        })
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.45)) {
                released = true
            }
            withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.9).delay(0.1)) {
                shownPercent = savedPercent
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 18) {
            ClampView(squeeze: released ? 0 : 1)
                .frame(width: 78, height: 84)
            VStack(alignment: .leading, spacing: 3) {
                if savedBytes > 0 {
                    PercentText(value: shownPercent)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                    Text("\(ByteFormat.string(savedBytes)) lighter · \(imageCount)")
                        .foregroundStyle(.secondary)
                } else if addedBytes > 0 {
                    Text("+\(Int((Double(addedBytes) / Double(totalOriginal) * 100).rounded()))%")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("\(ByteFormat.string(addedBytes)) heavier · \(imageCount)")
                        .foregroundStyle(.secondary)
                } else {
                    Text(successes.isEmpty ? "Nothing squished" : "Already lean")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text(successes.isEmpty ? "Nothing could be saved." : "\(imageCount) · nothing left to squeeze")
                        .foregroundStyle(.secondary)
                }
                if runner.wasCancelled {
                    Text("Cancelled after \(runner.results.count) of \(runner.totalFiles)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if !grown.isEmpty {
                    Label(grown.count == 1 && successes.count == 1 ? "Larger in the new format" : "\(grown.count) got larger in the new format",
                          systemImage: "arrow.up.right")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if !failures.isEmpty {
                    Label("\(failures.count) couldn’t be squished", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 40)
        .padding(.bottom, 14)
    }

    private var imageCount: String {
        successes.count == 1 ? "1 image" : "\(successes.count) images"
    }

    // MARK: - List

    private var list: some View {
        List(runner.results, selection: $selection) { result in
            ResultRow(result: result)
                .onDrag { result.output.flatMap { NSItemProvider(contentsOf: $0) } ?? NSItemProvider() }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .scrollContentBackground(.hidden)
        .contextMenu(forSelectionType: JobResult.ID.self) { ids in
            let urls = outputs(for: ids)
            Button("Open") { urls.forEach { NSWorkspace.shared.open($0) } }.disabled(urls.isEmpty)
            Button("Show in Finder") { Platform.reveal(urls) }.disabled(urls.isEmpty)
            Button("Quick Look") { preview = urls.first }.disabled(urls.isEmpty)
            Divider()
            Button("Copy") { copy(urls) }.disabled(urls.isEmpty)
        } primaryAction: { ids in
            outputs(for: ids).forEach { NSWorkspace.shared.open($0) }
        }
        .onKeyPress(.space) {
            guard let url = outputs(for: selection).first else { return .ignored }
            preview = url
            return .handled
        }
        .onCopyCommand {
            outputs(for: selection).map { NSItemProvider(object: $0 as NSURL) }
        }
        .quickLookPreview($preview, in: runner.outputs)
        .listCard()
        .padding(.horizontal, 16)
    }

    private func outputs(for ids: Set<JobResult.ID>) -> [URL] {
        runner.results.filter { ids.contains($0.id) }.compactMap(\.output)
    }

    /// Puts the files themselves on the pasteboard, for pasting into Finder or Mail.
    private func copy(_ urls: [URL]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(urls as [NSURL])
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 12) {
            ClampView(squeeze: 0)
                .frame(height: 130)
            Text("Nothing to squish")
                .font(.title2.weight(.semibold))
            Text("That drop didn’t include any images Squish can read.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if !runner.outputs.isEmpty {
                Button("Show in Finder") { Platform.reveal(runner.outputs) }
                    .buttonStyle(.glass)
            }
            Spacer()
            Text("Drop more to keep going")
                .font(.callout)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Done") { runner.reset() }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
        .background {
            // Escape also means Done; the visible button already answers Return.
            Button("Done") { runner.reset() }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private extension View {
    /// Clips the results list to a hairline-bordered card whose corners nest
    /// inside the window's.
    func listCard() -> some View {
        let shape = ConcentricRectangle(corners: .concentric(minimum: .fixed(14)), isUniform: true)
        return clipShape(shape).overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }
}

@Animatable
private struct PercentText: View {
    var value: Double
    var body: some View {
        Text("−\(Int(value.rounded()))%").monospacedDigit()
    }
}

private struct ResultRow: View {
    let result: JobResult
    @State private var thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            thumb
            VStack(alignment: .leading, spacing: 1) {
                Text(result.output?.lastPathComponent ?? result.name)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                detail
            }
            Spacer(minLength: 8)
            badge
        }
        .padding(.vertical, 3)
        .task(id: result.output) { thumbnail = await Thumbnails.load(result.output) }
        .help(result.output?.path ?? result.source.path)
    }

    @ViewBuilder private var thumb: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.06))
            if let thumbnail {
                Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
            } else if !result.isSuccess {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
        }
        .frame(width: 38, height: 30)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
    }

    @ViewBuilder private var detail: some View {
        switch result.status {
        case .success:
            Text(successDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        case .skipped(let why):
            Text(why).font(.caption).foregroundStyle(.secondary)
        case .failed(let why):
            Text(why).font(.caption).foregroundStyle(.red).lineLimit(1)
        }
    }

    private var successDetail: String {
        var s = "\(ByteFormat.string(result.originalBytes)) → \(ByteFormat.string(result.finalBytes))"
        if let o = result.originalSize, let f = result.finalSize, o != f {
            s += " · \(Int(f.width))×\(Int(f.height))"
        }
        if let note = result.note { s += " · \(note)" }
        return s
    }

    @ViewBuilder private var badge: some View {
        if result.isSuccess, result.savedPercent >= 1 {
            Text("−\(Int(result.savedPercent.rounded()))%")
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.accentColor)
        } else if result.isSuccess, result.savedPercent <= -1 {
            Text("+\(Int((-result.savedPercent).rounded()))%")
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

enum Thumbnails {
    static func load(_ url: URL?) async -> NSImage? {
        guard let url else { return nil }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 76, height: 60),
                                                   scale: NSScreen.main?.backingScaleFactor ?? 2,
                                                   representationTypes: .thumbnail)
        return try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
    }
}
