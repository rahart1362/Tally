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
        // D29 (safe-area part): plain `.background(Color)` ignores safe area edges by default, so
        // the banner's fill painted under the status bar — with dark glyphs/text there failing
        // contrast. An empty edge set keeps the fill to the banner's own frame, so the status bar
        // sits on the canvas behind it.
        // D29 (colour part, ux-fp6): `accent` flips to a light blue (#8DB4FF) in dark, which made
        // this the brightest block on screen. `accentFill` is the same deep blue in both
        // appearances, and `accentOnFill` (white in both) keeps the band's own text/icon ≥ 4.5:1.
        .background(TallyColor.accentFill, ignoresSafeAreaEdges: [])
        // Deliberately NOT `.accessibilityElement(children: .combine)`: that would fold the
        // "Exit" button into one non-interactive combined element, making it untappable for
        // VoiceOver (and unfindable by UI tests) — an interactive control must stay its own
        // element (HIG: never combine children that include a control).
    }
}
