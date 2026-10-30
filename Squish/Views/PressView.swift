import SwiftUI

/// The app icon's press, drawn live: two orange jaws close on a square photo
/// card as `squeeze` goes from 0 (open) to 1 (pressed, the icon's pose).
///
/// From 0 to `contact` the jaws slide in from the edges and the card stays a
/// flat square. Past `contact` they push the card's sides in, its top and
/// bottom bow outward and the picture narrows. At 1 the jaw faces sit on
/// x 256 and 768, the card's corners on y 256 and 768 and its edges bow to
/// y 192 and 832, as in the icon. `squeeze` may run to 1.15 for the pop.
///
/// Geometry is authored in the icon's 1024-point space (the icon is generated
/// by `build2.py`, variant `r2-6-bulgejaws`) so the window art and the app
/// icon stay the same object.
@Animatable
struct PressView: View {
    var squeeze: Double
    /// Shrinks the card (1 = full size) to act out a pixel limit. The jaws
    /// close on the smaller card.
    var photoScale: Double = 1
    /// Shifts both jaws toward one side, −1 (left) to 1 (right), up to 28
    /// points of the 1024 canvas; a card they grip moves with them.
    var lean: Double = 0

    @AnimatableIgnored @Environment(\.colorScheme) private var scheme

    /// The part of the canvas drawn: both jaws at rest, plus their shadows.
    static let art = CGRect(x: -36, y: 100, width: 1096, height: 824)
    /// The squeeze at which the jaws reach the card's sides.
    static let contact = 0.15

    var body: some View {
        Canvas { ctx, size in
            let a = Self.art
            let scale = min(size.width / a.width, size.height / a.height)
            ctx.translateBy(x: (size.width - a.width * scale) / 2 - a.minX * scale,
                            y: (size.height - a.height * scale) / 2 - a.minY * scale)
            ctx.scaleBy(x: scale, y: scale)
            draw(in: &ctx, scale: scale)
        }
        .aspectRatio(Self.art.width / Self.art.height, contentMode: .fit)
        .accessibilityHidden(true)
    }

    // MARK: - Geometry

    /// Photo space: the card is a square centred on (0, 0), half-size `A`.
    private static let A: CGFloat = 320
    /// Card half-size at rest, and its half-width and half-height at the
    /// jaws when pressed.
    private static let rest: CGFloat = 300
    private static let pressedHalfWidth: CGFloat = 272
    private static let pressedHalfHeight: CGFloat = 256
    /// How far the top and bottom edges bow out at the centre when pressed,
    /// as a fraction of the half-height: 256 × 1.25 = 320, so y 192 and 832.
    private static let pressedBow: CGFloat = 0.25
    /// The card runs this far under each jaw face once gripped.
    private static let overlap: CGFloat = 16
    /// Jaw face distance from the centre at rest.
    private static let openFace: CGFloat = 336
    private static let jawWidth: CGFloat = 200
    private static let jawTop: CGFloat = 128, jawBottom: CGFloat = 896
    private static let faceRadius: CGFloat = 96, backRadius: CGFloat = 40

    /// Maps photo space onto the canvas: scales x and y, then bows the top and
    /// bottom edges out, most at the centre.
    private struct Warp {
        var cx: CGFloat, cy: CGFloat, kx: CGFloat, ky: CGFloat, bow: CGFloat

        func callAsFunction(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            let u = min(max(x / PressView.A, -1.2), 1.2)
            return CGPoint(x: cx + x * kx, y: cy + y * ky * (1 + bow * (1 - u * u)))
        }

        func path(_ points: [CGPoint]) -> Path {
            var p = Path()
            p.addLines(points.map { self($0.x, $0.y) })
            p.closeSubpath()
            return p
        }
    }

    // MARK: - Drawing

    private func draw(in ctx: inout GraphicsContext, scale: CGFloat) {
        let s = CGFloat(min(max(squeeze, 0), 1.15))
        // 0 until the jaws touch, 1 at the icon's pose, about 1.18 at full overshoot.
        let c = max(0, (s - Self.contact) / (1 - Self.contact))
        let k = CGFloat(min(max(photoScale, 0.3), 1))
        // Below about 0.15 (the size menu's 46-point preview) shadows, bevels and
        // pressure shading are under a pixel, so they're skipped.
        let fine = scale > 0.15
        let dark = scheme == .dark

        let halfWidth = lerp(Self.rest, Self.pressedHalfWidth, c)
        let face = (s < Self.contact ? lerp(Self.openFace, Self.rest - Self.overlap, s / Self.contact)
                                     : halfWidth - Self.overlap) * k
        let shift = 28 * CGFloat(min(max(lean, -1), 1))
        let cardShift = shift * min(1, c * 4)
        let warp = Warp(cx: 512 + cardShift, cy: 512,
                        kx: halfWidth / Self.A * k,
                        ky: lerp(Self.rest, Self.pressedHalfHeight, c) / Self.A * k,
                        bow: Self.pressedBow * c)
        let pressure = min(c, 1.2)
        let leftFace = 512 + shift - face, rightFace = 512 + shift + face

        // Card
        let A = Self.A
        let steps = fine ? (corner: 6, edge: 12) : (corner: 3, edge: 6)
        let card = warp.path(Self.roundedRect(A, A, r: 44, steps))
        let windowHalf = (x: A - lerp(46, 40, c), y: A - lerp(46, 54, c))
        let window = warp.path(Self.roundedRect(windowHalf.x, windowHalf.y, r: 22, steps))
        let cardBox = card.boundingRect

        // The shadow filter applies to each drawing operation, so the card is
        // drawn into an inner layer that casts one shadow.
        ctx.drawLayer { outer in
            if fine { outer.addFilter(.shadow(color: .black.opacity(dark ? 0.5 : 0.2), radius: 16, x: 0, y: 12)) }
            outer.drawLayer { l in
                l.fill(card, with: .linearGradient(Gradient(colors: dark ? [Palette.sky0Dark, Palette.sky1Dark] : [Palette.sky0, Palette.sky1]),
                                                   startPoint: CGPoint(x: 0, y: cardBox.minY), endPoint: CGPoint(x: 0, y: cardBox.maxY)))
                l.drawLayer { p in
                    p.clip(to: window)
                    drawPicture(in: &p, warp: warp, squash: c, steps: fine ? 48 : 12, dark: dark)
                    if fine, pressure > 0 {
                        // Darker where the jaws press, a faint lift in the middle.
                        p.fill(Path(cardBox), with: .linearGradient(
                            Gradient(stops: [.init(color: Palette.press.opacity(0.38 * pressure), location: 0),
                                             .init(color: Palette.press.opacity(0), location: 0.2),
                                             .init(color: .white.opacity(0.08 * pressure), location: 0.5),
                                             .init(color: Palette.press.opacity(0), location: 0.8),
                                             .init(color: Palette.press.opacity(0.38 * pressure), location: 1)]),
                            startPoint: CGPoint(x: leftFace, y: 0), endPoint: CGPoint(x: rightFace, y: 0)))
                    }
                }
                // The white print border.
                var mat = card
                mat.addPath(window)
                l.fill(mat, with: .color((dark ? Palette.matDark : .white).opacity(0.95)), style: FillStyle(eoFill: true))
                if fine, pressure > 0 {
                    l.drawLayer { m in
                        m.clip(to: mat, style: FillStyle(eoFill: true))
                        m.fill(Path(cardBox), with: .linearGradient(
                            Gradient(stops: [.init(color: Palette.matShade.opacity(0.18 * pressure), location: 0),
                                             .init(color: Palette.matShade.opacity(0), location: 0.12),
                                             .init(color: Palette.matShade.opacity(0), location: 0.88),
                                             .init(color: Palette.matShade.opacity(0.18 * pressure), location: 1)]),
                            startPoint: CGPoint(x: leftFace, y: 0), endPoint: CGPoint(x: rightFace, y: 0)))
                    }
                }
            }
        }
        // A hairline keeps the white border off a light background.
        if !dark {
            ctx.stroke(card, with: .color(.black.opacity(0.14)), lineWidth: 1 / scale)
        }

        // Jaws
        drawJaw(in: &ctx, face: leftFace, left: true, fine: fine, dark: dark)
        drawJaw(in: &ctx, face: rightFace, left: false, fine: fine, dark: dark)
    }

    /// Sky is the card's own fill; this adds the sun and the two hills.
    private func drawPicture(in ctx: inout GraphicsContext, warp: Warp, squash: CGFloat, steps n: Int, dark: Bool) {
        let A = Self.A
        // The sun narrows to 0.62 of its width at the icon's pose, on top of the card's squeeze.
        let sunWidth = 70 * max(0.4, lerp(1, 0.62, squash))
        let sun = (0..<n).map { i -> CGPoint in
            let t = CGFloat(i) / CGFloat(n) * 2 * .pi
            return CGPoint(x: -120 + sunWidth * cos(t), y: -120 + 70 * sin(t))
        }
        ctx.fill(warp.path(sun), with: .color(dark ? Palette.sunDark : Palette.sun))

        func hill(_ ridge: (CGFloat) -> CGFloat) -> Path {
            // The bottom is sampled too so it bows with the card and no sky shows under it.
            let top = (0...n).map { i -> CGPoint in
                let x = -A + 2 * A * CGFloat(i) / CGFloat(n)
                return CGPoint(x: x, y: ridge(x))
            }
            let bottom = (0...n).map { i in CGPoint(x: A - 2 * A * CGFloat(i) / CGFloat(n), y: A) }
            return warp.path(top + bottom)
        }
        let back = hill { x in 70 - 125 * exp(-pow((x - 120) / 150, 2)) }
        let front = hill { x in 150 - 125 * exp(-pow((x + 150) / 165, 2)) - 20 * (x / A) }
        for (path, colors) in [(back, dark ? [Palette.back0Dark, Palette.back1Dark] : [Palette.back0, Palette.back1]),
                               (front, dark ? [Palette.front0Dark, Palette.front1Dark] : [Palette.front0, Palette.front1])] {
            let box = path.boundingRect
            ctx.fill(path, with: .linearGradient(Gradient(colors: colors),
                                                 startPoint: CGPoint(x: 0, y: box.minY), endPoint: CGPoint(x: 0, y: box.maxY)))
        }
    }

    /// One orange slab, its pressing face at `face`, rounded more on the face
    /// side. Lit along the top, shaded along the bottom, with a darker band
    /// on the pressing face that ends in a light edge.
    private func drawJaw(in ctx: inout GraphicsContext, face: CGFloat, left: Bool, fine: Bool, dark: Bool) {
        let (top, bottom, w) = (Self.jawTop, Self.jawBottom, Self.jawWidth)
        let rect = CGRect(x: left ? face - w : face, y: top, width: w, height: bottom - top)
        let (f, b) = (Self.faceRadius, Self.backRadius)
        let radii = left ? RectangleCornerRadii(topLeading: b, bottomLeading: b, bottomTrailing: f, topTrailing: f)
                         : RectangleCornerRadii(topLeading: f, bottomLeading: f, bottomTrailing: b, topTrailing: b)
        let jaw = UnevenRoundedRectangle(cornerRadii: radii, style: .circular).path(in: rect)
        func vertical(_ stops: [Gradient.Stop], _ y0: CGFloat, _ y1: CGFloat) -> GraphicsContext.Shading {
            .linearGradient(Gradient(stops: stops), startPoint: CGPoint(x: 0, y: y0), endPoint: CGPoint(x: 0, y: y1))
        }

        ctx.drawLayer { l in
            if fine { l.addFilter(.shadow(color: .black.opacity(dark ? 0.55 : 0.28), radius: 18, x: 0, y: 14)) }
            l.fill(jaw, with: .linearGradient(Gradient(colors: dark ? [Palette.jaw0Dark, Palette.jaw1Dark] : [Palette.jaw0, Palette.jaw1]),
                                              startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: bottom)))
        }
        ctx.drawLayer { l in
            l.clip(to: jaw)
            // Sheen along the top.
            l.fill(Path(rect), with: vertical([.init(color: .white.opacity(0.32), location: 0),
                                                .init(color: .white.opacity(0), location: 1)], top, top + 140))
            // Pressing face: a band that darkens toward the card and ends in a light edge.
            let band: CGFloat = 56
            let edge = Gradient(stops: [.init(color: Palette.burn.opacity(0), location: 0),
                                        .init(color: Palette.burn.opacity(0.26), location: 0.35),
                                        .init(color: Palette.burn.opacity(0.34), location: 0.8),
                                        .init(color: Palette.faceEdge.opacity(0.55), location: 1)])
            l.fill(Path(CGRect(x: left ? face - band : face, y: top, width: band, height: bottom - top)),
                   with: .linearGradient(edge, startPoint: CGPoint(x: left ? face - band : face + band, y: 0),
                                         endPoint: CGPoint(x: face, y: 0)))
            guard fine else { return }
            // Soft bevel: lit over the top 9 %, shaded over the bottom 14 %.
            l.fill(Path(rect), with: vertical([.init(color: .white.opacity(0.5), location: 0),
                                                .init(color: .white.opacity(0), location: 0.09),
                                                .init(color: Palette.burn.opacity(0), location: 0.86),
                                                .init(color: Palette.burn.opacity(0.4), location: 1)], top, bottom))
        }
    }

    // MARK: - Shapes

    /// Points round a rounded rect centred on (0, 0) in photo space, with the
    /// straight runs sampled too so they bow under the warp.
    private static func roundedRect(_ hw: CGFloat, _ hh: CGFloat, r: CGFloat,
                                    _ steps: (corner: Int, edge: Int)) -> [CGPoint] {
        let centres = [CGPoint(x: hw - r, y: -hh + r), CGPoint(x: hw - r, y: hh - r),
                       CGPoint(x: -hw + r, y: hh - r), CGPoint(x: -hw + r, y: -hh + r)]
        var points: [CGPoint] = []
        for (i, c) in centres.enumerated() {
            let a0 = CGFloat(i - 1) * .pi / 2
            for j in 0...steps.corner {
                let a = a0 + .pi / 2 * CGFloat(j) / CGFloat(steps.corner)
                points.append(CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a)))
            }
            let end = points[points.count - 1]
            let next = centres[(i + 1) % 4]
            let a1 = a0 + .pi / 2
            let start = CGPoint(x: next.x + r * cos(a1), y: next.y + r * sin(a1))
            for j in 1..<steps.edge {
                let t = CGFloat(j) / CGFloat(steps.edge)
                points.append(CGPoint(x: end.x + (start.x - end.x) * t, y: end.y + (start.y - end.y) * t))
            }
        }
        return points
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
}

/// The icon's colors (Squish.icon): light, and the icon's dark appearance.
enum Palette {
    static let jaw0 = Color(hex: 0xFFA44E), jaw1 = Color(hex: 0xE2501A)
    static let jaw0Dark = Color(hex: 0xF58A3A), jaw1Dark = Color(hex: 0xB93E0C)
    /// Shading on the jaws' bottom edge and pressing face, and the face's lit edge.
    static let burn = Color(hex: 0x5A1A00), faceEdge = Color(hex: 0xFFE2C4)
    static let matDark = Color(hex: 0xE9ECF4)
    /// Pressure shading on the picture and on the border.
    static let press = Color(hex: 0x0A1030), matShade = Color(hex: 0x1A2350)
    static let sky0 = Color(hex: 0x2F8BFF), sky1 = Color(hex: 0x9FD6FF)
    static let sky0Dark = Color(hex: 0x245FC8), sky1Dark = Color(hex: 0x6FA8E8)
    static let sun = Color(hex: 0xFFD84A), sunDark = Color(hex: 0xFFE07A)
    static let back0 = Color(hex: 0x8EDB6A), back1 = Color(hex: 0x56B451)
    static let back0Dark = Color(hex: 0x6CB75A), back1Dark = Color(hex: 0x3F8A3E)
    static let front0 = Color(hex: 0x4CC45C), front1 = Color(hex: 0x23863C)
    static let front0Dark = Color(hex: 0x3AA14C), front1Dark = Color(hex: 0x195F2B)
}

private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

#Preview("Squeeze") {
    HStack(spacing: 20) {
        ForEach([0, Double(PressView.contact), 0.55, 1, 1.15], id: \.self) { s in
            PressView(squeeze: s).frame(width: 160)
        }
    }
    .padding()
}
