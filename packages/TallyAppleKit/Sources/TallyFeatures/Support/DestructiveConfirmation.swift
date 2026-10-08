import SwiftUI
import TallyDesignSystem

/// ux-fp1 D03 (S1) round 2: Gate 2 found that at AX5, on the smallest iPhone, `.alert` still cut
/// the warning mid-sentence and pushed Cancel off-screen at rest (round 1's own regression test
/// only proved the alert's content was reachable *by scrolling*, never that the dialog itself was
/// visible without one — `.alert` sizes itself to a fixed fraction of the screen, not to its
/// content, so a long message at AX5 can still outgrow it). Below the accessibility sizes this
/// stays a plain `.alert` (unchanged, and still what every non-AX5 UI test expects). At AX1 and up,
/// the SAME title, message and button labels present instead as a full-screen confirmation sheet:
/// the buttons sit in a `safeAreaInset(edge: .bottom)` bar, so Cancel (always last) is pinned and
/// visible at rest on every device; only the title and message, above that bar, ever need a scroll,
/// and only on the smallest iPhone where the bar leaves the least room.
///
/// One component serves all three destructive confirmations this package touches (Sign Out &
/// Erase, Unlink, Remove), so all three read and behave the same way, as the fix list asks.
struct TallyConfirmationAction: Identifiable {
    enum Role {
        case destructive, cancel, normal
    }

    let id = UUID()
    let title: String
    let role: Role
    let action: () -> Void

    init(_ title: String, role: Role = .normal, action: @escaping () -> Void) {
        self.title = title
        self.role = role
        self.action = action
    }

    fileprivate var alertRole: ButtonRole? {
        switch role {
        case .destructive: .destructive
        case .cancel: .cancel
        case .normal: nil
        }
    }
}

extension View {
    /// D03 round 2: `.alert` below the accessibility sizes, a full-screen sheet built from the same
    /// title/message/actions at AX1 and up. See `TallyConfirmationAction`.
    func tallyDestructiveConfirmation(
        _ title: String, isPresented: Binding<Bool>, message: String, actions: [TallyConfirmationAction]
    ) -> some View {
        modifier(TallyDestructiveConfirmationModifier(title: title, isPresented: isPresented, message: message, actions: actions))
    }
}

private struct TallyDestructiveConfirmationModifier: ViewModifier {
    let title: String
    @Binding var isPresented: Bool
    let message: String
    let actions: [TallyConfirmationAction]
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        content
            .alert(title, isPresented: Binding(
                get: { isPresented && !typeSize.isAccessibilitySize },
                set: { shown in if !shown { isPresented = false } }
            )) {
                ForEach(actions) { action in
                    Button(action.title, role: action.alertRole, action: action.action)
                }
            } message: {
                Text(message)
            }
            .sheet(isPresented: Binding(
                get: { isPresented && typeSize.isAccessibilitySize },
                set: { shown in if !shown { isPresented = false } }
            )) {
                TallyConfirmationSheet(title: title, message: message, actions: actions, dismiss: { isPresented = false })
            }
    }
}

/// The AX1+ sheet itself: title and message in a `ScrollView` (so a very long message can scroll on
/// the smallest iPhone without pushing the buttons off screen), the buttons pinned in a bottom
/// safe-area inset so Cancel is reachable at rest on every device.
///
/// Round 3 (D03, Gate 2 round 2: the message was still cut at rest on every AX5 leg, the pinned bar
/// slicing a line through its glyphs with no cue that more followed). At AX5 Sign Out & Erase's
/// warning alone is taller than any iPhone's screen in `body` text, so it cannot all show at rest
/// without a copy change; it now ends cleanly instead. A fade the height of about one line
/// of the message's own text sits on top of the scroll content just above the bar, so the last
/// visible line dissolves into the canvas rather than being cut, and the scroll indicator flashes
/// on appear. The message gets the same height of bottom padding, so once scrolled to the end its
/// last line clears the fade. PAY-11's point stays clear at rest through the bar: Manage
/// Subscription is pinned there, never scrolled out of sight.
///
/// Considered and not used: `.safeAreaBar(edge: .bottom)` (iOS 26), which lets content scroll on
/// under the bar behind its soft scroll-edge effect; with an opaque bar that effect is hidden, and
/// without one the message would show (blurred) through the buttons' translucent tinted fills —
/// the content-under-chrome D01 removes elsewhere, and not checkable here without a device. And
/// `TallyTypography.body.weight(.semibold)` labels in place of `cardTitle`: `cardTitle` is
/// `.headline`, the same point size as `.body` at every Dynamic Type size and already semibold, so
/// the swap would not shorten the bar.
private struct TallyConfirmationSheet: View {
    let title: String
    let message: String
    let actions: [TallyConfirmationAction]
    let dismiss: () -> Void
    /// The fade's height, scaled with the message's own `body` text so it always covers about one
    /// line of it (24 pt at the default size; about 75 pt at AX5).
    @ScaledMetric(relativeTo: .body) private var fadeHeight: CGFloat = TallyConfirmationStyle.fadeHeight
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TallySpacing.md) {
                Text(title)
                    .font(TallyTypography.sectionHeader)
                    .foregroundStyle(TallyColor.textPrimary)
                Text(message)
                    .font(TallyTypography.body)
                    .foregroundStyle(TallyColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(TallySpacing.screenMargin)
            // Round 3: scrolled to the end, the message's last line sits above the fade, not in it.
            .padding(.bottom, fadeHeight)
        }
        // Round 3: a scroll cue on appear, alongside the fade.
        .scrollIndicatorsFlash(onAppear: true)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: TallySpacing.sm) {
                ForEach(actions) { action in
                    actionButton(action)
                }
            }
            .padding(TallySpacing.screenMargin)
            .background(TallyColor.bgCanvas)
            // Round 3: drawn above the bar's top edge, over the scrolling message, so the last
            // visible line fades out instead of being sliced by the bar. Decorative, and lets
            // touches through to the scroll view under it.
            .overlay(alignment: .top) {
                LinearGradient(colors: [TallyColor.bgCanvas.opacity(0), TallyColor.bgCanvas],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: fadeHeight)
                    .offset(y: -fadeHeight)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .background(TallyColor.bgCanvas, ignoresSafeAreaEdges: .all)
    }

    /// R5 (round 3): the destructive action is a filled button, white on `ScreenPalette.danger`'s
    /// light value (ux-ui.md §3.5), in light and dark alike — white on it is 5.7:1 (7.9:1 with
    /// Increase Contrast's value). Round 2's tinted `.bordered` style drew the red label on a pale
    /// pink fill of the same red: #FF383C on #F4D2D6, 2.56:1 in light. The other actions keep the
    /// tinted style (Manage Subscription 5.44:1, Cancel 5.32:1 in round 2's captures).
    @ViewBuilder
    private func actionButton(_ action: TallyConfirmationAction) -> some View {
        if action.role == .destructive {
            Button {
                dismiss()
                action.action()
            } label: {
                actionLabel(action.title)
                    .foregroundStyle(Color.white)
            }
            .buttonStyle(.borderedProminent)
            .tint(ScreenPalette.color(ScreenPalette.danger, scheme: .light, contrast: contrast))
        } else {
            Button {
                dismiss()
                action.action()
            } label: {
                actionLabel(action.title)
            }
            .buttonStyle(.bordered)
            .tint(action.role == .cancel ? TallyColor.textSecondary : TallyColor.accent)
        }
    }

    private func actionLabel(_ title: String) -> some View {
        Text(title)
            .font(TallyTypography.cardTitle.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
    }
}

/// D03/R5 round 3: the AX confirmation sheet's named values.
nonisolated enum TallyConfirmationStyle {
    /// The fade above the pinned button bar, in points at the default text size (scaled with
    /// `body` by `@ScaledMetric`).
    static let fadeHeight: CGFloat = 24
}
