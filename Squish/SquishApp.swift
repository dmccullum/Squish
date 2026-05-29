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
                .frame(minWidth: 440, idealWidth: 470, maxWidth: 640,
                       minHeight: 580, idealHeight: 660, maxHeight: 900)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
