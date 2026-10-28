import DMKit
import SwiftUI

/// The About window's signature: the icon's clamp, live. Click it to give the
/// handle a half turn and squeeze the photo; drag sideways to turn the handle
/// yourself, winding the screw down further the farther you go. It springs
/// open on release. Under Reduce Motion the handle doesn't spin on a click and
/// the squeeze fades in and out without a spring.
struct AboutClamp: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var squeeze = 0.0
    @State private var twist = 0.0
    /// The handle's angle when the current drag began.
    @State private var dragStart: Double?

    var body: some View {
        ClampView(squeeze: squeeze, twist: twist)
            .frame(height: 96)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let start = dragStart ?? twist
                        dragStart = start
                        let dx = value.translation.width
                        guard abs(dx) >= 3 else { return }
                        // About a half turn per 90 points; the screw bottoms out at 140.
                        twist = start + dx / 30
                        squeeze = min(abs(dx) / 140, 1)
                    }
                    .onEnded { value in
                        dragStart = nil
                        let moved = hypot(value.translation.width, value.translation.height)
                        if moved < 3 { clamp() } else { release() }
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("Clamp")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { clamp() }
            .help("Click or drag to turn the clamp")
    }

    /// A half turn down and back open.
    private func clamp() {
        withAnimation(DMMotion.spring.animation(reduceMotion: reduceMotion)) {
            squeeze = 1
            if !reduceMotion { twist += .pi }
        } completion: {
            release()
        }
    }

    private func release() {
        withAnimation(DMMotion.spring.animation(reduceMotion: reduceMotion)) {
            squeeze = 0
        }
    }
}

#Preview {
    AboutClamp()
        .padding()
}
