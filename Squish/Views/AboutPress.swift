import AppKit
import DMKit
import SwiftUI

/// The About window's signature: the icon's press, live. Drag down on it (or
/// scroll down over it) to close the jaws on the photo, with a haptic detent
/// at each of Squish's own presets (Share 10 MB, Email 5 MB and Web 1 MB,
/// spaced as a 24 MB photo would shrink) and a pop when they bottom out at
/// Small 500 KB. Release and they spring open. A click runs the whole squeeze
/// on its own.
///
/// While nobody holds it and the window is key, the press floats gently up and
/// down. 0.6 s after the window opens it gives one small squeeze and opens
/// again. Hovering moves the jaws in a little and leans them toward the
/// pointer, and shows the grab cursor. Under Reduce Motion there's no float,
/// demo squeeze or lean, the pop has no bounce, and the jaws ease open
/// without a spring.
struct AboutPress: View {
    /// The photo's size before squeezing and the presets it passes on the way
    /// down, as in Settings › File Size; they place the detents.
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
    private static let pressHeight: CGFloat = 100
    private static let pressSize = CGSize(width: pressHeight * PressView.art.width / PressView.art.height, height: pressHeight)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// False while the About window isn't key, which pauses the float.
    @Environment(\.appearsActive) private var appearsActive

    /// 0 open, 1 shut.
    @State private var squeeze = 0.0
    /// The pop's overshoot past shut, 0…1.
    @State private var punch = 0.0
    /// Hover: a small extra squeeze, and the jaws' lean toward the pointer (−1…1).
    @State private var leanIn = 0.0
    @State private var lean = 0.0
    /// The float, 0 at rest to 1 at the top of the drift.
    @State private var drift = 0.0
    /// True from the first scroll tick until the jaws open again.
    @State private var scrolling = false
    @State private var dragStart: Double?
    @State private var popped = false
    /// Set by the first drag, scroll or click; skips the demo.
    @State private var used = false
    @State private var hovering = false
    @State private var pending: Task<Void, Never>?
    @State private var scroll = ScrollMonitor()
    /// The signature's width, to find the centre of the press.
    @State private var width: CGFloat = 0

    var body: some View {
        PressView(squeeze: squeeze + punch * 0.15 + leanIn, lean: lean)
            .frame(width: Self.pressSize.width, height: Self.pressSize.height)
            .offset(y: -Self.driftHeight * drift)
            .frame(maxWidth: .infinity)
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
                    if hypot(value.translation.width, value.translation.height) < 3 { press() } else { release() }
                }
        )
        .onChange(of: floats, initial: true) { _, floats in
            if floats {
                withAnimation(.easeInOut(duration: Self.driftCycle / 2).repeatForever(autoreverses: true)) { drift = 1 }
            } else {
                // A plain animation replaces the repeating one and settles it.
                withDMAnimation(.smooth) { drift = 0 }
            }
        }
        .task { await demo() }
        .onDisappear {
            scroll.stop()
            pending?.cancel()
        }
        .accessibilityElement()
        .accessibilityLabel("Press")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Squeezes the photo through each file size preset")
        .accessibilityAction { press() }
        .accessibilityAdjustableAction { direction in
            let stage = Self.stage(at: squeeze)
            let next = min(max(stage + (direction == .increment ? 1 : -1), 0), Self.detents.count)
            let target = next == 0 ? 0 : Self.squeeze(at: Self.detents[next - 1].bytes)
            withDMAnimation(.snappy) { squeeze = target }
            popped = next == Self.detents.count
        }
        .help("Drag down or scroll to squeeze")
    }

    /// “Open”, or how far it's squeezed and the smallest preset it's reached.
    private var accessibilityValue: String {
        let stage = Self.stage(at: squeeze)
        guard squeeze > 0.001 else { return "Open" }
        let percent = "\(Int((squeeze * 100).rounded())) percent squeezed"
        return stage == 0 ? percent : "\(percent), \(Self.detents[stage - 1].name)"
    }

    // MARK: - Float

    /// Points the press drifts up, and seconds for one drift up and back.
    private static let driftHeight: CGFloat = 4
    private static let driftCycle = 2.8

    /// Floats while the window is key and nobody holds or scrolls it.
    private var floats: Bool {
        !reduceMotion && appearsActive && dragStart == nil && !scrolling
    }

    // MARK: - Squeezing

    /// Moves the jaws with the pointer: snaps into a preset within a hair of
    /// it, ticks a detent on each preset crossed, and pops when it bottoms out.
    private func set(_ raw: Double) {
        used = true
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

    /// The deliberate moment: the jaws bite past shut and wobble back, the
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

    /// A click: closes the jaws all the way, pops, holds a beat, and opens.
    private func press() {
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
        scrolling = false
        withDMAnimation(.spring) { squeeze = 0 }
    }

    /// Once per window opening, 0.6 s in: a small squeeze, about a fifth of
    /// the travel, so the jaws just bite the card (short of the first preset,
    /// so no detent), and back open.
    /// Skipped under Reduce Motion or once the user has squeezed.
    private func demo() async {
        guard !reduceMotion else { return }
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled, !used, dragStart == nil else { return }
        withAnimation(DMMotion.spring.animation) {
            squeeze = 0.21
        } completion: {
            guard !used, dragStart == nil else { return }
            withDMAnimation(.spring) { squeeze = 0 }
        }
    }

    /// Scrolling down closes the jaws; they open once scrolling stops.
    private func scrolled(_ down: CGFloat) {
        guard dragStart == nil else { return }
        pending?.cancel()
        scrolling = true
        set(squeeze + down / (Self.travel * 2))
        pending = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            release()
        }
    }

    /// Moves the jaws in a little and leans them toward the pointer, more the
    /// closer it is to the middle of the press.
    private func lean(toward p: CGPoint?) {
        guard !reduceMotion else { return }
        var inward = 0.0, side = 0.0
        if let p {
            // The press is centered under 4 pt of top padding; the drift is ignored.
            let dx = p.x - width / 2
            let dy = p.y - (4 + Self.pressSize.height / 2)
            let near = max(0, 1 - hypot(dx, dy) / 110)
            inward = 0.08 * near
            side = near * Double(max(-1, min(1, dx / 50)))
        }
        withDMAnimation(.smooth) {
            leanIn = inward
            lean = side
        }
    }
}

/// Feeds scroll-wheel and trackpad scrolls to the press while the pointer is
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
    AboutPress()
        .frame(width: 336)
        .padding()
}
