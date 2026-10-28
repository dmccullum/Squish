import SwiftUI

@main
struct SquishApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var app

    var body: some Scene {
        Window("Squish", id: "main") {
            ContentView()
                .environment(app.settings)
                .environment(app.runner)
                .environment(app.editor)
                .frame(width: 480, height: 440)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            SquishCommands(settings: app.settings, runner: app.runner, editor: app.editor)
        }

        Settings {
            SquishSettingsView()
                .environment(app.settings)
        }
    }
}

/// Owns the app's state so files can arrive before (or without) the window:
/// the Dock icon, Open With, and Finder's Services menu all land here.
@MainActor
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

    func applicationDidBecomeActive(_ notification: Notification) {
        if !runner.isRunning { NSApp.dockTile.badgeLabel = nil }
    }

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

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Squish Images…", systemImage: "photo.stack") {
                let urls = Platform.chooseInputs()
                guard !urls.isEmpty else { return }
                if runner.hasFinished { runner.reset() }
                runner.accept(urls, settings: settings)
            }
            .keyboardShortcut("o")
            .disabled(runner.isRunning)
        }
        CommandGroup(after: .newItem) {
            Divider()
            Button("Show in Finder", systemImage: "folder") { Platform.reveal(runner.outputs) }
                .keyboardShortcut("r")
                .disabled(runner.outputs.isEmpty)
            Button("Stop Squishing", systemImage: "stop.circle") { runner.cancel() }
                .keyboardShortcut(".")
                .disabled(!runner.isRunning)
        }
        CommandMenu("Recipe") {
            ForEach(RecipeField.allCases) { field in
                RecipeMenu(field: field, settings: settings, runner: runner, editor: editor)
            }
        }
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
        Menu(field.title, systemImage: field.symbol) {
            let actions = RecipeActions(
                editCustom: { editor.editing = $0 },
                editPresets: { field in
                    SettingsTab.select(field == .size ? .sizes : .pixels)
                    openSettings()
                })
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
