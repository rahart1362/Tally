import SwiftUI

public struct TallyCardStyle: ViewModifier {
    public init() {}
    public func body(content: Content) -> some View {
        content
            .padding(Spacing.md)
            .background(Color.Tally.surface)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
}

public extension View {
    func tallyCardStyle() -> some View {
        self.modifier(TallyCardStyle())
    }
}
