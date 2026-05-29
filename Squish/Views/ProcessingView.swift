import SwiftUI

struct ProcessingView: View {
    @EnvironmentObject private var runner: JobRunner

    private var done: Int { Int((runner.progress * Double(runner.totalFiles)).rounded()) }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.compress.vertical")
                .font(.system(size: 46, weight: .regular))
                .foregroundStyle(Color.accentColor)
                .symbolEffect(.pulse)

            Text("Squishing…")
                .font(.title2.bold())

            ProgressView(value: runner.progress)
                .progressViewStyle(.linear)
                .frame(width: 280)

            Text("\(done) of \(runner.totalFiles)")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            if !runner.currentFile.isEmpty {
                Text(runner.currentFile)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 280)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
