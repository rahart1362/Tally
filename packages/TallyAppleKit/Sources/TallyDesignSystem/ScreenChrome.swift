import SwiftUI

/// ux-fp1 D01 (S1, systemic): on every scrolling screen, content scrolled past the top stayed
/// visible — blurred, not hidden — under the inline title, the toolbar buttons and the status bar,
/// even at rest. iOS 26's default scroll-edge effect (`.soft`) fades content under the bar instead
/// of hiding it; `.hard` fully occludes it while the bar itself still renders as native iOS 26
/// (Liquid Glass), so this is a one-line fix with no custom bar background to keep in sync with the
/// system's own materials across light, dark and every Dynamic Type size.
///
/// Apply to the outermost scrollable content of every `NavigationStack` root, pushed screen and
/// sheet (`Home/HomeShellView.swift`'s five tabs, `CourseDetail/CourseDetailView.swift`,
/// `Settings/SettingsView.swift` and its pushed/sheeted screens, `Subscription/PaywallView.swift`
/// and `CourseDetail/WhatIfSheet.swift`).
public struct TallyScreenChrome: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        content
            .scrollEdgeEffectStyle(.hard, for: .top)
    }
}

extension View {
    /// D01: hides content scrolled under the top bar/status bar instead of showing it through a
    /// blur. See `TallyScreenChrome`.
    public func tallyScreenChrome() -> some View {
        modifier(TallyScreenChrome())
    }
}

/// ux-fp1 D27 (S3) + D31 (S2, dark): `List` screens (Courses, To-Do, Calendar, Course detail,
/// What-If) used the system's inset-grouped margin (20 pt) and the system's grouped colours, while
/// `ScrollView` screens (Dashboard, Insights, Paywall) used `TallySpacing.screenMargin` (16 pt) and
/// the Tally colour tokens — a 4 pt edge jump and, in dark, two different palettes on every tab
/// switch. One modifier unifies both: the Tally screen margin as the list's own content margin, and
/// the Tally canvas/card tokens in place of the system's grouped backgrounds.
public struct TallyListChrome: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        content
            .contentMargins(.horizontal, TallySpacing.screenMargin, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .background(TallyColor.bgCanvas)
            .listRowBackground(TallyColor.bgCard)
    }
}

extension View {
    /// D27/D31: 16 pt content margins and the Tally canvas/card palette on a `List`, in place of
    /// the system's 20 pt inset-grouped margin and grouped colours. A row that draws its own
    /// background (the Course Detail hero, `.listRowBackground(Color.clear)`) still overrides this
    /// default. See `TallyListChrome`.
    public func tallyList() -> some View {
        modifier(TallyListChrome())
    }
}
