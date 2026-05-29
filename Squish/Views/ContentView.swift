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

    // MARK: - Idle

    private var idleView: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                DropZoneView(isTargeted: isTargeted) { addFromPanel() }
                    .frame(height: 150)
                ControlsView()
                OutputRow()
            }
            .padding(20)

            Spacer(minLength: 0)
            Divider()
            actionFooter
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(.bar)
        }
    }

    @ViewBuilder
    private var actionFooter: some View {
        if !settings.isActionable {
            Label("Turn on a control above, then drop your images.", systemImage: "wand.and.stars")
                .font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        } else if let pendingInput {
            HStack {
                Button("Clear", role: .cancel) { self.pendingInput = nil }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                Button {
                    runner.run(input: pendingInput, settings: settings)
                } label: {
                    Label("Squish \(Self.describe(pendingInput))", systemImage: "bolt.fill")
                }
                .controlSize(.large).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        } else {
            Text("Ready — drop images to squish.")
                .font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
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

// MARK: - Output destination row

private struct OutputRow: View {
    @EnvironmentObject private var settings: SquishSettings

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                segment("Auto", "wand.and.stars", mode: .auto)
                segment("Choose…", "folder", mode: .choose)
            }
            .padding(3)
            .background(Capsule().fill(Color.primary.opacity(0.06)))

            if settings.outputMode == .auto {
                Text("Saved next to your originals")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(settings.chosenFolder?.path ?? "No folder chosen")
                    .font(.caption).foregroundStyle(settings.chosenFolder == nil ? .secondary : .primary)
                    .lineLimit(1).truncationMode(.middle)
                Button("Choose…") {
                    if let u = Platform.chooseFolder() { settings.chosenFolderPath = u.path }
                }
                .controlSize(.small)
            }
            Spacer(minLength: 0)
        }
    }

    private func segment(_ title: String, _ icon: String, mode: OutputMode) -> some View {
        let selected = settings.outputMode == mode
        return Button {
            withAnimation(.snappy(duration: 0.15)) { settings.outputMode = mode }
        } label: {
            Label(title, systemImage: icon)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Capsule().fill(selected ? Color.accentColor : Color.clear))
                .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
