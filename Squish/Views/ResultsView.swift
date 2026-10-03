import SwiftUI
import QuickLook
import QuickLookThumbnailing

struct ResultsView: View {
    @EnvironmentObject private var runner: JobRunner
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
                        .foregroundStyle(Color.squishInk)
                    Text("\(ByteFormat.string(savedBytes)) lighter · \(imageCount)")
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
                if !failures.isEmpty {
                    Label("\(failures.count) couldn’t be squished", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
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
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects(urls as [NSURL])
            }.disabled(urls.isEmpty)
        } primaryAction: { ids in
            outputs(for: ids).forEach { NSWorkspace.shared.open($0) }
        }
        .onKeyPress(.space) {
            guard let url = outputs(for: selection).first else { return .ignored }
            preview = url
            return .handled
        }
        .quickLookPreview($preview, in: runner.outputs)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        .padding(.horizontal, 16)
    }

    private func outputs(for ids: Set<JobResult.ID>) -> [URL] {
        runner.results.filter { ids.contains($0.id) }.compactMap(\.output)
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
            }
            Spacer()
            Text("Drop more to keep going")
                .font(.callout)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Done") { runner.reset() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }
}

/// "−81%" that counts up smoothly as `value` animates.
private struct PercentText: View, Animatable {
    var value: Double
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }
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
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
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
            Text(why).font(.caption).foregroundStyle(.orange).lineLimit(1)
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
                .foregroundStyle(Color.squishInk)
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
