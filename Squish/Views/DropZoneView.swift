import SwiftUI

struct DropZoneView: View {
    let isTargeted: Bool
    let onChoose: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(isTargeted ? Color.accentColor.opacity(0.14)
                                 : Color(nsColor: .controlBackgroundColor))

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                )

            VStack(spacing: 8) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 46, weight: .regular))
                    .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                    .symbolEffect(.bounce, value: isTargeted)

                Text(isTargeted ? "Release to squish" : "Drop images here")
                    .font(.title3.weight(.semibold))

                Text("An image, a bunch, or a whole folder")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text("or click to choose")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
            .padding()
        }
        .scaleEffect(isTargeted ? 1.02 : 1)
        .animation(.snappy(duration: 0.2), value: isTargeted)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture(perform: onChoose)
        .help("Drop images, or click to choose files")
    }
}
