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
private struct TallyConfirmationSheet: View {
    let title: String
    let message: String
    let actions: [TallyConfirmationAction]
    let dismiss: () -> Void

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
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: TallySpacing.sm) {
                ForEach(actions) { action in
                    Button {
                        dismiss()
                        action.action()
                    } label: {
                        Text(action.title)
                            .font(TallyTypography.cardTitle.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(action.role == .destructive ? .red : (action.role == .cancel ? TallyColor.textSecondary : TallyColor.accent))
                }
            }
            .padding(TallySpacing.screenMargin)
            .background(TallyColor.bgCanvas)
        }
        .background(TallyColor.bgCanvas, ignoresSafeAreaEdges: .all)
    }
}
