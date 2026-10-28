import SwiftUI
import AppKit

/// Which custom editor (if any) is open. Shared so the Recipe menu in the menu
/// bar can open the same popovers as the sentence.
@Observable
final class RecipeEditor {
    var editing: RecipeField?
    /// Set while a recipe menu is open and something in it is highlighted or
    /// being dragged; the window's clamp and caption act it out.
    var preview: RecipePreview?
}

/// "Make them [under 1 MB] and [max 2048 px], then save as [JPEG] [next to the originals]."
struct RecipeSentence: View {
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                Text("Make them")
                RecipeToken(field: .size)
                Text("and")
                RecipeToken(field: .dimensions)
                    .overlay(alignment: .trailing) { Text(",").offset(x: 6) }
            }
            HStack(spacing: 5) {
                Text("then save as")
                RecipeToken(field: .format)
                RecipeToken(field: .location)
                    .overlay(alignment: .trailing) { Text(".").offset(x: 5) }
            }
        }
        .font(.system(size: 15))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recipe")
    }
}

/// One tappable phrase in the sentence. Clicking shows a native menu with the
/// current choice under the pointer, like a pop-up button.
struct RecipeToken: View {
    let field: RecipeField

    @Environment(SquishSettings.self) private var settings
    @Environment(RecipeEditor.self) private var editor
    @Environment(\.openSettings) private var openSettings
    @State private var anchor = MenuAnchor.Box()
    @State private var hovering = false
    @State private var menuOpen = false

    var body: some View {
        Button(action: showMenu) {
            HStack(spacing: 4) {
                Text(settings.phrase(for: field))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .opacity(0.7)
            }
            .fontWeight(.semibold)
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.accentColor.opacity(menuOpen ? 0.28 : hovering ? 0.2 : 0.12))
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(MenuAnchor(box: anchor))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .popover(isPresented: editingBinding, arrowEdge: .bottom) { editorView }
        .accessibilityLabel(field.title)
        .accessibilityValue(settings.phrase(for: field))
        .accessibilityHint("Shows choices")
    }

    private var editingBinding: Binding<Bool> {
        Binding(get: { editor.editing == field },
                set: { if !$0, editor.editing == field { editor.editing = nil } })
    }

    @ViewBuilder private var editorView: some View {
        switch field {
        case .size:       SizeEditor().environment(settings).environment(editor)
        case .dimensions: DimensionEditor().environment(settings).environment(editor)
        default:          EmptyView()
        }
    }

    private func showMenu() {
        guard let view = anchor.view else { return }
        let actions = RecipeActions(
            editCustom: { field in
                // Let the menu finish closing before the popover appears.
                DispatchQueue.main.async { editor.editing = field }
            },
            editPresets: { field in
                SettingsTab.select(field == .size ? .sizes : .pixels)
                openSettings()
            })
        let options = settings.options(for: field, style: .popUp, actions: actions)
        let controller = RecipeMenuController { editor.preview = $0 }
        let context = RecipeMenuContext(field: field, settings: settings) { editor.preview = $0 }
        let (menu, selected) = RecipeMenuBuilder.menu(for: options, context: context, delegate: controller)
        controller.root = menu
        menuOpen = true
        withExtendedLifetime(controller) {
            if options.contains(where: { $0.kind == .dial }) {
                // Menus that lead with the dial drop down from the phrase.
                menu.popUp(positioning: nil, at: NSPoint(x: -12, y: -6), in: view)
            } else {
                // Others put the checked item right over the phrase, like a pop-up button.
                let origin = NSPoint(x: -RecipeMenuBuilder.titleInset + 8, y: view.bounds.height - 1)
                menu.popUp(positioning: selected, at: origin, in: view)
            }
        }
        menuOpen = false
        editor.preview = nil
    }
}

/// Captures the NSView behind a SwiftUI view so a menu can pop up from it.
struct MenuAnchor: NSViewRepresentable {
    final class Box { weak var view: NSView? }
    let box: Box

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        box.view = v
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) { box.view = nsView }
}

// MARK: - Custom editors

private struct SizeEditor: View {
    @Environment(SquishSettings.self) private var settings
    @Environment(RecipeEditor.self) private var editor
    @FocusState private var valueFocused: Bool

    var body: some View {
        @Bindable var settings = settings
        VStack(alignment: .leading, spacing: 12) {
            Text("Keep each image under").font(.headline)
            HStack(spacing: 8) {
                TextField("Size", value: $settings.sizeValue, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .focused($valueFocused)
                Picker("Unit", selection: $settings.sizeUnit) {
                    ForEach(SizeUnit.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 96)
            }
            HStack {
                Spacer()
                Button("Done") { editor.editing = nil }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 240)
        .defaultFocus($valueFocused, true)
        .onAppear { settings.sizeTargetEnabled = true }
    }
}

private struct DimensionEditor: View {
    @Environment(SquishSettings.self) private var settings
    @Environment(RecipeEditor.self) private var editor
    /// The label of the focused pixel field.
    @FocusState private var focused: String?

    var body: some View {
        @Bindable var settings = settings
        VStack(alignment: .leading, spacing: 12) {
            Text("Limit dimensions").font(.headline)
            Picker("Limit", selection: $settings.dimensionMode) {
                ForEach(DimensionMode.allCases) { Text($0.shortName).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch settings.dimensionMode {
            case .maxLongSide: pixelField("Longest side", $settings.longSide)
            case .maxWidth:    pixelField("Width", $settings.maxWidth)
            case .maxHeight:   pixelField("Height", $settings.maxHeight)
            case .fit:
                HStack(spacing: 8) {
                    pixelField("Width", $settings.fitWidth)
                    Text("×").foregroundStyle(.secondary)
                    pixelField("Height", $settings.fitHeight)
                }
            }
            Text("Smaller images are left as they are.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Done") { editor.editing = nil }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 300)
        .defaultFocus($focused, firstField)
        .onAppear { settings.dimensionEnabled = true }
    }

    /// The field that takes focus when the popover opens.
    private var firstField: String {
        switch settings.dimensionMode {
        case .maxLongSide: return "Longest side"
        case .maxWidth, .fit: return "Width"
        case .maxHeight:   return "Height"
        }
    }

    private func pixelField(_ label: String, _ value: Binding<Int>) -> some View {
        HStack(spacing: 6) {
            Text(label).foregroundStyle(.secondary).fixedSize()
            TextField(label, value: value, format: .number.grouping(.never))
                .textFieldStyle(.roundedBorder)
                .frame(width: 68)
                .focused($focused, equals: label)
            Text("px").foregroundStyle(.secondary).fixedSize()
        }
    }
}
