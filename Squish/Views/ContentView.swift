import DMKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(SquishSettings.self) private var settings
    @Environment(JobRunner.self) private var runner
    @Environment(RecipeEditor.self) private var editor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.hostingWindow) private var window

    @State private var isTargeted = false
    @State private var hoveringHero = false
    /// 1 at the moment a file finishes, easing back to 0: the jaws bite again.
    @State private var bite = 0.0
    /// The last batch whose press has finished playing; the results wait for it.
    @State private var shownBatch = 0
    /// How far the press has got through the current batch, 0 at the grip to 1
    /// fully crumpled; and the pop at the end, 0…1.
    @State private var pressed = 0.0
    @State private var pop = 0.0

    var body: some View {
        ZStack {
            background
            if runner.hasFinished && !playing {
                ResultsView()
                    .transition(.opacity)
            } else {
                main
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: runner.hasFinished && !playing)
        .onAppear {
            // A batch that finished while the window was closed goes straight to its results.
            if !runner.isRunning { shownBatch = runner.batches }
        }
        .task(id: runner.batches) { await playPress() }
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
            // A warm pool of light behind the press; brightens when files hover.
            // Reduce Transparency leaves the plain window background.
            if !reduceTransparency {
                RadialGradient(colors: [Color.accentColor.opacity(isTargeted ? 0.30 : 0.13), .clear],
                               center: UnitPoint(x: 0.5, y: 0.3), startRadius: 0, endRadius: 280)
                    .animation(.easeOut(duration: 0.25), value: isTargeted)
            }
        }
        .ignoresSafeArea()
        // On this full-window layer, so the outline follows the window's corners.
        .dropTargetOutline(isTargeted, filled: false)
    }

    // MARK: - Ready / squishing

    private var main: some View {
        VStack(spacing: 0) {
            Button(action: chooseFiles) {
                // The jaws run in from the window's edges.
                PressView(squeeze: squeeze + 0.12 * bite, framing: .bleed)
                    .frame(maxWidth: .infinity)
                    .frame(height: 280)
                    .padding(.top, 30)
            }
            .buttonStyle(.plain)
            .onHover { hoveringHero = $0 }
            .accessibilityLabel("Choose images to squish")
            .help("Choose images to squish")

            caption
                .frame(height: 64)
                .padding(.top, 8)

            Spacer(minLength: 0)

            tray
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        // While the press plays, playPress sets the squeeze every frame itself.
        .animation(playing ? .linear(duration: 0.05) : heroSpring, value: squeeze)
        .onChange(of: runner.completed) { _, _ in
            guard runner.isRunning, !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.08)) {
                bite = 1
            } completion: {
                withAnimation(.spring(duration: 0.35, bounce: 0.3)) { bite = 0 }
            }
        }
    }

    /// Open at rest; under the pointer the jaws close on the card and start to
    /// bow it, grip harder while files hover, and act out a highlighted menu
    /// choice. A batch plays the whole press, from the grip through the icon's
    /// pose to fully crumpled and a pop (see `playPress`); under Reduce Motion
    /// it holds at the recipe's depth instead.
    private var squeeze: Double {
        if playing { return Self.grip + (1 - Self.grip) * pressed + 0.15 * pop }
        if runner.isRunning { return max(settings.pressDepth, Self.grip) }
        if isTargeted { return Self.grip }
        if let preview = editor.preview { return preview.squeeze ?? 0 }
        return hoveringHero ? Self.bite : 0
    }

    /// The pointer over the art: the jaws meet the card and just start to bow it.
    static let bite = PressView.contact + 0.05
    /// Files held over the window.
    static let grip = PressView.contact + 0.16

    /// True from a batch's start until its press has finished playing.
    private var playing: Bool { !reduceMotion && shownBatch != runner.batches }

    /// The shortest time the press takes from the drop to fully crumpled, so a
    /// single fast file still shows the whole squeeze. It only delays the
    /// switch to the results; the files are written as soon as they're done.
    private static let minimumPress: Double = 0.75

    /// Acts out one batch: the press follows the batch's progress, but no
    /// faster than `minimumPress` from grip to fully crumpled; then a pop and
    /// a short hold before the results. A cancelled batch goes straight to its
    /// results.
    private func playPress() async {
        let batch = runner.batches
        guard batch != shownBatch else { return }
        defer { shownBatch = batch }
        guard !reduceMotion else { return }
        pressed = 0
        pop = 0
        let clock = ContinuousClock()
        let start = clock.now
        while !Task.isCancelled, !runner.wasCancelled {
            let elapsed = (clock.now - start) / .seconds(1)
            let done = !runner.isRunning
            let target = min(done ? 1 : runner.progress, elapsed / Self.minimumPress)
            // Ease toward the target so per-file steps glide rather than jump.
            pressed += (target - pressed) * 0.22
            if done, pressed > 0.995 { break }
            try? await Task.sleep(for: .milliseconds(16))
        }
        guard !Task.isCancelled, !runner.wasCancelled else { return }
        pressed = 1
        withAnimation(.easeOut(duration: 0.08)) { pop = 1 } completion: {
            withAnimation(.spring(duration: 0.3, bounce: 0.4)) { pop = 0 }
        }
        try? await Task.sleep(for: .milliseconds(150))
    }

    private var heroSpring: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.62)
    }

    @ViewBuilder private var caption: some View {
        VStack(spacing: 6) {
            if runner.isRunning || playing {
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
            if runner.isRunning || playing {
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
            let urls = await Platform.chooseInputs(in: window)
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
