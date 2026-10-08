import SwiftUI

/// ux-fp1 D01 (S1, systemic): on every scrolling screen, content scrolled past the top stayed
/// visible — blurred, not hidden — under the inline title, the toolbar buttons and the status bar,
/// even at rest. iOS 26's default scroll-edge effect (`.soft`) fades content under the bar instead
/// of hiding it; `.hard` was meant to fully occlude it, but round 1's Gate 2 review (D01 PARTIAL)
/// found large AX5 text still ghosting through at rest, and a navy hero scrolled under the bar
/// turning it into a grey-blue slab in light mode: `.hard` changes how much the scroll edge *fades*
/// content, but the bar's own Liquid Glass material still blends with whatever sits behind it. Round
/// 2 adds an explicit, opaque fill behind the bar (`toolbarBackground` + `toolbarBackgroundVisibility
/// (.visible, ...)`), so nothing can ever show through, on top of `.hard`'s edge behaviour.
///
/// Apply to the outermost scrollable content of every `List`/`ScrollView` screen that uses the Tally
/// canvas/card palette (`Home/HomeShellView.swift`'s five tabs, `CourseDetail/CourseDetailView.swift`,
/// `CourseDetail/WhatIfSheet.swift`, `Subscription/PaywallView.swift`, the AX5 student switcher
/// sheet). A `Form`-based grouped sheet (Settings, Subscription, Family) uses `tallyFormScreenChrome()`
/// instead, below, so its bar matches its own grouped background rather than Tally's navy canvas.
public struct TallyScreenChrome: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        content
            .scrollEdgeEffectStyle(.hard, for: .top)
            .toolbarBackground(TallyColor.bgCanvas, for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
    }
}

extension View {
    /// D01: hides content scrolled under the top bar/status bar instead of showing it through a
    /// blur, with an opaque Tally-canvas fill behind the bar so nothing can ghost through even at
    /// the largest text sizes. See `TallyScreenChrome`.
    public func tallyScreenChrome() -> some View {
        modifier(TallyScreenChrome())
    }
}

/// ux-fp1 D01 round 2: the `Form`-based grouped sheets (Settings, Subscription, Family, and their
/// pushed/sheeted screens) ghosted content under the bar exactly like the List/ScrollView screens,
/// but they keep the system's own grouped background (never Tally's `bgCanvas`: D31's apply-list
/// explicitly excludes them, so FP-4's own dark-mode tint fix for these screens, D30, is not
/// pre-empted here). So the bar needs to go opaque without being repainted a specific colour —
/// `toolbarBackgroundVisibility(.visible, ...)` alone does that, picking up whatever the Form's own
/// material already is instead of a hard-coded fill.
public struct TallyFormScreenChrome: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        content
            .scrollEdgeEffectStyle(.hard, for: .top)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
    }
}

extension View {
    /// D01 round 2: the grouped-`Form` sheets' own variant of `tallyScreenChrome()` — opaque, but
    /// in the Form's own background rather than Tally's navy canvas. See `TallyFormScreenChrome`.
    public func tallyFormScreenChrome() -> some View {
        modifier(TallyFormScreenChrome())
    }
}

/// ux-fp1 D27 (S3) + D31 (S2, dark): `List` screens (Courses, To-Do, Calendar, Course detail,
/// What-If) used the system's inset-grouped margin (20 pt) and the system's grouped colours, while
/// `ScrollView` screens (Dashboard, Insights, Paywall) used `TallySpacing.screenMargin` (16 pt) and
/// the Tally colour tokens — a 4 pt edge jump and, in dark, two different palettes on every tab
/// switch. One modifier unifies both: the Tally screen margin as the list's own content margin, and
/// the Tally canvas token behind the list.
///
/// Round 1 also set `.listRowBackground(TallyColor.bgCard)` here, on the `List` itself — Gate 2
/// (D31 PARTIAL) found the rows stayed the system's own grey (`#2C2C2E`): a list-row trait like
/// `.listRowBackground` only reaches a row when it's set on something that actually produces a row
/// (a `Section`, a `ForEach`, or a plain row view) — never on the `List` as a whole, which isn't
/// itself a row. `tallyRow()`, below, is the per-row form of the same token; every call site now
/// applies it directly to its rows/Sections instead.
public struct TallyListChrome: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        content
            .contentMargins(.horizontal, TallySpacing.screenMargin, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .background(TallyColor.bgCanvas)
    }
}

extension View {
    /// D27/D31: 16 pt content margins and the Tally canvas background on a `List`, in place of the
    /// system's 20 pt inset-grouped margin and grouped background. Pair with `tallyRow()` on every
    /// row/Section so the rows themselves pick up the Tally card colour too. See `TallyListChrome`.
    public func tallyList() -> some View {
        modifier(TallyListChrome())
    }
}

/// ux-fp1 D31 (S2, dark) round 2: the per-row half of `tallyList()`'s palette — `bg.card`, applied
/// directly to a row or to a `Section` (which reaches every row the Section contains), unlike
/// `.listRowBackground` set on the `List` itself, which reaches none of them. A row that draws its
/// own background (the Course Detail hero, `.listRowBackground(Color.clear)`) is left without this
/// modifier so its own colour keeps showing.
public struct TallyRow: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        content.listRowBackground(TallyColor.bgCard)
    }
}

extension View {
    /// D31: the Tally card colour on one row, or on every row a `Section`/`ForEach` contains. See
    /// `TallyRow`.
    public func tallyRow() -> some View {
        modifier(TallyRow())
    }
}
