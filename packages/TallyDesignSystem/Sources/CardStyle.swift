import SwiftUI

public struct TallyCardStyle: ViewModifier {
    public init() {}
    public func body(content: Content) -> some View {
        content
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.Tally.cardBackground.opacity(0.85))
                    .background(
                        VisualEffectBlur(blurStyle: .systemUltraThinMaterial)
                            .cornerRadius(16)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.Tally.divider.opacity(0.5), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
}

public struct VisualEffectBlur: UIViewRepresentable {
    var blurStyle: UIBlurEffect.Style
    public init(blurStyle: UIBlurEffect.Style) {
        self.blurStyle = blurStyle
    }
    public func makeUIView(context: Context) -> UIVisualEffectView {
        return UIVisualEffectView(effect: UIBlurEffect(style: blurStyle))
    }
    public func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: blurStyle)
    }
}

public extension View {
    func tallyCardStyle() -> some View {
        self.modifier(TallyCardStyle())
    }
}
