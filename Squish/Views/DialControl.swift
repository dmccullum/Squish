import SwiftUI

/// A tactile rotary dial. Drag around the arc (or vertically) to change the
/// value. Supports a logarithmic scale for things like file size.
struct DialControl: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var logScale: Bool = false
    var enabled: Bool = true
    let format: (Double) -> String

    @State private var dragStartFraction: Double?

    private let sweep: Double = 270            // degrees of travel
    private let startDeg: Double = 135         // bottom-left

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = side / 2 - 8

            ZStack {
                // Track
                ArcShape(startDeg: startDeg, sweep: sweep)
                    .stroke(Color.primary.opacity(0.12), style: .init(lineWidth: 9, lineCap: .round))
                // Progress
                ArcShape(startDeg: startDeg, sweep: sweep * fraction)
                    .stroke(enabled ? Color.accentColor : Color.secondary,
                            style: .init(lineWidth: 9, lineCap: .round))

                // Knob
                let knobDeg = startDeg + sweep * fraction
                let knob = point(on: center, radius: radius, degrees: knobDeg)
                Circle()
                    .fill(.white)
                    .frame(width: 16, height: 16)
                    .shadow(radius: 1, y: 1)
                    .overlay(Circle().strokeBorder(enabled ? Color.accentColor : Color.secondary, lineWidth: 3))
                    .position(knob)

                VStack(spacing: 0) {
                    Text(format(value))
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(width: side * 0.62)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { g in
                        guard enabled else { return }
                        if dragStartFraction == nil { dragStartFraction = fraction }
                        // Scrub: drag up to increase, down to decrease.
                        // Full range over ~220 px of travel.
                        let delta = Double(-g.translation.height) / 220
                        setFraction((dragStartFraction ?? fraction) + delta)
                    }
                    .onEnded { _ in dragStartFraction = nil }
            )
        }
        .frame(height: 104)
    }

    // value <-> fraction

    private var fraction: Double {
        let lo = logScale ? log(range.lowerBound) : range.lowerBound
        let hi = logScale ? log(range.upperBound) : range.upperBound
        let v = logScale ? log(value) : value
        return min(1, max(0, (v - lo) / (hi - lo)))
    }

    private func setFraction(_ f: Double) {
        let lo = logScale ? log(range.lowerBound) : range.lowerBound
        let hi = logScale ? log(range.upperBound) : range.upperBound
        let raw = logScale ? exp(lo + f * (hi - lo)) : lo + f * (hi - lo)
        let snapped = (raw / step).rounded() * step
        value = min(range.upperBound, max(range.lowerBound, snapped))
    }

    private func point(on center: CGPoint, radius: CGFloat, degrees: Double) -> CGPoint {
        let rad = degrees * .pi / 180
        let x = Double(center.x) + Double(radius) * cos(rad)
        let y = Double(center.y) + Double(radius) * sin(rad)
        return CGPoint(x: x, y: y)
    }
}

private struct ArcShape: Shape {
    let startDeg: Double
    let sweep: Double
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(rect.width, rect.height) / 2 - 8
        let c = CGPoint(x: rect.midX, y: rect.midY)
        p.addArc(center: c, radius: r,
                 startAngle: .degrees(startDeg),
                 endAngle: .degrees(startDeg + sweep),
                 clockwise: false)
        return p
    }
}
