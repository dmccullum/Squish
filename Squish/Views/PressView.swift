import SwiftUI

/// The app icon's press, drawn live: two orange jaws close on a square photo
/// card as `squeeze` goes from 0 (open) to 1 (the deepest squeeze).
///
/// - 0 to `contact`: the jaws slide in from the edges; the card stays a flat
///   square.
/// - `contact` to `pose`: the jaws push the card's sides in, its top and
///   bottom bow outward and the picture narrows. At `pose` it matches the
///   icon: jaw faces on x 256 and 768, card corners on y 256 and 768, edges
///   bowing to y 192 and 832.
/// - `pose` to 1: the card narrows further and crumples. Creases appear by
///   the jaws first and spread inward, the picture follows them, and the top
///   and bottom edges turn wavy.
/// - Up to 1.15: extra squash for the About window's pop.
///
/// Geometry is authored in the icon's 1024-point space (the icon is generated
/// by `build2.py`, variant `r2-6-bulgejaws`) so the window art and the app
/// icon stay the same object.
@Animatable
struct PressView: View {
    /// How the jaws meet the view's edges.
    enum Framing {
        /// The jaws run in from the view's left and right edges; the art is as
        /// wide as the view and scales with its height. For a view that spans
        /// a window.
        case bleed
        /// A rounded navy tile with the jaws running off its edges, like the
        /// icon. For small sizes with no window edge nearby.
        case tile
    }

    var squeeze: Double
    @AnimatableIgnored var framing: Framing = .tile

    @AnimatableIgnored @Environment(\.colorScheme) private var scheme

    /// The squeeze at which the jaws reach the card's sides.
    static let contact = 0.18
    /// The squeeze at which the press matches the icon; crumpling starts here.
    static let pose = 0.55

    var body: some View {
        let canvas = Canvas { ctx, size in
            let scale: CGFloat, edge: CGFloat
            switch framing {
            case .bleed:
                // Units 116…916 fill the layout height; the canvas runs
                // `bleedOverflow` beyond it above and below so the card's bloom
                // fades out before any edge. The width shows as much as fits.
                scale = size.height / (800 * (1 + 2 * Self.bleedOverflow))
                edge = size.width / 2 / scale
                ctx.translateBy(x: size.width / 2 - 512 * scale, y: size.height / 2 - 516 * scale)
            case .tile:
                let side = min(size.width, size.height)
                scale = side / 1024
                edge = 512
                ctx.translateBy(x: (size.width - side) / 2, y: (size.height - side) / 2)
            }
            ctx.scaleBy(x: scale, y: scale)
            draw(in: &ctx, scale: scale, edge: edge)
        }
        .accessibilityHidden(true)
        switch framing {
        case .bleed:
            // Laid out at the art's own height; the canvas draws taller, outside
            // it, and never takes clicks.
            Color.clear
                .overlay {
                    GeometryReader { geo in
                        let extra = geo.size.height * Self.bleedOverflow
                        canvas
                            .frame(width: geo.size.width, height: geo.size.height + 2 * extra)
                            .offset(y: -extra)
                            .allowsHitTesting(false)
                    }
                }
        case .tile: canvas.aspectRatio(1, contentMode: .fit)
        }
    }

    /// How far the bleed canvas reaches past its layout frame, above and below,
    /// as a share of the frame's height: room for the bloom to fade out.
    private static let bleedOverflow: CGFloat = 0.22

    // MARK: - Geometry

    /// Photo space: the card is a square centred on (0, 0), half-size `A`.
    private static let A: CGFloat = 320
    /// Card half-size at rest; half-width and half-height at the jaws at the
    /// icon's pose; and half-width at the deepest squeeze.
    private static let rest: CGFloat = 300
    private static let poseHalfWidth: CGFloat = 272
    private static let poseHalfHeight: CGFloat = 256
    private static let deepHalfWidth: CGFloat = 242
    /// How far the top and bottom bow out at the centre at the icon's pose,
    /// as a fraction of the half-height: 256 × 1.25 = 320, so y 192 and 832.
    private static let poseBow: CGFloat = 0.25
    /// The card runs this far under each jaw face once gripped.
    private static let overlap: CGFloat = 16
    private static let jawTop: CGFloat = 128, jawBottom: CGFloat = 896
    private static let faceRadius: CGFloat = 96
    /// Jaw face distance from the centre at rest in a tile, and the least it
    /// may be in a bleed, so the gap to the card stays clear.
    private static let tileOpenFace: CGFloat = 384
    /// How much of each jaw shows at rest when it bleeds off a window edge.
    private static let bleedStub: CGFloat = 190

    /// A fold running down the card, a little off vertical: where it meets
    /// the top and bottom edges (−1…1 across the card), the crumple at which
    /// it starts, and whether it pushes the edges out (a ridge) or in (a
    /// valley).
    private struct Crease { var top: CGFloat, bottom: CGFloat, start: CGFloat, ridge: Bool }
    /// By the jaws first, then spreading inward, each at its own slant so they
    /// read as crumpling rather than pleats.
    private static let creases = [Crease(top: -0.68, bottom: -0.56, start: 0, ridge: true),
                                  Crease(top: 0.6, bottom: 0.72, start: 0.06, ridge: true),
                                  Crease(top: -0.22, bottom: -0.36, start: 0.3, ridge: false),
                                  Crease(top: 0.4, bottom: 0.27, start: 0.42, ridge: false),
                                  Crease(top: 0.08, bottom: -0.04, start: 0.7, ridge: true)]
    /// Below the detail threshold only two folds, so a 46-point tile stays legible.
    private static let smallCreases = [Crease(top: -0.5, bottom: -0.42, start: 0, ridge: true),
                                       Crease(top: 0.44, bottom: 0.52, start: 0.1, ridge: true)]

    /// A crease with its strength, 0…1.
    private struct Fold {
        var crease: Crease, a: CGFloat
        /// Where the fold crosses height `v` (−1 top … 1 bottom).
        func u(at v: CGFloat) -> CGFloat {
            crease.top + (crease.bottom - crease.top) * (min(max(v, -1), 1) + 1) / 2
        }
    }

    /// Maps photo space onto the canvas: scales x and y, bows the top and
    /// bottom edges out, then adds the folds.
    private struct Warp {
        var cx: CGFloat, cy: CGFloat, kx: CGFloat, ky: CGFloat, bow: CGFloat
        var folds: [Fold]
        /// 0 until the card crumples; ripples the top and bottom edges.
        var ragged: CGFloat

        func callAsFunction(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            let A = PressView.A
            let u = min(max(x / A, -1.2), 1.2), v = min(max(y / A, -1.2), 1.2)
            var dx: CGFloat = 0, out: CGFloat = 0
            for f in folds where f.a > 0 {
                let d = u - f.u(at: v)
                // Material gathers into the fold, so lines across it step; the
                // outline swells (or dips) smoothly where it meets the edge.
                dx -= f.a * 6 * tanh(d / 0.06) * (1 - min(u * u * u * u, 1))
                let reach: CGFloat = 0.3
                if abs(d) < reach { out += f.a * (f.crease.ridge ? 13 : -6) * (1 + cos(.pi * d / reach)) / 2 }
            }
            out += ragged * 3 * sin(u * 21 + 1.3) * pow(abs(v), 4)
            let edgeWeight = abs(v)   // 0 through the middle, 1 at the top and bottom edges
            return CGPoint(x: cx + (x + dx) * kx,
                           y: cy + y * ky * (1 + bow * (1 - u * u)) + (v < 0 ? -1 : 1) * out * edgeWeight)
        }

        func path(_ points: [CGPoint]) -> Path {
            var p = Path()
            p.addLines(points.map { self($0.x, $0.y) })
            p.closeSubpath()
            return p
        }
    }

    // MARK: - Drawing

    private func draw(in ctx: inout GraphicsContext, scale: CGFloat, edge: CGFloat) {
        let s = CGFloat(min(max(squeeze, 0), 1.15))
        let contact = CGFloat(Self.contact), pose = CGFloat(Self.pose)
        // c: 0 at contact to 1 at the icon's pose. k: the crumple, 0 at the pose,
        // 1 at the deepest squeeze, about 1.33 at the pop.
        let c = min(max((s - contact) / (pose - contact), 0), 1)
        let k = max(0, (s - pose) / (1 - pose))
        // Below about 0.15 (the size menu's 46-point tile and the results header)
        // shadows, bevels and pressure shading are under a pixel, so they're skipped.
        let fine = scale > 0.15
        let dark = scheme == .dark

        if framing == .tile {
            let tile = Path(roundedRect: CGRect(x: 0, y: 0, width: 1024, height: 1024), cornerRadius: 230, style: .continuous)
            ctx.clip(to: tile)
            ctx.fill(tile, with: .linearGradient(Gradient(colors: dark ? [Palette.tile0Dark, Palette.tile1Dark] : [Palette.tile0, Palette.tile1]),
                                                 startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: 1024)))
        }

        let halfWidth = lerp(Self.rest, Self.poseHalfWidth, c) - (Self.poseHalfWidth - Self.deepHalfWidth) * k
        let openFace = framing == .tile ? Self.tileOpenFace : max(edge - Self.bleedStub, Self.tileOpenFace)
        let face = s < contact ? lerp(openFace, Self.rest - Self.overlap, s / contact) : halfWidth - Self.overlap
        let gates = fine ? Self.creases : Self.smallCreases
        let folds = gates.map { g in Fold(crease: g, a: min(max((k - g.start) / 0.35, 0), 1) * (0.6 + 0.4 * min(k, 1.33))) }
        let warp = Warp(cx: 512, cy: 512,
                        kx: halfWidth / Self.A,
                        ky: (lerp(Self.rest, Self.poseHalfHeight, c) - 8 * k) / Self.A,
                        bow: Self.poseBow * c + 0.08 * k,
                        folds: folds, ragged: fine ? min(k, 1.33) : 0)
        let pressure = min(c + 0.3 * k, 1.4)
        let leftFace = 512 - face, rightFace = 512 + face

        // Card
        let A = Self.A
        let steps = fine ? (corner: 6, edge: 32) : (corner: 3, edge: 10)
        let card = warp.path(Self.roundedRect(A, A, r: 44, steps))
        let windowHalf = (x: A - lerp(46, 40, c), y: A - lerp(46, 54, c))
        let window = warp.path(Self.roundedRect(windowHalf.x, windowHalf.y, r: 22, steps))
        let cardBox = card.boundingRect

        // How brightly the card lights each jaw: from each jaw's gap as a share
        // of the rest gap, lifted up to 15 % more while pressing so a running
        // batch reads as more intense than a grip.
        let cardLeft = warp(-A, 0).x, cardRight = warp(A, 0).x
        let restGap = openFace - Self.rest
        let lift = 1 + 0.15 * min(max((s - contact) / (1 - contact), 0), 1)
        let leftLight = Self.rimLight(gap: cardLeft - leftFace, restGap: restGap) * lift
        let rightLight = Self.rimLight(gap: rightFace - cardRight, restGap: restGap) * lift

        // The card is a light source: a constant bloom spreads outward from its
        // whole outline, behind it, following its bow and folds.
        if fine {
            drawBloom(in: &ctx, card: card, box: cardBox, dark: dark)
        }

        // The shadow filter applies to each drawing operation, so the card is
        // drawn into an inner layer that casts one shadow.
        ctx.drawLayer { outer in
            // A lit panel casts only a light shadow.
            if fine { outer.addFilter(.shadow(color: .black.opacity(dark ? 0.3 : 0.18), radius: 16, x: 0, y: 12)) }
            outer.drawLayer { l in
                l.fill(card, with: .linearGradient(Gradient(colors: dark ? [Palette.sky0Dark, Palette.sky1Dark] : [Palette.sky0, Palette.sky1]),
                                                   startPoint: CGPoint(x: 0, y: cardBox.minY), endPoint: CGPoint(x: 0, y: cardBox.maxY)))
                l.drawLayer { p in
                    p.clip(to: window)
                    drawPicture(in: &p, warp: warp, squash: c, crumple: k, steps: fine ? 48 : 14, dark: dark,
                                backlit: Self.cardLight == .panel && fine)
                    if Self.cardLight == .panel, fine {
                        // Backlit: light from behind the picture, brightest in the middle.
                        var lit = p
                        lit.blendMode = .plusLighter
                        lit.fill(Path(cardBox), with: .radialGradient(
                            Gradient(colors: [(dark ? Palette.moonlight : .white).opacity(dark ? 0.2 : 0.14), .clear]),
                            center: CGPoint(x: 512, y: 470), startRadius: 0, endRadius: max(cardBox.width, cardBox.height) * 0.7))
                    }
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
                if Self.cardLight == .border {
                    // Lit from within: brighter than paper, with a luminous outer
                    // edge and a faint falloff toward the photo.
                    l.fill(mat, with: .color(dark ? Palette.emitDark : .white), style: FillStyle(eoFill: true))
                    if fine {
                        l.drawLayer { m in
                            m.clip(to: mat, style: FillStyle(eoFill: true))
                            m.drawLayer { e in
                                e.addFilter(.blur(radius: 8))
                                e.stroke(window, with: .color(Palette.matShade.opacity(dark ? 0.22 : 0.12)), lineWidth: 10)
                            }
                            m.blendMode = .plusLighter
                            m.drawLayer { e in
                                e.addFilter(.blur(radius: 5))
                                e.stroke(card, with: .color(.white.opacity(0.7)), lineWidth: 10)
                            }
                        }
                    }
                } else {
                    l.fill(mat, with: .color((dark ? Palette.matDark : .white).opacity(0.95)), style: FillStyle(eoFill: true))
                }
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
                // Folds: each a soft shadow on its jaw side and a softer highlight toward the middle.
                let active = warp.folds.filter { $0.a > 0.01 }
                if !active.isEmpty {
                    l.drawLayer { f in
                        f.clip(to: card)
                        for fold in active { drawFold(fold, in: &f, warp: warp, fine: fine) }
                    }
                }
            }
        }
        // A hairline keeps the white border off a light window background.
        if !dark, framing == .bleed {
            ctx.stroke(card, with: .color(.black.opacity(0.14)), lineWidth: 1 / scale)
        }

        // Jaws: each runs from past the edge in to its face, its face lit by
        // the card according to its own gap.
        let far = 512 - edge - 80
        let cardHalfHeight = 512 - warp(-A, -A).y
        drawJaw(in: &ctx, from: far, to: leftFace, light: leftLight,
                cardHalfHeight: cardHalfHeight, gap: cardLeft - leftFace, fine: fine, dark: dark)
        drawJaw(in: &ctx, from: 1024 - far, to: rightFace, light: rightLight,
                cardHalfHeight: cardHalfHeight, gap: rightFace - cardRight, fine: fine, dark: dark)
    }

    /// What gives off the card's light (see `drawBloom`).
    enum CardLight {
        /// The white mat is lit from within, like a backlit frame.
        case border
        /// The whole picture is backlit, like a lightbox or a display.
        case panel
    }
    static let cardLight: CardLight = .panel

    /// Light spilling outward from the card onto whatever is behind it: a wide
    /// soft bloom and a tighter one from the whole outline, at a constant
    /// strength (the card is the light source; the jaws catch more of it as
    /// they close in, which `rimLight` covers). Moonlit at night and warm by
    /// day; the backlit picture tints its bloom by the scene, sky above and
    /// hills below. Added with plus-lighter and drawn behind the card and the
    /// jaws, so it never stacks on the jaws' own rim light.
    private func drawBloom(in ctx: inout GraphicsContext, card: Path, box: CGRect, dark: Bool) {
        let base = dark ? Palette.moonlight : Palette.spill
        let (top, bottom): (Color, Color)
        switch Self.cardLight {
        case .border: (top, bottom) = (base, base)
        case .panel:
            (top, bottom) = dark ? (base.mix(with: Palette.sky1Dark, by: 0.35), base.mix(with: Palette.back0Dark, by: 0.35))
                                 : (base.mix(with: Palette.sky1, by: 0.35), base.mix(with: Palette.back0, by: 0.3))
        }
        let previous = ctx.blendMode
        ctx.blendMode = .plusLighter
        defer { ctx.blendMode = previous }
        ctx.drawLayer { b in
            b.drawLayer { s in
                // At night a lit panel's spill, not a haze; by day wider, to read at all.
                s.addFilter(.blur(radius: dark ? 52 : 70))
                s.fill(card, with: .color(.white.opacity(dark ? 0.36 : 0.56)))
            }
            b.drawLayer { s in
                s.addFilter(.blur(radius: 28))
                s.stroke(card, with: .color(.white.opacity(dark ? 0.38 : 0.45)), lineWidth: 18)
            }
            // Colour the bloom (its alpha stays as drawn).
            b.blendMode = .sourceIn
            let span = box.insetBy(dx: -260, dy: -260)
            b.fill(Path(span), with: .linearGradient(Gradient(colors: [top, bottom]),
                                                     startPoint: CGPoint(x: 0, y: box.minY), endPoint: CGPoint(x: 0, y: box.maxY)))
        }
    }

    /// How brightly the white card lights a jaw's inner end, from its gap as a
    /// fraction of the gap at rest (so it reads the same in any window width):
    /// 0.07 at rest, rising on a smoothstep to 1 by a quarter of the rest gap
    /// and staying 1 through contact. Half at about 0.62 of the rest gap.
    static func rimLight(gap: CGFloat, restGap: CGFloat) -> CGFloat {
        let t = min(max((1 - gap / max(restGap, 1)) / 0.75, 0), 1)
        return 0.07 + 0.93 * t * t * (3 - 2 * t)
    }

    /// One fold's shading: a strip along the crease, mapped through the warp so
    /// it bends with the card, shaded dark on the jaw side and light on the
    /// other.
    private func drawFold(_ fold: Fold, in ctx: inout GraphicsContext, warp: Warp, fine: Bool) {
        let A = Self.A
        let half: CGFloat = fine ? 0.1 : 0.14   // strip half-width, in card widths
        let n = fine ? 12 : 4
        func edge(_ offset: CGFloat) -> [CGPoint] {
            (0...n).map { i in
                let v = -1.1 + 2.2 * CGFloat(i) / CGFloat(n)
                return CGPoint(x: (fold.u(at: v) + offset) * A, y: v * A)
            }
        }
        var strip = Path()
        strip.addLines((edge(-half) + edge(half).reversed()).map { warp($0.x, $0.y) })
        strip.closeSubpath()
        let mid = fold.u(at: 0)
        let a = warp((mid - half) * A, 0), b = warp((mid + half) * A, 0)
        let shadow = Palette.press.opacity((fine ? 0.26 : 0.34) * fold.a)
        let light = Color.white.opacity((fine ? 0.22 : 0.3) * fold.a)
        let (first, second) = mid < 0 ? (shadow, light) : (light, shadow)
        let clear = Color.white.opacity(0)
        ctx.fill(strip, with: .linearGradient(
            Gradient(stops: [.init(color: clear, location: 0), .init(color: first, location: 0.48),
                             .init(color: second, location: 0.52), .init(color: clear, location: 1)]),
            startPoint: a, endPoint: b))
    }

    /// Sky is the card's own fill; this adds the sun and the two hills.
    private func drawPicture(in ctx: inout GraphicsContext, warp: Warp, squash: CGFloat, crumple: CGFloat,
                             steps n: Int, dark: Bool, backlit: Bool = false) {
        let A = Self.A
        // The sun narrows to 0.62 of its width at the icon's pose, a little more as the card crumples.
        let sunWidth = 70 * max(0.45, lerp(1, 0.62, squash) - 0.1 * crumple)
        let sun = (0..<n).map { i -> CGPoint in
            let t = CGFloat(i) / CGFloat(n) * 2 * .pi
            return CGPoint(x: -120 + sunWidth * cos(t), y: -120 + 70 * sin(t))
        }
        if dark {
            // Night: a crescent where the sun is (the sun's ellipse minus one
            // offset up and right), narrowing with it, and sparse stars, all
            // through the same warp so they fold with the card. Stars are
            // skipped in the small tile.
            let inner = (0..<n).map { i -> CGPoint in
                let t = CGFloat(i) / CGFloat(n) * 2 * .pi
                return CGPoint(x: -120 + 0.56 * sunWidth + 0.86 * sunWidth * cos(t), y: -120 - 0.26 * 70 + 0.86 * 70 * sin(t))
            }
            var lights = warp.path(sun).subtracting(warp.path(inner))
            ctx.fill(lights, with: .color(Palette.moon))
            if n > 20 {
                for star in Self.stars {
                    let points = warp.path(Self.starPoints(x: star.u * A, y: star.v * A, r: star.r, sparkle: star.sparkle))
                    ctx.fill(points, with: .color(Palette.star))
                    lights.addPath(points)
                }
            }
            if backlit { bloom(lights, color: Palette.moon, in: &ctx) }
        } else {
            ctx.fill(warp.path(sun), with: .color(Palette.sun))
            if backlit { bloom(warp.path(sun), color: Palette.sun, in: &ctx) }
        }

        /// The backlit picture's highlights bloom slightly.
        func bloom(_ path: Path, color: Color, in ctx: inout GraphicsContext) {
            var g = ctx
            g.blendMode = .plusLighter
            g.addFilter(.blur(radius: 14))
            g.fill(path, with: .color(color.opacity(0.55)))
        }

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

    /// The night sky's stars, in photo space (u and v as fractions of the
    /// half-size, r in photo units): three four-point sparkles and five dots,
    /// as in the icon's dark appearance.
    private static let stars: [(u: CGFloat, v: CGFloat, r: CGFloat, sparkle: Bool)] = [
        (-0.74, -0.70, 20, true), (0.17, -0.60, 24, true), (0.70, -0.52, 18, true),
        (-0.04, -0.72, 7, false), (0.45, -0.72, 7, false), (0.07, -0.30, 6, false), (0.46, -0.38, 5, false),
        (-0.78, -0.28, 6, false),
    ]

    /// A four-point sparkle (concave sides: a superellipse with exponent 0.6)
    /// or a round dot.
    private static func starPoints(x: CGFloat, y: CGFloat, r: CGFloat, sparkle: Bool) -> [CGPoint] {
        let n = sparkle ? 48 : 16
        return (0..<n).map { i in
            let a = CGFloat(i) / CGFloat(n) * 2 * .pi
            let (c, s) = (cos(a), sin(a))
            let rad = sparkle ? r / pow(pow(abs(c), 0.6) + pow(abs(s), 0.6), 1 / 0.6) : r
            return CGPoint(x: x + rad * c, y: y + rad * s)
        }
    }

    /// One orange slab from `outer` (past the edge) to its pressing face at
    /// `face`, rounded on the face side. Lit along the top, shaded along the
    /// bottom, with a darker band on the pressing face that ends in a light
    /// edge. Light from the card falls on the rounded inner end, by `gap`.
    private func drawJaw(in ctx: inout GraphicsContext, from outer: CGFloat, to face: CGFloat, light rim: CGFloat,
                         cardHalfHeight: CGFloat, gap: CGFloat, fine: Bool, dark: Bool) {
        let left = outer < face
        let (top, bottom) = (Self.jawTop, Self.jawBottom)
        let rect = CGRect(x: min(outer, face), y: top, width: abs(face - outer), height: bottom - top)
        let f = min(Self.faceRadius, rect.width)
        let radii = left ? RectangleCornerRadii(topLeading: 0, bottomLeading: 0, bottomTrailing: f, topTrailing: f)
                         : RectangleCornerRadii(topLeading: f, bottomLeading: f, bottomTrailing: 0, topTrailing: 0)
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
            // Pressing face: a band that darkens toward the card and ends in a
            // light edge. In the small tile the edge only varies a little, so
            // the 46-point preview doesn't flicker as the dial moves.
            let band: CGFloat = 56
            let edgeAlpha = fine ? 0.2 + 0.4 * min(rim, 1) : 0.4 + 0.2 * min(rim, 1)
            let edge = Gradient(stops: [.init(color: Palette.burn.opacity(0), location: 0),
                                        .init(color: Palette.burn.opacity(0.26), location: 0.35),
                                        .init(color: Palette.burn.opacity(0.34), location: 0.8),
                                        .init(color: Palette.faceEdge.opacity(edgeAlpha), location: 1)])
            l.fill(Path(CGRect(x: left ? face - band : face, y: top, width: band, height: bottom - top)),
                   with: .linearGradient(edge, startPoint: CGPoint(x: left ? face - band : face + band, y: 0),
                                         endPoint: CGPoint(x: face, y: 0)))
            if fine {
                // Soft bevel: lit over the top 9 %, shaded over the bottom 14 %.
                l.fill(Path(rect), with: vertical([.init(color: .white.opacity(0.5), location: 0),
                                                    .init(color: .white.opacity(0), location: 0.09),
                                                    .init(color: Palette.burn.opacity(0), location: 0.86),
                                                    .init(color: Palette.burn.opacity(0.4), location: 1)], top, bottom))
            }
            drawBounce(in: &l, jaw: rect, face: face, left: left, radius: f,
                       color: dark ? Palette.moonlight : Palette.spill, rim: rim,
                       cardHalfHeight: cardHalfHeight, gap: gap, fine: fine)
        }
    }

    /// Light from the white card falling on the jaw's rounded inner end, as a
    /// Cycles render of the jaw beside a lit card shows it: a band on the bevel
    /// that hugs the face and its corner radii, brightest at the silhouette
    /// (where the surface turns to face the card) and falling off with the
    /// cosine across the bevel's width; only as tall as the card, with ends
    /// that soften as the gap grows. Added with plus-lighter in the card's
    /// warm white. (The render shows no separate specular streak, so none.)
    private func drawBounce(in ctx: inout GraphicsContext, jaw rect: CGRect, face: CGFloat, left: Bool, radius f: CGFloat,
                            color: Color,
                            rim: CGFloat, cardHalfHeight: CGFloat, gap: CGFloat, fine: Bool) {
        let strength = fine ? rim : 0.3 * min(rim, 1)
        guard strength > 0.005, f > 1 else { return }
        let bevel = min(56, f)   // the face band's width: the bevel rolling toward the card
        let (top, bottom) = (rect.minY, rect.maxY)
        let side: CGFloat = left ? 1 : -1                 // toward the card
        let cx = face - side * f                          // the corner arcs' centre line

        // Brightness across the bevel, from where it meets the flat front (0)
        // to the silhouette (1): the cosine of the normal against the card.
        let samples = 7
        func stops(from inner: CGFloat, to outer: CGFloat) -> [Gradient.Stop] {
            [.init(color: color.opacity(0), location: 0), .init(color: color.opacity(0), location: inner)] +
            (1...samples).map { i in
                let u = CGFloat(i) / CGFloat(samples)
                return .init(color: color.opacity(min(1, 0.95 * strength * pow(u, 1.3))), location: inner + (outer - inner) * u)
            }
        }

        // The layer is composited with the context's blend mode, so plus-lighter
        // goes on the context that receives it.
        let previous = ctx.blendMode
        ctx.blendMode = .plusLighter
        defer { ctx.blendMode = previous }
        ctx.drawLayer { band in
            // The straight run of the face: a horizontal gradient across the bevel.
            let run = CGRect(x: left ? face - bevel : face, y: top + f, width: bevel, height: bottom - top - 2 * f)
            band.fill(Path(run), with: .linearGradient(Gradient(stops: stops(from: 0, to: 1)),
                                                       startPoint: CGPoint(x: face - side * bevel, y: 0),
                                                       endPoint: CGPoint(x: face, y: 0)))
            // The corners: the same profile, radial about each arc's centre.
            for (cy, y0) in [(top + f, top), (bottom - f, bottom - f)] {
                let quadrant = CGRect(x: left ? cx : face, y: y0, width: f, height: f)
                band.drawLayer { q in
                    q.clip(to: Path(quadrant))
                    q.fill(Path(quadrant), with: .radialGradient(Gradient(stops: stops(from: (f - bevel) / f, to: 1)),
                                                                 center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: f))
                }
            }
            // Only as tall as the card; its ends soften as it backs away.
            band.blendMode = .destinationIn
            let soft = 24 + 0.6 * max(gap, 0)
            let (y0, y1) = (512 - cardHalfHeight, 512 + cardHalfHeight)
            let span = rect.insetBy(dx: -50, dy: -50)
            func at(_ y: CGFloat) -> CGFloat { min(max((y - span.minY) / span.height, 0), 1) }
            let mask = Gradient(stops: [.init(color: .white.opacity(0), location: at(y0 - soft)),
                                        .init(color: .white, location: at(y0 + soft * 0.4)),
                                        .init(color: .white, location: at(y1 - soft * 0.4)),
                                        .init(color: .white.opacity(0), location: at(y1 + soft))])
            band.fill(Path(span), with: .linearGradient(mask, startPoint: CGPoint(x: 0, y: span.minY),
                                                        endPoint: CGPoint(x: 0, y: span.maxY)))
        }
    }

    // MARK: - Shapes

    /// Points round a rounded rect centred on (0, 0) in photo space, with the
    /// straight runs sampled too so they bow and fold under the warp.
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

/// The icon's colors (Squish.icon), light and dark, with the jaws leaned toward coral.
enum Palette {
    static let tile0 = Color(hex: 0x2B4596), tile1 = Color(hex: 0x0E1A4A)
    static let tile0Dark = Color(hex: 0x16224E), tile1Dark = Color(hex: 0x04081C)
    /// How far the jaws lean from the icon's orange toward coral, the warm
    /// side of the app's accent (AccentColor: P3 0.82 0.29 0.10 light,
    /// 1.0 0.56 0.36 dark): 0 is the icon's orange, 1 is full coral.
    static let coral = 0.6
    private static let coral0 = Color(.displayP3, red: 1.0, green: 0.6, blue: 0.46)
    private static let coral1 = Color(.displayP3, red: 0.88, green: 0.34, blue: 0.24)
    private static let coral0Dark = Color(.displayP3, red: 0.98, green: 0.53, blue: 0.4)
    private static let coral1Dark = Color(.displayP3, red: 0.72, green: 0.24, blue: 0.15)
    static let jaw0 = Color(hex: 0xFFA44E).mix(with: coral0, by: coral)
    static let jaw1 = Color(hex: 0xE2501A).mix(with: coral1, by: coral)
    static let jaw0Dark = Color(hex: 0xF58A3A).mix(with: coral0Dark, by: coral)
    static let jaw1Dark = Color(hex: 0xB93E0C).mix(with: coral1Dark, by: coral)
    /// Shading on the jaws' bottom edge and pressing face, and the face's lit edge.
    static let burn = Color(hex: 0x5A1A00), faceEdge = Color(hex: 0xFFE2C4)
    /// Light from the card falling on the jaws' inner ends: warm by day, a
    /// cooler moonlit blue-white at night (same strength).
    static let spill = Color(hex: 0xFFE0B8), moonlight = Color(hex: 0xC4D8FF)
    static let matDark = Color(hex: 0xE9ECF4)
    /// The mat lit from within at night: a touch brighter and cooler than paper.
    static let emitDark = Color(hex: 0xF6F8FF)
    /// Pressure and fold shading on the picture, and pressure shading on the border.
    static let press = Color(hex: 0x0A1030), matShade = Color(hex: 0x1A2350)
    static let sky0 = Color(hex: 0x2F8BFF), sky1 = Color(hex: 0x9FD6FF)
    /// Dark appearance: the photo is a night scene, matching the icon's.
    static let sky0Dark = Color(hex: 0x13206A), sky1Dark = Color(hex: 0x3E3A9A)
    static let sun = Color(hex: 0xFFD84A), moon = Color(hex: 0xF6EDC4), star = Color(hex: 0xFFF4D6)
    static let back0 = Color(hex: 0x8EDB6A), back1 = Color(hex: 0x56B451)
    static let back0Dark = Color(hex: 0x2F7D6A), back1Dark = Color(hex: 0x1D5650)
    static let front0 = Color(hex: 0x4CC45C), front1 = Color(hex: 0x23863C)
    static let front0Dark = Color(hex: 0x1F6648), front1Dark = Color(hex: 0x0E3A2C)
}

private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

#Preview("Bleed") {
    VStack(spacing: 12) {
        ForEach([0, 0.06, PressView.contact, PressView.pose, 0.8, 1, 1.15], id: \.self) { s in
            PressView(squeeze: s, framing: .bleed).frame(width: 480, height: 220)
        }
    }
}

#Preview("Tile") {
    HStack(spacing: 12) {
        ForEach([0, PressView.pose, 1], id: \.self) { s in
            PressView(squeeze: s).frame(width: 46, height: 50)
            PressView(squeeze: s).frame(width: 80, height: 80)
        }
    }
    .padding()
}
