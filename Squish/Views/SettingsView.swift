import SwiftUI

/// Settings tabs, remembered so "Edit Presets…" can jump straight to one.
enum SettingsTab: String {
    case general, pixels, sizes

    static func select(_ tab: SettingsTab) {
        UserDefaults.standard.set(tab.rawValue, forKey: "settingsTab")
    }
}

/// Each tab sets its own size: General fits its form, and the preset lists
/// keep a fixed height so they can scroll. The window resizes as tabs change.
struct SquishSettingsView: View {
    @AppStorage("settingsTab") private var tab = SettingsTab.general.rawValue

    var body: some View {
        TabView(selection: $tab) {
            Tab("General", systemImage: "gearshape", value: SettingsTab.general.rawValue) { GeneralPane() }
            Tab("File Size", systemImage: "scalemass", value: SettingsTab.sizes.rawValue) {
                SizePresetsPane().frame(width: 500, height: 380)
            }
            Tab("Dimensions", systemImage: "aspectratio", value: SettingsTab.pixels.rawValue) {
                DimensionPresetsPane().frame(width: 500, height: 380)
            }
        }
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
        // Reports the form's full height instead of scrolling, so no space is left below it.
        .scrollDisabled(true)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Pixel size presets

private struct DimensionPresetsPane: View {
    @Environment(SquishSettings.self) private var settings
    @Environment(\.undoManager) private var undoManager

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
                        PresetNameField(name: row.name) { old, new in
                            settings.registerRename(of: preset.id, in: \.dimensionPresets, from: old, to: new, undoManager: undoManager)
                        }
                        TextField("px", value: row.pixels, format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Text("px").foregroundStyle(.secondary)
                        Button(role: .destructive) {
                            settings.removePreset(preset.id, from: \.dimensionPresets, undoManager: undoManager)
                        } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .help("Delete Preset")
                        .accessibilityLabel("Delete \(preset.name)")
                    }
                }
            }

            Divider()
            HStack {
                Button {
                    settings.addPreset(.init(name: "New", pixels: 1024), to: \.dimensionPresets, undoManager: undoManager)
                } label: { Label("Add Preset", systemImage: "plus") }
                Spacer()
            }
            .padding(12)
        }
    }
}

// MARK: - File size presets

private struct SizePresetsPane: View {
    @Environment(SquishSettings.self) private var settings
    @Environment(\.undoManager) private var undoManager

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
                        PresetNameField(name: row.name) { old, new in
                            settings.registerRename(of: preset.id, in: \.sizePresets, from: old, to: new, undoManager: undoManager)
                        }
                        TextField("Size", value: row.value, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                        Picker("", selection: row.unit) {
                            ForEach(SizeUnit.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 70)
                        Button(role: .destructive) {
                            settings.removePreset(preset.id, from: \.sizePresets, undoManager: undoManager)
                        } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .help("Delete Preset")
                        .accessibilityLabel("Delete \(preset.name)")
                    }
                }
            }

            Divider()
            HStack {
                Button {
                    settings.addPreset(.init(name: "New", value: 1, unit: .mb), to: \.sizePresets, undoManager: undoManager)
                } label: { Label("Add Preset", systemImage: "plus") }
                Spacer()
            }
            .padding(12)
        }
    }
}

// MARK: - Undo

/// A preset's name field. Typing updates the preset live; one undo step is
/// registered per rename, when the field loses focus or Return is pressed.
private struct PresetNameField: View {
    @Binding var name: String
    let renamed: (_ old: String, _ new: String) -> Void

    @FocusState private var isFocused: Bool
    @State private var original: String?

    var body: some View {
        TextField("Name", text: $name)
            .textFieldStyle(.roundedBorder)
            .focused($isFocused)
            .onChange(of: isFocused) { _, focused in
                if focused { original = name } else { commit() }
            }
            .onSubmit {
                commit()
                original = name
            }
    }

    private func commit() {
        if let original, original != name { renamed(original, name) }
        original = nil
    }
}

/// A preset that Settings can add, delete and rename with undo.
private protocol EditablePreset: Identifiable<UUID> {
    var name: String { get set }
}

extension DimensionPreset: @MainActor EditablePreset {}
extension SizePreset: @MainActor EditablePreset {}

private typealias PresetList<P> = ReferenceWritableKeyPath<SquishSettings, [P]>

/// One named undo step per add, delete or rename. Each step registers its own
/// inverse under the same name, so Redo reads like Undo did.
extension SquishSettings {
    fileprivate func addPreset<P: EditablePreset>(_ preset: P, to list: PresetList<P>, undoManager: UndoManager?) {
        insert(preset, at: self[keyPath: list].endIndex, in: list, named: "Add Preset", undoManager: undoManager)
    }

    fileprivate func removePreset<P: EditablePreset>(_ id: UUID, from list: PresetList<P>, undoManager: UndoManager?) {
        remove(id, from: list, named: "Delete Preset", undoManager: undoManager)
    }

    /// The name is already `new`; this only makes the rename undoable.
    fileprivate func registerRename<P: EditablePreset>(of id: UUID, in list: PresetList<P>,
                                                       from old: String, to new: String, undoManager: UndoManager?) {
        // A field can lose focus because its preset was just deleted; that's not a rename.
        guard self[keyPath: list].contains(where: { $0.id == id }) else { return }
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] settings in
            guard let index = settings[keyPath: list].firstIndex(where: { $0.id == id }) else { return }
            settings[keyPath: list][index].name = old
            settings.registerRename(of: id, in: list, from: new, to: old, undoManager: undoManager)
        }
        undoManager?.setActionName("Rename Preset")
    }

    private func insert<P: EditablePreset>(_ preset: P, at index: Int, in list: PresetList<P>,
                                           named actionName: String, undoManager: UndoManager?) {
        self[keyPath: list].insert(preset, at: min(index, self[keyPath: list].endIndex))
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] settings in
            settings.remove(preset.id, from: list, named: actionName, undoManager: undoManager)
        }
        undoManager?.setActionName(actionName)
    }

    private func remove<P: EditablePreset>(_ id: UUID, from list: PresetList<P>,
                                           named actionName: String, undoManager: UndoManager?) {
        guard let index = self[keyPath: list].firstIndex(where: { $0.id == id }) else { return }
        let preset = self[keyPath: list].remove(at: index)
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] settings in
            settings.insert(preset, at: index, in: list, named: actionName, undoManager: undoManager)
        }
        undoManager?.setActionName(actionName)
    }
}
