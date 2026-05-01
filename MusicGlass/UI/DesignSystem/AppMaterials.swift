import SwiftUI

struct GlassBackgroundModifier<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var tint: Color?
    var shape: S
    var interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.stroke(.primary.opacity(0.08), lineWidth: 1))
        } else if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.14), lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        }
    }
}

extension View {
    func appGlass<S: Shape>(
        tint: Color? = nil,
        in shape: S,
        interactive: Bool = false
    ) -> some View {
        modifier(GlassBackgroundModifier(tint: tint, shape: shape, interactive: interactive))
    }
}

struct GlassEffectStack<Content: View>: View {
    var spacing: CGFloat?
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}
