import SwiftUI
import TallyDesignSystem

/// UX2-10 (continuing UX1-19): iOS 26 draws both `confirmationDialog` and a toolbar `Menu` as an
/// anchored popover with a fixed width, which can cut a long choice's label (Course Options' "Tracked
/// in Canvas") or a menu's own single row (Calendar's "Subscribe to Canvas Calendar…") at the
/// accessibility sizes. At AX1 and up, a plain sheet replaces either presentation: the same title,
/// the same choices as full-width rows (each at least 44 pt, a checkmark on the current selection
/// where one applies), and Cancel, following D03's AX1+ pattern (`DestructiveConfirmation.swift`) --
/// content that cannot be squeezed into a fixed-width popover instead gets the whole sheet to lay out
/// in. Below AX1 both call sites keep their native `Menu`/`confirmationDialog` unchanged. One
/// component serves Course Options and Calendar's options menu, so both read and behave the same way
/// at these sizes.
struct TallyOptionsSheet: View {
    struct Option: Identifiable {
        let id: String
        let title: String
        var isSelected = false
        let accessibilityIdentifier: String?
        let action: () -> Void
    }

    let title: String
    let options: [Option]
    let cancelTitle: String
    /// A stable id for Cancel, independent of its (translated) title, matching every option's own
    /// `accessibilityIdentifier`.
    var cancelAccessibilityIdentifier: String? = nil
    let dismiss: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TallySpacing.md) {
                Text(title)
                    .font(TallyTypography.sectionHeader)
                    .foregroundStyle(TallyColor.textPrimary)
                VStack(spacing: TallySpacing.sm) {
                    ForEach(options) { option in
                        Button {
                            dismiss()
                            option.action()
                        } label: {
                            HStack {
                                Text(option.title)
                                    .font(TallyTypography.cardTitle.weight(.semibold))
                                Spacer(minLength: TallySpacing.sm)
                                if option.isSelected {
                                    Image(systemName: "checkmark")
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .padding(.horizontal, TallySpacing.md)
                        }
                        .buttonStyle(.bordered)
                        .tint(TallyColor.accent)
                        .accessibilityIdentifier(option.accessibilityIdentifier ?? "")
                    }
                    Button(cancelTitle, role: .cancel, action: dismiss)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .buttonStyle(.bordered)
                        .tint(TallyColor.textSecondary)
                        .accessibilityIdentifier(cancelAccessibilityIdentifier ?? "")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(TallySpacing.screenMargin)
        }
        .background(TallyColor.bgCanvas, ignoresSafeAreaEdges: .all)
    }
}
