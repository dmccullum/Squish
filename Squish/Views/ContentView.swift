import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(SquishSettings.self) private var settings
    @Environment(JobRunner.self) private var runner
    @Environment(RecipeEditor.self) private var editor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isTargeted = false
    @State private var hoveringHero = false
    @State private var twist = 0.0

    var body: some View {
        ZStack {
            background
            if runner.hasFinished {
                ResultsView()
                    .transition(.opacity)
            } else {
                main
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: runner.hasFinished)
        .dropDestination(for: URL.self) { urls, _ in
            if runner.hasFinished { runner.reset() }
            runner.accept(urls, settings: settings)
            return true
        } isTargeted: { isTargeted = $0 }
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            // A warm pool of light behind the clamp; brightens when files hover.
            RadialGradient(colors: [Color.accentColor.opacity(isTargeted ? 0.30 : 0.13), .clear],
                           center: UnitPoint(x: 0.5, y: 0.3), startRadius: 0, endRadius: 280)
                .animation(.easeOut(duration: 0.25), value: isTargeted)
        }
        .ignoresSafeArea()
    }

    // MARK: - Ready / squishing

    private var main: some View {
        VStack(spacing: 0) {
            Button(action: chooseFiles) {
                ClampView(squeeze: squeeze, twist: twist, photoScale: photoScale)
                    .frame(height: 170)
                    .padding(.top, 34)
            }
            .buttonStyle(.plain)
            .onHover { hoveringHero = $0 }
            .accessibilityLabel("Choose images to squish")
            .help("Choose images to squish")

            caption
                .frame(height: 64)
                .padding(.top, 14)

            Spacer(minLength: 0)

            tray
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .animation(heroSpring, value: squeeze)
        .animation(heroSpring, value: photoScale)
        .onChange(of: runner.completed) { _, _ in
            guard runner.isRunning, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.35)) { twist += .pi }
        }
    }

    private var squeeze: Double {
        if runner.isRunning { return 1 }
        if isTargeted { return 0.55 }
        if let preview = editor.preview { return preview.squeeze ?? 0 }
        return hoveringHero ? 0.12 : 0
    }

    private var photoScale: Double {
        runner.isRunning ? 1 : editor.preview?.photoScale ?? 1
    }

    private var heroSpring: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.62)
    }

    @ViewBuilder private var caption: some View {
        VStack(spacing: 6) {
            if runner.isRunning {
                Text(runner.totalFiles == 1 ? "Squishing…" : "Squishing \(min(runner.completed + 1, runner.totalFiles)) of \(runner.totalFiles)…")
                    .font(.title2.weight(.semibold))
                    .contentTransition(.numericText())
                    .animation(.snappy, value: runner.completed)
                Text(runner.currentFile)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 320)
            } else if let preview = editor.preview, !isTargeted {
                // Narrates whatever is highlighted in an open recipe menu.
                Text(preview.title)
                    .font(.title2.weight(.semibold))
                Text(preview.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text(isTargeted ? "Let go to squish" : "Drop images to squish")
                    .font(.title2.weight(.semibold))
                    .contentTransition(.interpolate)
            }
        }
        .animation(.easeOut(duration: 0.15), value: isTargeted)
    }

    @ViewBuilder private var tray: some View {
        Group {
            if runner.isRunning {
                HStack(spacing: 14) {
                    ProgressView(value: runner.progress)
                        .progressViewStyle(.linear)
                        .tint(.accentColor)
                    Button("Cancel") { runner.cancel() }
                        .keyboardShortcut(.cancelAction)
                }
                .padding(.horizontal, 20)
            } else {
                RecipeSentence()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 88)
        .trayBackground()
    }

    // MARK: - Input

    private func chooseFiles() {
        guard !runner.isRunning else { return }
        Task {
            let urls = await Platform.chooseInputs()
            guard !urls.isEmpty else { return }
            runner.accept(urls, settings: settings)
        }
    }
}

extension View {
    /// The rounded tray that holds the recipe and the progress bar: Liquid Glass
    /// with its corners nested inside the window's.
    func trayBackground() -> some View {
        glassEffect(.regular, in: ConcentricRectangle(corners: .concentric(minimum: .fixed(18)), isUniform: true))
    }
}
