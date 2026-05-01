import SwiftUI

struct GlassButton: View {
    var systemName: String
    var accessibilityLabel: String
    var tint: Color? = nil
    var size: CGFloat = 46
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.38, weight: .semibold))
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint ?? .primary)
        .appGlass(tint: tint?.opacity(0.18), in: Circle(), interactive: true)
        .accessibilityLabel(accessibilityLabel)
    }
}

#Preview {
    GlassButton(systemName: "play.fill", accessibilityLabel: "Play") {}
        .padding()
}
