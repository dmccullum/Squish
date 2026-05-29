import SwiftUI

@main
struct SquishApp: App {
    @StateObject private var settings = SquishSettings()
    @StateObject private var runner = JobRunner()

    var body: some Scene {
        Window("Squish", id: "main") {
            ContentView()
                .environmentObject(settings)
                .environmentObject(runner)
                .frame(width: 680, height: 420)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SquishSettingsView()
                .environmentObject(settings)
        }
    }
}
