import SwiftUI

struct ResultsView: View {
    @EnvironmentObject private var runner: JobRunner
    let onMore: () -> Void

    private var successes: [JobResult] { runner.results.filter(\.isSuccess) }
    private var failures: [JobResult] { runner.results.filter { !$0.isSuccess } }
    private var totalOriginal: Int { successes.reduce(0) { $0 + $1.originalBytes } }
    private var totalFinal: Int { successes.reduce(0) { $0 + $1.finalBytes } }
    private var savedBytes: Int { max(0, totalOriginal - totalFinal) }
    private var savedPercent: Double {
        totalOriginal > 0 ? Double(totalOriginal - totalFinal) / Double(totalOriginal) * 100 : 0
    }

    var body: some View {
        VStack(spacing: 0) {
            if runner.emptyDrop {
                emptyState
            } else {
                summary
                Divider()
                List {
                    ForEach(runner.results) { ResultRow(result: $0) }
                }
                .listStyle(.inset)
            }

            Divider()
            footer
        }
    }

    private var summary: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor)
                .symbolEffect(.bounce, value: runner.hasFinished)

            Text(savedBytes > 0
                 ? "Saved \(ByteFormat.string(savedBytes))"
                 : "Done")
                .font(.title2.bold())

            Text(headline)
                .font(.callout)
                .foregroundStyle(.secondary)

            if !failures.isEmpty {
                Label("\(failures.count) couldn’t be squished", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private var headline: String {
        let n = successes.count
        let noun = n == 1 ? "image" : "images"
        if savedBytes > 0 {
            return "\(n) \(noun) · \(Int(savedPercent.rounded()))% smaller"
        }
        return "\(n) \(noun) squished"
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "questionmark.folder")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No images found")
                .font(.title2.bold())
            Text("That drop didn’t contain any images Squish can read.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var footer: some View {
        HStack {
            if !successes.isEmpty {
                Button {
                    Platform.reveal(successes.compactMap(\.output))
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
            }
            Spacer()
            Button(action: onMore) {
                Label("Squish More", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }
}

private struct ResultRow: View {
    let result: JobResult

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .font(.title3)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.output?.lastPathComponent ?? result.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                detail
            }
            Spacer()
            if result.isSuccess, result.savedPercent > 0 {
                Text("−\(Int(result.savedPercent.rounded()))%")
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var detail: some View {
        switch result.status {
        case .success:
            HStack(spacing: 6) {
                Text("\(ByteFormat.string(result.originalBytes)) → \(ByteFormat.string(result.finalBytes))")
                if let o = result.originalSize, let f = result.finalSize, o != f {
                    Text("· \(dims(f))")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let note = result.note {
                Text(note).font(.caption2).foregroundStyle(.tertiary)
            }
        case .skipped(let why):
            Text(why).font(.caption).foregroundStyle(.secondary)
        case .failed(let why):
            Text(why).font(.caption).foregroundStyle(.orange).lineLimit(1)
        }
    }

    private func dims(_ size: CGSize) -> String {
        "\(Int(size.width))×\(Int(size.height))"
    }

    private var icon: String {
        switch result.status {
        case .success: return "checkmark.circle.fill"
        case .skipped: return "minus.circle"
        case .failed:  return "exclamationmark.circle.fill"
        }
    }

    private var iconColor: Color {
        switch result.status {
        case .success: return Color.accentColor
        case .skipped: return .secondary
        case .failed:  return .orange
        }
    }
}
