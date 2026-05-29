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
            Picker("Default format", selection: $settings.defaultFormat) {
                ForEach(OutputFormat.allCases) { Text($0.displayName).tag($0) }
            }
            .help("Used whenever the Format control is off — including for inputs like PNG.")

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

            Section("Appearance") {
                Picker("Controls", selection: $settings.controlStyle) {
                    ForEach(ControlStyle.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("How the three squish controls look on the main window.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Pixel size presets

private struct DimensionPresetsPane: View {
    @EnvironmentObject private var settings: SquishSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Quick-pick pixel sizes shown in the Dimensions control (applied as a max long side).")
                .font(.callout).foregroundStyle(.secondary)
                .padding([.horizontal, .top], 16)
                .padding(.bottom, 8)

            List {
                ForEach($settings.dimensionPresets) { $preset in
                    HStack(spacing: 10) {
                        TextField("Name", text: $preset.name)
                            .textFieldStyle(.roundedBorder)
                        TextField("px", value: $preset.pixels, format: .number)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Quick-pick file-size limits shown in the File size control.")
                .font(.callout).foregroundStyle(.secondary)
                .padding([.horizontal, .top], 16)
                .padding(.bottom, 8)

            List {
                ForEach($settings.sizePresets) { $preset in
                    HStack(spacing: 10) {
                        TextField("Name", text: $preset.name)
                            .textFieldStyle(.roundedBorder)
                        TextField("Size", value: $preset.value, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                        Picker("", selection: $preset.unit) {
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
