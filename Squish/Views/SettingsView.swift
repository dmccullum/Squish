import SwiftUI

/// Settings tabs, remembered so "Edit Presets…" can jump straight to one.
enum SettingsTab: String {
    case general, pixels, sizes

    static func select(_ tab: SettingsTab) {
        UserDefaults.standard.set(tab.rawValue, forKey: "settingsTab")
    }
}

struct SquishSettingsView: View {
    @AppStorage("settingsTab") private var tab = SettingsTab.general.rawValue

    var body: some View {
        Group {
            if #available(macOS 15.0, *) {
                TabView(selection: $tab) {
                    Tab("General", systemImage: "gearshape", value: SettingsTab.general.rawValue) { GeneralPane() }
                    Tab("Pixel Sizes", systemImage: "aspectratio", value: SettingsTab.pixels.rawValue) { DimensionPresetsPane() }
                    Tab("File Sizes", systemImage: "scalemass", value: SettingsTab.sizes.rawValue) { SizePresetsPane() }
                }
            } else {
                TabView(selection: $tab) {
                    GeneralPane()
                        .tabItem { Label("General", systemImage: "gearshape") }
                        .tag(SettingsTab.general.rawValue)
                    DimensionPresetsPane()
                        .tabItem { Label("Pixel Sizes", systemImage: "aspectratio") }
                        .tag(SettingsTab.pixels.rawValue)
                    SizePresetsPane()
                        .tabItem { Label("File Sizes", systemImage: "scalemass") }
                        .tag(SettingsTab.sizes.rawValue)
                }
            }
        }
        .frame(width: 500, height: 380)
    }
}

// MARK: - General

private struct GeneralPane: View {
    @Environment(SquishSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
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
            Section("When a batch finishes") {
                Toggle("Play a sound", isOn: $settings.playSound)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Pixel size presets

private struct DimensionPresetsPane: View {
    @Environment(SquishSettings.self) private var settings

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
            Text("Shown in the Dimensions menu and applied to the longest side. Sorted largest to smallest.")
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
    @Environment(SquishSettings.self) private var settings

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
            Text("Shown in the File Size menu. Sorted largest to smallest.")
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
