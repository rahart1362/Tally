import SwiftUI
import TallyDesignSystem
import TallyStrings

/// The persistent "SAMPLE DATA" banner (ASC-14). Shown above the tab bar on every screen while
/// exploring sample data, with the one way out: "Exit" back to Welcome.
struct SampleDataBanner: View {
    let onExit: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "sparkles")
                .accessibilityHidden(true)
            Text(L10n.SampleData.bannerLabel())
                .font(TallyTypography.caption.weight(.semibold))
            Spacer()
            // A 44 × 44 pt target (HIG minimum). The text alone measured 22 × 14 pt in CI's
            // accessibility hierarchy (run 36363360710), too small to tap reliably.
            Button(action: onExit) {
                Text(L10n.SampleData.bannerExit())
                    .font(TallyTypography.caption.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
        }
        .foregroundStyle(TallyColor.accentOnFill)
        .padding(.horizontal, TallySpacing.screenMargin)
        .frame(maxWidth: .infinity)
        .background(TallyColor.accent)
        // Deliberately NOT `.accessibilityElement(children: .combine)`: that would fold the
        // "Exit" button into one non-interactive combined element, making it untappable for
        // VoiceOver (and unfindable by UI tests) — an interactive control must stay its own
        // element (HIG: never combine children that include a control).
    }
}
