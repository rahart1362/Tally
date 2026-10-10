import AppIntents
import SwiftUI
import TallyDesignSystem

/// The "Due soon" row's trailing "Mark Done" button (M3-D2, m3d-report.md §6 option A): a plain
/// SF Symbol, `Button(intent:)` so the system performs `MarkDoneIntent` in the app's process
/// (never here). Carries only `itemID`, the glance's own opaque planner ID — never an assignment
/// name, a course or anything else that would need the app's key to read (encryption.md §3.3).
///
/// `accessibilityLabel` arrives already localized and already "Hide course names" aware
/// (`TallyGlance`'s `GlanceText.title`/`L10n.Widgets.markDoneButton`): this view takes no
/// `TallyStrings` dependency of its own, and so can never show a title the row itself is hiding.
struct MarkDoneButton: View {
    let itemID: String
    let accessibilityLabel: String

    var body: some View {
        Button(intent: MarkDoneIntent(itemID: itemID)) {
            Image(systemName: "checkmark.circle")
                .font(TallyTypography.cardTitle)
                // D06: with no foreground style, the glyph took `.plain`'s default
                // (`.primary`), which renders black in light mode — 1.21:1 on `bg.brand`'s navy,
                // the owner's "dark glyph on navy" lapse. `brandCream` is the fixed wordmark/mark
                // fill already used on this same brand surface (`TallyColor.swift`), so the glyph
                // reads the same regardless of the system's light/dark setting; `.widgetAccentable()`
                // keeps it visible when the system takes over in the accented and vibrant modes.
                .foregroundStyle(TallyColor.brandCream)
                .widgetAccentable()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: accessibilityLabel))
    }
}
