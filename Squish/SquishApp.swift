import DMKit
import SwiftUI

@main
struct SquishApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var app

    var body: some Scene {
        Window("Squish", id: "main") {
            ContentView()
                .providesHostingWindow()
                .environment(app.settings)
                .environment(app.runner)
                .environment(app.editor)
                // Grows so the results list can show more rows; Zoom fills the screen.
                .frame(minWidth: 480, idealWidth: 480, maxWidth: .infinity,
                       minHeight: 440, idealHeight: 440, maxHeight: .infinity)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            SquishCommands(settings: app.settings, runner: app.runner, editor: app.editor)
            UndoCommands()
        }

        Settings {
            SquishSettingsView()
                .environment(app.settings)
        }

        AboutScene(links: AboutLinks(sourceCode: URL(string: "https://github.com/dmccullum/Squish"))) {
            AboutClamp()
        }
    }
}

/// Owns the app's state so files can arrive before (or without) the window:
/// the Dock icon, Open With, and Finder's Services menu all land here.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = SquishSettings()
    let runner = JobRunner()
    let editor = RecipeEditor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        squish(urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Services menu: "Squish Images" (NSMessage `squishFiles` in Info.plist).
    @objc func squishFiles(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        squish(urls)
        NSApp.activate()
    }

    private func squish(_ urls: [URL]) {
        if runner.hasFinished { runner.reset() }
        runner.accept(urls, settings: settings)
    }
}

struct SquishCommands: Commands {
    let settings: SquishSettings
    let runner: JobRunner
    let editor: RecipeEditor
    @FocusedValue(\.resultSelection) private var selection

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Squish Images…") {
                Task {
                    let urls = await Platform.chooseInputs(in: Platform.commandWindow)
                    guard !urls.isEmpty else { return }
                    if runner.hasFinished { runner.reset() }
                    runner.accept(urls, settings: settings)
                }
            }
            .keyboardShortcut("o")
            .disabled(runner.isRunning)
        }
        CommandGroup(after: .newItem) {
            Divider()
            Button("Open") { selection?.urls.forEach { NSWorkspace.shared.open($0) } }
                .keyboardShortcut(.downArrow)
                .disabled(selection?.urls.isEmpty ?? true)
            Button("Show in Finder") {
                // The selected results, or all of them when nothing is selected.
                let selected = selection?.urls ?? []
                Platform.reveal(selected.isEmpty ? runner.outputs : selected)
            }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(runner.outputs.isEmpty)
            Button(quickLookTitle) { selection?.quickLook() }
                .keyboardShortcut("y")
                .disabled(selection?.urls.isEmpty ?? true)
            Divider()
            Button("Clear Results") { runner.reset() }
                .disabled(!runner.hasFinished)
            Button("Stop Squishing") { runner.cancel() }
                .keyboardShortcut(".")
                .disabled(!runner.isRunning)
        }
        FamilyHelpCommands(
            help: URL(string: "https://github.com/dmccullum/Squish#readme")!,
            // The README has no heading of its own for shortcuts; the table is under Usage.
            keyboardShortcuts: .url(URL(string: "https://github.com/dmccullum/Squish#usage")!),
            reportIssue: URL(string: "https://github.com/dmccullum/Squish/issues/new")
        )
        CommandMenu("Recipe") {
            ForEach(RecipeField.allCases) { field in
                RecipeMenu(field: field, settings: settings, runner: runner, editor: editor)
            }
        }
    }

    /// "Quick Look “IMG_0042 (squished).jpg”", like Finder, when one result is selected.
    private var quickLookTitle: String {
        guard let urls = selection?.urls, urls.count == 1 else { return "Quick Look" }
        return "Quick Look “\(urls[0].lastPathComponent)”"
    }
}

/// A Recipe submenu built from the same options as the sentence's pop-ups.
private struct RecipeMenu: View {
    let field: RecipeField
    let settings: SquishSettings
    let runner: JobRunner
    let editor: RecipeEditor
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Menu(field.title) {
            let actions = RecipeActions(
                editCustom: { editor.editing = $0 },
                editPresets: { field in
                    SettingsTab.select(field == .size ? .sizes : .pixels)
                    openSettings()
                },
                chooseFolder: { await Platform.chooseFolder(in: Platform.commandWindow) })
            ForEach(settings.options(for: field, style: .menuBar, actions: actions)) { option in
                switch option.kind {
                case .separator:
                    Divider()
                case .command:
                    Button(option.title, action: option.action)
                        .disabled(option.editsInSentence && (runner.isRunning || runner.hasFinished))
                case .choice:
                    Toggle(isOn: Binding(get: { option.checked }, set: { _ in option.action() })) {
                        Text(option.detail.map { "\(option.title) (\($0))" } ?? option.title)
                    }
                case .submenu, .dial:
                    EmptyView()  // Only used by the pop-up style.
                }
            }
        }
    }
}
