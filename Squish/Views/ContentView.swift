import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var settings: SquishSettings
    @EnvironmentObject private var runner: JobRunner

    @State private var pendingInput: DropInput?
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            backdrop.ignoresSafeArea()

            Group {
                if runner.isRunning {
                    ProcessingView()
                } else if runner.hasFinished {
                    ResultsView(onMore: {
                        pendingInput = nil
                        runner.reset()
                    })
                } else {
                    idleView
                }
            }
        }
        .animation(.snappy(duration: 0.28), value: runner.isRunning)
        .animation(.snappy(duration: 0.28), value: runner.hasFinished)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
    }

    /// Soft colored light so the Liquid Glass tiles have something to refract.
    private var backdrop: some View {
        ZStack {
            Circle().fill(Color.accentColor).frame(width: 340)
                .blur(radius: 120).opacity(0.45).offset(x: -170, y: -130)
            Circle().fill(Color(red: 0.30, green: 0.55, blue: 1.0)).frame(width: 300)
                .blur(radius: 120).opacity(0.32).offset(x: 190, y: 70)
            Circle().fill(Color(red: 1.0, green: 0.35, blue: 0.7)).frame(width: 260)
                .blur(radius: 120).opacity(0.26).offset(x: 150, y: -160)
        }
    }

    // MARK: - Idle

    private var idleView: some View {
        VStack(spacing: 0) {
            VStack(spacing: 24) {
                DropZoneView(isTargeted: isTargeted) { addFromPanel() }
                    .frame(height: 150)
                ControlsView()
            }
            .padding(.horizontal, 20)
            .padding(.top, 26)
            .padding(.bottom, 13)

            Spacer(minLength: 0)
            Divider()
            bottomBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(.bar)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            OutputLocationMenu()
            Spacer(minLength: 8)
            trailingControl
        }
    }

    @ViewBuilder
    private var trailingControl: some View {
        if !settings.isActionable {
            Label("Turn on a control to start", systemImage: "wand.and.stars")
                .font(.callout).foregroundStyle(.secondary)
        } else if let pendingInput {
            HStack(spacing: 8) {
                Button("Clear", role: .cancel) { self.pendingInput = nil }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                Button {
                    runner.run(input: pendingInput, settings: settings)
                } label: {
                    Label("Squish \(Self.describe(pendingInput))", systemImage: "bolt.fill")
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        } else {
            Text("Drop images to squish")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    // MARK: - Drop handling

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let relevant = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !relevant.isEmpty else { return false }
        loadURLs(from: relevant) { urls in accept(urls) }
        return true
    }

    private func addFromPanel() {
        accept(Platform.chooseInputs())
    }

    private func accept(_ urls: [URL]) {
        guard let input = DropInput.classify(urls) else { return }
        if runner.hasFinished { runner.reset() }
        if settings.isActionable {
            pendingInput = nil
            runner.run(input: input, settings: settings)
        } else {
            pendingInput = input
        }
    }

    private func loadURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var resolved: URL?
                if let data = item as? Data { resolved = URL(dataRepresentation: data, relativeTo: nil) }
                else if let url = item as? URL { resolved = url }
                if let resolved { lock.lock(); urls.append(resolved); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) { completion(urls) }
    }

    static func describe(_ input: DropInput) -> String {
        switch input {
        case .single: return "1 image"
        case .group(let urls): return "\(urls.count) items"
        case .folder(let url): return "“\(url.lastPathComponent)”"
        }
    }
}

// MARK: - Output location (bottom bar)

private struct OutputLocationMenu: View {
    @EnvironmentObject private var settings: SquishSettings

    var body: some View {
        HStack(spacing: 6) {
            Text("Save to").font(.callout).foregroundStyle(.secondary)
            Menu {
                Button {
                    settings.outputMode = .auto
                } label: {
                    Label("Auto — beside originals", systemImage: "wand.and.stars")
                }
                Button {
                    if let url = Platform.chooseFolder() {
                        settings.chosenFolderPath = url.path
                        settings.outputMode = .choose
                    }
                } label: {
                    Label(settings.chosenFolder == nil ? "Choose Folder…" : "Change Folder…",
                          systemImage: "folder")
                }
            } label: {
                Label(labelText, systemImage: settings.outputMode == .auto ? "wand.and.stars" : "folder")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private var labelText: String {
        switch settings.outputMode {
        case .auto:   return "Auto Location"
        case .choose: return settings.chosenFolder?.lastPathComponent ?? "Choose Folder…"
        }
    }
}
