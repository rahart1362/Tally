import SwiftUI
import TallyStrings

/// L10N-04 round 2 (gate-2 verdict item "Spanish widget renders"): every `GlanceText.*` call in
/// the widget views resolves through `TallyLocale.effective` (`Bundle.main.preferredLocalizations`
/// + `Locale.current`), a plain `String`, never SwiftUI's `\.locale` environment — so
/// `.environment(\.locale, …)` on a hosted render test had no effect, and every Spanish widget
/// render came back byte-identical to English (the gate-2 verdict's finding).
///
/// `TallyLocale.effective` cannot simply be swapped for `\.locale`: the two are deliberately
/// different values (`TallyLocale.swift`'s own doc comment) — `\.locale`'s default tracks the
/// iPhone's system locale, while `TallyLocale.effective` tracks the language Tally's UI is
/// *actually shown in*, which can differ (an iPhone set to a language Tally does not ship).
/// Reading `\.locale` as a blind replacement would reintroduce exactly the bug `TallyLocale` exists
/// to prevent.
///
/// This is the narrow seam instead: an environment override that every production code path leaves
/// `nil`, so `TallyLocale.effective` keeps resolving exactly as before (verified by
/// `WidgetFamilyRenderTests`'s English-unchanged test) — and that a hosted render test can set, to
/// get a specific locale's text without touching what ships. Every widget view that calls
/// `GlanceText.*` reads this through `effectiveGlanceLocale` and passes it explicitly, in place of
/// relying on `GlanceText`'s own `TallyLocale.effective` default.
private struct GlanceLocaleOverrideKey: EnvironmentKey {
    static let defaultValue: Locale? = nil
}

extension EnvironmentValues {
    /// `nil` in every shipping code path. See `GlanceLocaleOverrideKey`.
    public var glanceLocaleOverride: Locale? {
        get { self[GlanceLocaleOverrideKey.self] }
        set { self[GlanceLocaleOverrideKey.self] = newValue }
    }
}

extension EnvironmentValues {
    /// `glanceLocaleOverride ?? TallyLocale.effective`: what a widget view should resolve
    /// `GlanceText.*` with. Unchanged from today's behavior unless a test sets the override.
    public var effectiveGlanceLocale: Locale {
        glanceLocaleOverride ?? TallyLocale.effective
    }
}
