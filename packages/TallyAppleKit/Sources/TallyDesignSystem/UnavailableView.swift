import SwiftUI

/// ux-fp2 D20 (S2): an empty or error state (a symbol, a title, a description, its actions) that
/// can scroll when it is taller than the screen.
///
/// The system `ContentUnavailableView` sizes itself to the space it is offered and centres its
/// content there; content taller than that space overflows both edges. Inside a `ScrollView` it
/// still reported the visible height, so the page never scrolled: Audit tour run 37827539573's
/// first-sync failure at AX5 on the smallest iPhone kept its icon and title above the top edge and
/// "Choose a Different School" below the bottom one, as before the wrapper.
///
/// Below the accessibility sizes this IS that system view (ux-ui.md §3.2.3: "Build these with
/// `ContentUnavailableView`"), unchanged. From AX1 up it lays the same parts out in a plain `VStack`
/// as tall as its content, so `tallyCenteredScrolling()` centres it when it fits and scrolls it when
/// it does not.
public struct TallyUnavailableView<Actions: View>: View {
    private let title: Text
    private let systemImage: String
    private let description: Text?
    private let actions: Actions
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(_ title: Text, systemImage: String, description: Text? = nil, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
        self.actions = actions()
    }

    public var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: TallySpacing.lg) {
                Image(systemName: systemImage)
                    .font(TallyTypography.stateSymbol)
                    .foregroundStyle(TallyColor.textSecondary)
                    .accessibilityHidden(true)
                title
                    .font(TallyTypography.stateTitle)
                    .foregroundStyle(TallyColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let description {
                    description
                        .font(TallyTypography.body)
                        .foregroundStyle(TallyColor.textSecondary)
                }
                VStack(spacing: TallySpacing.md) {
                    actions
                }
                .padding(.top, TallySpacing.sm)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, TallySpacing.screenMargin)
            .padding(.vertical, TallySpacing.xxl)
            .frame(maxWidth: .infinity)
        } else {
            // Onboarding tint (ux-fp5): the onboarding stack's `.tint(TallyColor.accent)`
            // (`WelcomeFlowView`) colours School search's "Retry" (measured 7.24:1 light, 9.64:1
            // dark in Audit tour 38023201467, gate 2). The call sites that pass a `.tallyPrimary`/
            // `.tallySecondary` button paint their own colour; `SchoolSearchView`'s plain "Retry"
            // also sets `.foregroundStyle(TallyColor.accent)` so it never depends on an ancestor.
            ContentUnavailableView {
                Label {
                    title
                } icon: {
                    Image(systemName: systemImage)
                }
            } description: {
                if let description {
                    description
                }
            } actions: {
                actions
            }
        }
    }
}

extension TallyUnavailableView where Actions == EmptyView {
    /// A state with no action.
    public init(_ title: Text, systemImage: String, description: Text? = nil) {
        self.init(title, systemImage: systemImage, description: description) { EmptyView() }
    }
}
