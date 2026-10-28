import SwiftUI

/// The app icon's clamp, drawn live so it can react: the screw winds down and
/// the photo squashes as `squeeze` goes from 0 (open) to 1 (fully clamped),
/// and the T-handle turns with `twist` (radians).
///
/// Geometry is authored in the icon's 1024-point space (see Icon/Source) so the
/// window art and the app icon stay the same object.
struct ClampView: View, Animatable {
    var squeeze: Double
    var twist: Double = 0
    /// Shrinks the photo (1 = full size) to act out a pixel limit.
    var photoScale: Double = 1

    nonisolated var animatableData: AnimatablePair<AnimatablePair<Double, Double>, Double> {
        get { AnimatablePair(AnimatablePair(squeeze, twist), photoScale) }
        set { squeeze = newValue.first.first; twist = newValue.first.second; photoScale = newValue.second }
    }

    @Environment(\.colorScheme) private var scheme

    // Visible part of the 1024 canvas.
    private static let art = CGRect(x: 120, y: 20, width: 780, height: 840)

    var body: some View {
        Canvas { ctx, size in
            let a = Self.art
            let scale = min(size.width / a.width, size.height / a.height)
            ctx.translateBy(x: (size.width - a.width * scale) / 2 - a.minX * scale,
                            y: (size.height - a.height * scale) / 2 - a.minY * scale)
            ctx.scaleBy(x: scale, y: scale)
            draw(in: &ctx)
        }
        .aspectRatio(Self.art.width / Self.art.height, contentMode: .fit)
        .accessibilityHidden(true)
    }

    // MARK: - Drawing

    private func draw(in ctx: inout GraphicsContext) {
        let s = CGFloat(min(max(squeeze, 0), 1.15))

        // Photo: sits on the lower jaw, gets shorter, wider and rounder as it's squeezed.
        let bottom: CGFloat = 698
        let k = CGFloat(min(max(photoScale, 0.3), 1))
        let w = lerp(420, 454, s) * k, h = lerp(360, 310, s) * k, bulge = lerp(0, 22, s) * k
        let photo = CGRect(x: 441 - w / 2, y: bottom - h, width: w, height: h)

        // Screw: the pad rests `gap` above the photo; rod and handle ride on the pad.
        let padTop = photo.minY - lerp(40, 0, min(s, 1)) - 46
        let rodTop = padTop - 200

        let shadow = GraphicsContext.Filter.shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.22),
                                                   radius: 18, x: 0, y: 14)

        // Photo
        ctx.drawLayer { l in
            l.addFilter(shadow)
            let outline = Self.barrel(photo, r: 30 * k, bulge: bulge)
            l.clip(to: outline)
            l.fill(Path(photo.insetBy(dx: -bulge - 4, dy: -4)),
                   with: .linearGradient(Gradient(colors: [Palette.sky0, Palette.sky1]),
                                         startPoint: CGPoint(x: 0, y: photo.minY), endPoint: CGPoint(x: 0, y: photo.maxY)))
            let sunR = min(photo.width, photo.height) * 0.104
            l.fill(Path(ellipseIn: CGRect(x: photo.minX + photo.width * 0.72 - sunR, y: photo.minY + photo.height * 0.32 - sunR,
                                          width: sunR * 2, height: sunR * 2)), with: .color(Palette.sun))
            let (back, front) = Self.hills(x0: photo.minX - 40, x1: photo.maxX + 40, base: photo.maxY + 30, h: photo.height * 0.55)
            l.fill(back, with: .color(Palette.hill1))
            l.fill(front, with: .color(Palette.hill2))
        }

        // Frame
        ctx.drawLayer { l in
            l.addFilter(shadow)
            l.fill(Self.frame, with: .linearGradient(Gradient(colors: [Palette.orange0, Palette.orange1]),
                                                    startPoint: CGPoint(x: 0, y: 200), endPoint: CGPoint(x: 0, y: 824)))
        }
        // A soft top-lit sheen so the frame reads as an object, not a sticker.
        ctx.drawLayer { l in
            l.clip(to: Self.frame)
            l.fill(Path(CGRect(x: 120, y: 190, width: 760, height: 90)),
                   with: .linearGradient(Gradient(colors: [.white.opacity(0.35), .white.opacity(0)]),
                                         startPoint: CGPoint(x: 0, y: 200), endPoint: CGPoint(x: 0, y: 280)))
        }

        // Rod and pad: silver on dark, gray on light so they read against the window.
        let metal = scheme == .dark ? [Palette.steel0, .white, Palette.steel1] : [Palette.slate0, Palette.slate1]
        let steel = GraphicsContext.Shading.linearGradient(Gradient(colors: metal),
                                                           startPoint: CGPoint(x: 415, y: 0), endPoint: CGPoint(x: 467, y: 0))
        ctx.fill(Path(roundedRect: CGRect(x: 415, y: rodTop, width: 52, height: padTop - rodTop + 10), cornerRadius: 14), with: steel)
        ctx.drawLayer { l in
            l.addFilter(.shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 4))
            l.fill(Path(roundedRect: CGRect(x: 331, y: padTop, width: 220, height: 46), cornerRadius: 16),
                   with: .linearGradient(Gradient(colors: metal),
                                         startPoint: CGPoint(x: 331, y: 0), endPoint: CGPoint(x: 551, y: 0)))
        }

        // T-handle, foreshortened as it turns.
        let turn = abs(cos(twist))
        let hw = 260 * max(turn, 0.2)
        let handle = Path(roundedRect: CGRect(x: 441 - hw / 2, y: rodTop - 22, width: hw, height: 48), cornerRadius: 24)
        let (h0, h1) = scheme == .dark ? (Palette.graphite0, Palette.graphite1) : (Palette.ink0, Palette.ink1)
        ctx.fill(handle, with: .linearGradient(Gradient(colors: [h0, h1]),
                                               startPoint: CGPoint(x: 0, y: rodTop - 22), endPoint: CGPoint(x: 0, y: rodTop + 26)))
        // Catch-light that slides across the bar while it turns.
        let glint = (sin(twist) + 1) / 2
        ctx.fill(Path(roundedRect: CGRect(x: 441 - hw / 2 + 10, y: rodTop - 16, width: max(hw - 20, 0), height: 10), cornerRadius: 5),
                 with: .color(.white.opacity(0.18 + 0.2 * glint)))
    }

    // MARK: - Shapes (ported from Icon/Source/gen.py)

    private static let frame: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 196, y: 200))
        p.addArc(tangent1End: CGPoint(x: 856, y: 200), tangent2End: CGPoint(x: 856, y: 296), radius: 96)
        p.addArc(tangent1End: CGPoint(x: 856, y: 824), tangent2End: CGPoint(x: 760, y: 824), radius: 96)
        p.addArc(tangent1End: CGPoint(x: 156, y: 824), tangent2End: CGPoint(x: 156, y: 784), radius: 40)
        p.addArc(tangent1End: CGPoint(x: 156, y: 704), tangent2End: CGPoint(x: 196, y: 704), radius: 40)
        p.addLine(to: CGPoint(x: 720, y: 704))
        p.addLine(to: CGPoint(x: 720, y: 320))
        p.addLine(to: CGPoint(x: 196, y: 320))
        p.addArc(tangent1End: CGPoint(x: 156, y: 320), tangent2End: CGPoint(x: 156, y: 280), radius: 40)
        p.addArc(tangent1End: CGPoint(x: 156, y: 200), tangent2End: CGPoint(x: 196, y: 200), radius: 40)
        p.closeSubpath()
        return p
    }()

    /// A rounded rect whose left and right sides bulge outward.
    private static func barrel(_ r: CGRect, r cr: CGFloat, bulge b: CGFloat) -> Path {
        let (x0, y0, x1, y1) = (r.minX, r.minY, r.maxX, r.maxY)
        let my = r.midY
        var p = Path()
        p.move(to: CGPoint(x: x0 + cr, y: y0))
        p.addLine(to: CGPoint(x: x1 - cr, y: y0))
        p.addQuadCurve(to: CGPoint(x: x1 + b * 0.35, y: y0 + cr * 0.9), control: CGPoint(x: x1, y: y0))
        p.addCurve(to: CGPoint(x: x1 + b * 0.35, y: y1 - cr * 0.9),
                   control1: CGPoint(x: x1 + b, y: y0 + (my - y0) * 0.6), control2: CGPoint(x: x1 + b, y: y1 - (y1 - my) * 0.6))
        p.addQuadCurve(to: CGPoint(x: x1 - cr, y: y1), control: CGPoint(x: x1, y: y1))
        p.addLine(to: CGPoint(x: x0 + cr, y: y1))
        p.addQuadCurve(to: CGPoint(x: x0 - b * 0.35, y: y1 - cr * 0.9), control: CGPoint(x: x0, y: y1))
        p.addCurve(to: CGPoint(x: x0 - b * 0.35, y: y0 + cr * 0.9),
                   control1: CGPoint(x: x0 - b, y: y1 - (y1 - my) * 0.6), control2: CGPoint(x: x0 - b, y: y0 + (my - y0) * 0.6))
        p.addQuadCurve(to: CGPoint(x: x0 + cr, y: y0), control: CGPoint(x: x0, y: y0))
        p.closeSubpath()
        return p
    }

    /// Two rolling hills spanning x0…x1 whose tops sit around `base - h`.
    private static func hills(x0: CGFloat, x1: CGFloat, base: CGFloat, h: CGFloat) -> (Path, Path) {
        let w = x1 - x0
        func pt(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { CGPoint(x: x0 + fx * w, y: base - h * fy) }
        var back = Path()
        back.move(to: CGPoint(x: x0 - 0.05 * w, y: base + 40))
        back.addLine(to: pt(-0.05, 0.55))
        back.addCurve(to: pt(0.40, 1.0), control1: pt(0.15, 0.85), control2: pt(0.28, 1.0))
        back.addCurve(to: pt(0.70, 0.62), control1: pt(0.52, 1.0), control2: pt(0.60, 0.70))
        back.addCurve(to: pt(1.05, 0.80), control1: pt(0.82, 0.54), control2: pt(0.95, 0.72))
        back.addLine(to: CGPoint(x: x0 + 1.05 * w, y: base + 40))
        back.closeSubpath()

        var front = Path()
        front.move(to: CGPoint(x: x0 - 0.05 * w, y: base + 40))
        front.addLine(to: pt(-0.05, 0.30))
        front.addCurve(to: pt(0.42, 0.58), control1: pt(0.12, 0.42), control2: pt(0.26, 0.62))
        front.addCurve(to: pt(0.86, 0.34), control1: pt(0.58, 0.54), control2: pt(0.70, 0.30))
        front.addCurve(to: pt(1.05, 0.44), control1: pt(0.94, 0.36), control2: pt(1.0, 0.42))
        front.addLine(to: CGPoint(x: x0 + 1.05 * w, y: base + 40))
        front.closeSubpath()
        return (back, front)
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
}

/// Colors shared by the icon and the in-app art ("Dusk" scene).
enum Palette {
    static let sky0 = Color(.displayP3, red: 0.294, green: 0.357, blue: 1.0)
    static let sky1 = Color(.displayP3, red: 1.0, green: 0.702, blue: 0.541)
    static let sun = Color(.displayP3, red: 1.0, green: 0.906, blue: 0.639)
    static let hill1 = Color(.displayP3, red: 0.553, green: 0.388, blue: 0.851)
    static let hill2 = Color(.displayP3, red: 0.290, green: 0.184, blue: 0.561)
    static let orange0 = Color(.displayP3, red: 1.0, green: 0.58, blue: 0.22)
    static let orange1 = Color(.displayP3, red: 0.95, green: 0.30, blue: 0.16)
    static let steel0 = Color(red: 0.851, green: 0.867, blue: 0.886)
    static let steel1 = Color(red: 0.663, green: 0.690, blue: 0.722)
    static let slate0 = Color(.displayP3, red: 0.50, green: 0.51, blue: 0.55)
    static let slate1 = Color(.displayP3, red: 0.30, green: 0.31, blue: 0.34)
    static let ink0 = Color(.displayP3, red: 0.24, green: 0.24, blue: 0.27)
    static let ink1 = Color(.displayP3, red: 0.10, green: 0.10, blue: 0.12)
    static let graphite0 = Color(.displayP3, red: 0.78, green: 0.80, blue: 0.84)
    static let graphite1 = Color(.displayP3, red: 0.52, green: 0.54, blue: 0.59)
}

extension NSColor {
    /// Accent for text: deep enough to read on light backgrounds, bright on dark.
    static let squishInk = NSColor(name: "squishInk") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(displayP3Red: 1.0, green: 0.56, blue: 0.36, alpha: 1)
            : NSColor(displayP3Red: 0.82, green: 0.29, blue: 0.10, alpha: 1)
    }
}

extension Color {
    static let squishInk = Color(nsColor: .squishInk)
}
