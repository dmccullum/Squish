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
            ScrollView {
                VStack(spacing: 18) {
                    DropZoneView(isTargeted: isTargeted) { addFromPanel() }
                        .frame(height: 188)

                    ControlsView()
                }
                .padding(20)
            }

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
            Label("Turn on an option above, then drop your images.", systemImage: "wand.and.stars")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        } else if let pendingInput {
            VStack(spacing: 8) {
                Button {
                    runner.run(input: pendingInput, settings: settings)
                } label: {
                    Label("Squish \(Self.describe(pendingInput))", systemImage: "bolt.fill")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)

                Button("Clear", role: .cancel) { self.pendingInput = nil }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("Ready — drop images to squish.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
    }

    // MARK: - Drop handling

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let relevant = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !relevant.isEmpty else { return false }
        loadURLs(from: relevant) { urls in
            accept(urls)
        }
        return true
    }

    private func addFromPanel() {
        let urls = Platform.chooseInputs()
        accept(urls)
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
                if let data = item as? Data {
                    resolved = URL(dataRepresentation: data, relativeTo: nil)
                } else if let url = item as? URL {
                    resolved = url
                }
                if let resolved {
                    lock.lock(); urls.append(resolved); lock.unlock()
                }
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
