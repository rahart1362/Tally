import SwiftUI

/// UX2-09: one shared layout for a full-screen notice (`AgeRestrictedView`,
/// `SchoolRevokedNoticeView`, `PurchaseConfirmationView`): an icon at `stateSymbol`, a title at
/// `stateTitle` -- the same scale `TallyUnavailableView` already uses for an empty/error state at
/// the accessibility sizes, in place of each screen's own ad-hoc `sectionHeader` (20 pt semibold) --
/// then free-form body content and actions. Before this, each of the three screens was its own
/// top-anchored `VStack` in a bare `ScrollView`, leaving 55-75% of the screen empty at std, with
/// `TallySpacing.xl` (20 pt) side padding instead of the 16 pt `screenMargin` every other screen
/// uses (on the smallest iPhone at AX5 that 4 pt difference was enough to hyphenate the primary
/// pill: "Manage Subscrip- / tion").
///
/// Centred in the available height when it fits (`tallyCenteredScrolling()`), scrolling when it
/// does not (so a long notice on the smallest iPhone at AX5 never overflows top and bottom at
/// once), inside `screenMargin` sides, with UX2-04's opaque status-bar band
/// (`tallyStatusBarBand()`) for whichever of the three has no toolbar of its own to carry D01's fix.
public struct TallyNoticeLayout<Content: View, Actions: View>: View {
    private let systemImage: String
    private let title: Text
    private let titleIdentifier: String
    private let content: Content
    private let actions: Actions

    public init(systemImage: String, title: Text, titleIdentifier: String,
                @ViewBuilder content: () -> Content, @ViewBuilder actions: () -> Actions) {
        self.systemImage = systemImage
        self.title = title
        self.titleIdentifier = titleIdentifier
        self.content = content()
        self.actions = actions()
    }

    public var body: some View {
        VStack(spacing: TallySpacing.xl) {
            Image(systemName: systemImage)
                .font(TallyTypography.stateSymbol)
                .foregroundStyle(TallyColor.accent)
                .accessibilityHidden(true)
            title
                .font(TallyTypography.stateTitle)
                .foregroundStyle(TallyColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(titleIdentifier)
            content
            actions
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, TallySpacing.screenMargin)
        .padding(.vertical, TallySpacing.xl)
        .frame(maxWidth: .infinity)
        .tallyCenteredScrolling()
        .background(TallyColor.bgCanvas)
        .tallyStatusBarBand()
    }
}

extension TallyNoticeLayout where Actions == EmptyView {
    /// A notice with no actions of its own (`PurchaseConfirmationView`'s content: its one action,
    /// Done, lives in the toolbar, not here).
    public init(systemImage: String, title: Text, titleIdentifier: String, @ViewBuilder content: () -> Content) {
        self.init(systemImage: systemImage, title: title, titleIdentifier: titleIdentifier, content: content) {
            EmptyView()
        }
    }
}
