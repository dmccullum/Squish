import SwiftUI

struct SquishSettingsView: View {
    var body: some View {
        TabView {
            GeneralPane()
                .tabItem { Label("General", systemImage: "gearshape") }
            DimensionPresetsPane()
                .tabItem { Label("Pixel Sizes", systemImage: "aspectratio") }
            SizePresetsPane()
                .tabItem { Label("File Sizes", systemImage: "scalemass") }
        }
        .frame(width: 500, height: 380)
    }
}

// MARK: - General

private struct GeneralPane: View {
    @EnvironmentObject private var settings: SquishSettings

    var body: some View {
        Form {
            Section("Batches") {
                Picker("When squishing several images", selection: $settings.strategy) {
                    ForEach(CompressionStrategy.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.radioGroup)
                Text(settings.strategy.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Pixel size presets

private struct DimensionPresetsPane: View {
    @EnvironmentObject private var settings: SquishSettings

    // Edit by id so rows can re-sort live without losing the binding.
    private func binding(_ id: UUID) -> Binding<DimensionPreset> {
        Binding(
            get: { settings.dimensionPresets.first { $0.id == id } ?? .init(name: "", pixels: 0) },
            set: { newValue in
                if let i = settings.dimensionPresets.firstIndex(where: { $0.id == id }) {
                    settings.dimensionPresets[i] = newValue
                }
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Quick-pick pixel sizes shown in the Dimensions control (applied as a max long side). Sorted largest to smallest.")
                .font(.callout).foregroundStyle(.secondary)
                .padding([.horizontal, .top], 16)
                .padding(.bottom, 8)

            List {
                ForEach(settings.sortedDimensionPresets) { preset in
                    let row = binding(preset.id)
                    HStack(spacing: 10) {
                        TextField("Name", text: row.name)
                            .textFieldStyle(.roundedBorder)
                        TextField("px", value: row.pixels, format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Text("px").foregroundStyle(.secondary)
                        Button(role: .destructive) {
                            settings.dimensionPresets.removeAll { $0.id == preset.id }
                        } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                    }
                }
            }

            Divider()
            HStack {
                Button {
                    settings.dimensionPresets.append(.init(name: "New", pixels: 1024))
                } label: { Label("Add Size", systemImage: "plus") }
                Spacer()
            }
            .padding(12)
        }
    }
}

// MARK: - File size presets

private struct SizePresetsPane: View {
    @EnvironmentObject private var settings: SquishSettings

    private func binding(_ id: UUID) -> Binding<SizePreset> {
        Binding(
            get: { settings.sizePresets.first { $0.id == id } ?? .init(name: "", value: 0, unit: .mb) },
            set: { newValue in
                if let i = settings.sizePresets.firstIndex(where: { $0.id == id }) {
                    settings.sizePresets[i] = newValue
                }
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Quick-pick file-size limits shown in the File size control. Sorted largest to smallest.")
                .font(.callout).foregroundStyle(.secondary)
                .padding([.horizontal, .top], 16)
                .padding(.bottom, 8)

            List {
                ForEach(settings.sortedSizePresets) { preset in
                    let row = binding(preset.id)
                    HStack(spacing: 10) {
                        TextField("Name", text: row.name)
                            .textFieldStyle(.roundedBorder)
                        TextField("Size", value: row.value, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                        Picker("", selection: row.unit) {
                            ForEach(SizeUnit.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 70)
                        Button(role: .destructive) {
                            settings.sizePresets.removeAll { $0.id == preset.id }
                        } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                    }
                }
            }

            Divider()
            HStack {
                Button {
                    settings.sizePresets.append(.init(name: "New", value: 1, unit: .mb))
                } label: { Label("Add Limit", systemImage: "plus") }
                Spacer()
            }
            .padding(12)
        }
    }
}
