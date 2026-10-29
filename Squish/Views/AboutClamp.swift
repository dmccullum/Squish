import AppKit
import DMKit
import SwiftUI

/// The About window's signature: the icon's clamp, live, squeezing a 24 MB
/// photo. Drag down on it (or scroll down over it) to wind the screw: the jaw
/// closes on the photo and the readout under it ticks the size down through
/// Squish's own presets, Share 10 MB, Email 5 MB and Web 1 MB, with a haptic
/// detent at each, to Small 500 KB, where it pops. Release and it springs
/// open. A click runs the whole squeeze on its own.
///
/// 0.6 s after the window opens the clamp gives one small squeeze and opens
/// again, and “Drag the handle down to squeeze” sits under the readout until
/// the first squeeze; until then the handle bobs every 4 s while the window
/// is key and the pointer is elsewhere. Hovering leans the handle a little toward the pointer and shows the grab
/// cursor. Under Reduce Motion there's no demo squeeze or bob, the handle doesn't turn or lean, the pop has
/// no bounce, and the clamp eases open without a spring.
struct AboutClamp: View {
    /// The photo before squeezing and the presets it passes on the way down,
    /// as in Settings › File Size.
    static let original = 24_000_000
    static let detents: [(name: String, bytes: Int)] = [
        ("Share", 10_000_000), ("Email", 5_000_000), ("Web", 1_000_000), ("Small", 500_000)
    ]
    static var smallest: Int { detents.last!.bytes }

    /// Size at a squeeze from 0 (open) to 1 (shut): falls geometrically, so
    /// every preset gets a fair share of the travel.
    static func bytes(at squeeze: Double) -> Int {
        let s = min(max(squeeze, 0), 1)
        return Int(Double(original) * pow(Double(smallest) / Double(original), s))
    }

    static func squeeze(at bytes: Int) -> Double {
        log(Double(original) / Double(bytes)) / log(Double(original) / Double(smallest))
    }

    /// How many presets the photo fits under at `squeeze`.
    static func stage(at squeeze: Double) -> Int {
        let b = bytes(at: squeeze + 0.0001)
        return detents.filter { b <= $0.bytes }.count
    }

    /// Points of downward drag for a full squeeze.
    private static let travel: CGFloat = 90
    private static let clampHeight: CGFloat = 110
    private static let clampSize = CGSize(width: clampHeight * ClampView.art.width / ClampView.art.height, height: clampHeight)
    /// The T-handle's center at rest, in the clamp's own coordinates.
    private static let handle = CGPoint(x: (441 - ClampView.art.minX) / ClampView.art.width * clampSize.width,
                                        y: (54 - ClampView.art.minY) / ClampView.art.height * clampSize.height)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    /// False while the About window isn't key, which pauses the idle bob.
    @Environment(\.appearsActive) private var appearsActive

    /// 0 open, 1 shut; drives the readout.
    @State private var squeeze = 0.0
    /// The pop's overshoot past shut, 0…1.
    @State private var punch = 0.0
    /// Hover lean: a small extra squeeze and turn toward the pointer.
    @State private var leanDown = 0.0
    @State private var leanTurn = 0.0
    /// The idle bob, 0…1: a few points down and an eighth of a turn.
    @State private var bob = 0.0
    /// `appearsActive` mirrored into state, which the idle task reads live.
    @State private var windowIsKey = true
    @State private var dragStart: Double?
    @State private var popped = false
    /// Set by the first drag, scroll or click; hides the hint and skips the demo.
    @State private var used = false
    @State private var hovering = false
    @State private var pending: Task<Void, Never>?
    @State private var scroll = ScrollMonitor()
    /// The signature's width, to find the handle under the centered clamp.
    @State private var width: CGFloat = 0

    var body: some View {
        VStack(spacing: 8) {
            ClampView(squeeze: squeeze + punch * 0.12 + leanDown + bob * 0.16,
                      twist: (reduceMotion ? 0 : squeeze * 1.5 * .pi) + leanTurn + bob * .pi / 4)
                .frame(width: Self.clampSize.width, height: Self.clampSize.height)

            VStack(spacing: 2) {
                SquishReadout(squeeze: squeeze, popped: popped)
                    .frame(maxWidth: .infinity)
                // The line stays reserved after the hint fades, so nothing below moves.
                Text("Drag the handle down to squeeze")
                    .font(.callout)
                    .foregroundStyle(contrast == .increased ? .secondary : .tertiary)
                    .lineLimit(1)
                    .opacity(used ? 0 : 1)
                    .animation(reduceMotion ? nil : DMMotion.smooth.animation, value: used)
                    .accessibilityHidden(true)
            }
        }
        .padding(.top, 4)
        .contentShape(Rectangle())
        .pointerStyle(dragStart == nil ? .grabIdle : .grabActive)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let p):
                if !hovering {
                    hovering = true
                    scroll.start { delta in scrolled(delta) }
                }
                lean(toward: p)
            case .ended:
                hovering = false
                scroll.stop()
                lean(toward: nil)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if dragStart == nil {
                        pending?.cancel()
                        dragStart = squeeze
                    }
                    guard let start = dragStart,
                          hypot(value.translation.width, value.translation.height) >= 3 else { return }
                    set(start + value.translation.height / Self.travel)
                }
                .onEnded { value in
                    dragStart = nil
                    if hypot(value.translation.width, value.translation.height) < 3 { clamp() } else { release() }
                }
        )
        .onChange(of: appearsActive, initial: true) { _, active in windowIsKey = active }
        .task {
            await demo()
            await idle()
        }
        .onDisappear {
            scroll.stop()
            pending?.cancel()
        }
        .accessibilityElement()
        .accessibilityLabel("Clamp")
        .accessibilityValue("\(ByteFormat.string(Self.original)) squeezed to \(ByteFormat.string(Self.bytes(at: squeeze)))")
        .accessibilityHint("Squeezes the photo to each file size preset")
        .accessibilityAction { clamp() }
        .accessibilityAdjustableAction { direction in
            let stage = Self.stage(at: squeeze)
            let next = min(max(stage + (direction == .increment ? 1 : -1), 0), Self.detents.count)
            let target = next == 0 ? 0 : Self.squeeze(at: Self.detents[next - 1].bytes)
            withDMAnimation(.snappy) { squeeze = target }
            popped = next == Self.detents.count
        }
        .help("Drag down or scroll to squeeze")
    }

    // MARK: - Squeezing

    /// Moves the screw under the pointer: snaps into a preset within a hair of
    /// it, ticks a detent on each preset crossed, and pops when it bottoms out.
    private func set(_ raw: Double) {
        used = true
        bob = 0
        var value = min(max(raw, 0), 1)
        for detent in Self.detents.dropLast() {
            let at = Self.squeeze(at: detent.bytes)
            if abs(value - at) < 0.025 { value = at }
        }
        let before = Self.stage(at: squeeze)
        squeeze = value
        let after = Self.stage(at: value)
        if value >= 1 {
            if !popped { pop() }
        } else {
            if value < 0.97 { popped = false }
            if after != before {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        }
    }

    /// The deliberate moment: the jaw bites past shut and wobbles back, the
    /// one spring here under 0.7 damping.
    private func pop() {
        popped = true
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        guard !reduceMotion else { return }
        withAnimation(.easeOut(duration: 0.07)) {
            punch = 1
        } completion: {
            withAnimation(.spring(duration: 0.45, bounce: 0.55)) { punch = 0 }
        }
    }

    /// A click: winds all the way down, pops, holds a beat, and opens.
    private func clamp() {
        used = true
        pending?.cancel()
        withAnimation(DMMotion.spring.animation(reduceMotion: reduceMotion)) {
            squeeze = 1
        } completion: {
            guard squeeze >= 1 else { return }
            pop()
            pending = Task {
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                release()
            }
        }
    }

    private func release() {
        pending?.cancel()
        popped = false
        withDMAnimation(.spring) { squeeze = 0 }
    }

    /// Once per window opening, 0.6 s in: a small squeeze, about a fifth of
    /// the travel (short of the first preset, so no detent), and back open.
    /// Skipped under Reduce Motion or once the user has squeezed.
    private func demo() async {
        guard !reduceMotion else { return }
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled, !used, dragStart == nil else { return }
        withAnimation(DMMotion.spring.animation) {
            squeeze = 0.18
        } completion: {
            guard !used, dragStart == nil else { return }
            withDMAnimation(.spring) { squeeze = 0 }
        }
    }

    /// Until the first squeeze, every 4 s the handle bobs down and back with
    /// a little wiggle. Sleeps between bobs, skips while hovered, dragged or
    /// while the window isn't key, and ends with the window or the first
    /// squeeze. Never under Reduce Motion.
    private func idle() async {
        guard !reduceMotion else { return }
        while !used {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, !used else { return }
            guard windowIsKey, !hovering, dragStart == nil, squeeze == 0 else { continue }
            withAnimation(.easeOut(duration: 0.12)) {
                bob = 1
            } completion: {
                withAnimation(.spring(duration: 0.5, bounce: 0.3)) { bob = 0 }
            }
        }
    }

    /// Scrolling down winds the screw; it opens once scrolling stops.
    private func scrolled(_ down: CGFloat) {
        guard dragStart == nil else { return }
        pending?.cancel()
        set(squeeze + down / (Self.travel * 2))
        pending = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            release()
        }
    }

    /// Leans the handle toward the pointer, more the closer it is.
    private func lean(toward p: CGPoint?) {
        guard !reduceMotion else { return }
        var down = 0.0, turn = 0.0
        if let p {
            // The clamp is centered under 4 pt of top padding.
            let dx = p.x - ((width - Self.clampSize.width) / 2 + Self.handle.x)
            let dy = p.y - (4 + Self.handle.y)
            let near = max(0, 1 - hypot(dx, dy) / 110)
            down = 0.12 * near
            turn = 0.35 * near * Double(max(-1, min(1, dx / 40)))
        }
        withDMAnimation(.smooth) {
            leanDown = down
            leanTurn = turn
        }
    }
}

/// “24 MB → 612 KB · Web”: the photo's size as the clamp squeezes it, read
/// frame by frame so it ticks during a click or a spring back too.
@Animatable
private struct SquishReadout: View {
    var squeeze: Double
    @AnimatableIgnored var popped: Bool
    @AnimatableIgnored @Environment(\.colorSchemeContrast) private var contrast
    @AnimatableIgnored @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let stage = AboutClamp.stage(at: squeeze)
        let squeezed = squeeze > 0.001
        HStack(spacing: 6) {
            Text(ByteFormat.string(AboutClamp.original))
                .foregroundStyle(contrast == .increased ? .primary : .secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            // At rest only the original shows, in the same place; the arrow and
            // the squeezed size fade in once the screw moves.
            Group {
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                HStack(spacing: 4) {
                Text(ByteFormat.string(AboutClamp.bytes(at: squeeze)))
                    .fontWeight(popped ? .bold : .semibold)
                    .foregroundStyle(popped ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
                    if stage > 0 {
                        Text("· \(AboutClamp.detents[stage - 1].name)")
                            .foregroundStyle(contrast == .increased ? .primary : .secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .opacity(squeezed ? 1 : 0)
            .animation(reduceMotion ? nil : DMMotion.smooth.animation, value: squeezed)
        }
        .font(.callout)
        .monospacedDigit()
        .lineLimit(1)
        .accessibilityHidden(true)
    }
}

/// Feeds scroll-wheel and trackpad scrolls to the clamp while the pointer is
/// over it, in points. A swipe or wheel turn toward you counts as down
/// whatever the Natural Scrolling setting.
private final class ScrollMonitor {
    private var monitor: Any?

    func start(_ handler: @escaping (CGFloat) -> Void) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            // Momentum after the fingers lift would keep squeezing past release.
            guard event.momentumPhase.isEmpty else { return nil }
            let raw = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 10
            handler(event.isDirectionInvertedFromDevice ? raw : -raw)
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    isolated deinit { stop() }
}

#Preview {
    AboutClamp()
        .frame(width: 336)
        .padding()
}
