import SwiftUI

extension View {
    /// Full tile treatment: Liquid Glass fill (macOS 26+) with a glossy edge,
    /// optional accent tint when active, and a soft drop shadow.
    func glassCard(cornerRadius: CGFloat = 18, isOn: Bool = false) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius, isOn: isOn))
    }

    /// Just the glass fill (no stroke/shadow), for larger surfaces.
    func glassFill(cornerRadius: CGFloat = 18, tinted: Bool = false) -> some View {
        modifier(GlassFill(cornerRadius: cornerRadius, tinted: tinted))
    }
}

private struct GlassCard: ViewModifier {
    let cornerRadius: CGFloat
    let isOn: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .modifier(GlassFill(cornerRadius: cornerRadius, tinted: isOn))
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.40), .white.opacity(0.06)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
            )
            .overlay(
                shape.strokeBorder(isOn ? Color.accentColor.opacity(0.55) : .clear, lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(0.28), radius: 12, y: 6)
    }
}

private struct GlassFill: ViewModifier {
    let cornerRadius: CGFloat
    let tinted: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            content.glassEffect(
                tinted ? .regular.tint(Color.accentColor.opacity(0.55)).interactive()
                       : .regular.interactive(),
                in: shape)
        } else {
            content.background(
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(tinted ? Color.accentColor.opacity(0.16) : Color.clear)
                }
            )
        }
    }
}
