import SwiftUI

struct ControlsView: View {
    @EnvironmentObject private var settings: SquishSettings

    var body: some View {
        VStack(spacing: 14) {
            // File size
            OptionCard(title: "File size", systemImage: "scalemass", isOn: $settings.sizeTargetEnabled) {
                HStack(spacing: 8) {
                    TextField("Size", value: $settings.sizeValue, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                    Picker("", selection: $settings.sizeUnit) {
                        ForEach(SizeUnit.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 96)
                    Spacer()
                }
                caption("Each image is squished to about this size or smaller.")
            }

            // Dimensions
            OptionCard(title: "Dimensions", systemImage: "arrow.up.left.and.arrow.down.right", isOn: $settings.dimensionEnabled) {
                Picker("Limit", selection: $settings.dimensionMode) {
                    ForEach(DimensionMode.allCases) { Text($0.displayName).tag($0) }
                }
                .labelsHidden()
                dimensionFields
                caption("Images larger than this are scaled down. Smaller images are left alone.")
            }

            // Format
            OptionCard(title: "Format", systemImage: "photo", isOn: $settings.formatEnabled) {
                Picker("", selection: $settings.format) {
                    ForEach(OutputFormat.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if settings.format == .png {
                    caption("PNG is lossless — file-size targets are reached by resizing.")
                } else {
                    caption("Convert every image to \(settings.format.displayName).")
                }
            }

            outputCard
        }
    }

    @ViewBuilder
    private var dimensionFields: some View {
        switch settings.dimensionMode {
        case .maxLongSide:
            pixelField("Longest side", value: $settings.longSide)
        case .maxWidth:
            pixelField("Width", value: $settings.maxWidth)
        case .maxHeight:
            pixelField("Height", value: $settings.maxHeight)
        case .fit:
            HStack(spacing: 8) {
                pixelField("Width", value: $settings.fitWidth)
                Text("×").foregroundStyle(.secondary)
                pixelField("Height", value: $settings.fitHeight)
            }
        }
    }

    private var outputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Output", systemImage: "folder").font(.headline)

            Picker("", selection: $settings.outputMode) {
                Text("Auto").tag(OutputMode.auto)
                Text("Choose…").tag(OutputMode.choose)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if settings.outputMode == .auto {
                caption("Single image → saved beside the original. Several → a “Squished” folder. A folder → a “\(settings.suffix.trimmingCharacters(in: .whitespaces))” copy nearby.")
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill").foregroundStyle(.secondary)
                    Text(settings.chosenFolder?.path ?? "No folder chosen")
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(settings.chosenFolder == nil ? .secondary : .primary)
                    Spacer()
                    Button("Choose…") {
                        if let url = Platform.chooseFolder() { settings.chosenFolderPath = url.path }
                    }
                    .controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.primary.opacity(0.05)))
    }

    private func pixelField(_ label: String, value: Binding<Int>) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.callout).foregroundStyle(.secondary)
            TextField(label, value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
            Text("px").font(.callout).foregroundStyle(.secondary)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A titled card with a master switch that reveals its content when on.
struct OptionCard<Content: View>: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: systemImage).font(.headline)
                Spacer()
                Toggle("", isOn: $isOn.animation(.snappy(duration: 0.2)))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            if isOn {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.primary.opacity(0.05)))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isOn ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1.5)
        )
    }
}
