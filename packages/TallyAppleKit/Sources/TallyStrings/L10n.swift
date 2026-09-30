import Foundation

/// Every user-facing string the app, the widget and the intents share (plan 08 §3.1, L10N-01).
///
/// Each entry is a `LocalizedStringResource` with a semantic key, the English text as its
/// `defaultValue`, a translator comment, and `bundle: #bundle`: this target's resource bundle,
/// which holds `Resources/Localizable.xcstrings`. The catalog is the source of truth for the text
/// (`scripts/ci/check_string_catalogs.py` checks that every key used here is in it, and that
/// every English value, translation and plural form has the same placeholders). The
/// `defaultValue` is only the fallback when a lookup finds nothing.
///
/// Why wrappers: Xcode 26 generates symbols for catalog keys, but they are internal to this
/// target, so the other targets reach the strings through these public functions.
///
/// How to add a string: add the key to the catalog (English value, comment, plural variants
/// where a count is involved), then a function here returning the resource. Views take it as
/// `Text(L10n.Area.name(...))`; code that needs a `String` (accessibility labels built from parts,
/// notification bodies, share text) uses `String(localized:)`. Canvas content (course names,
/// assignment titles, letter grades) is never localized: pass it with `Text(verbatim:)`.
///
/// Default isolation (nonisolated), deliberately: SwiftPM's generated resource accessor declares
/// a class, and under `.defaultIsolation(MainActor.self)` it gained an isolated deinit (plan 06 A2,
/// CI run 36390172728). The functions are pure, so main-actor and background callers alike use
/// them.
public enum L10n {
    /// The Dashboard (`TallyFeatures/Dashboard`).
    public enum Dashboard {
        /// The hero's caption: "Average of 1 course", "Average of 5 courses". A plural key: the
        /// catalog holds one form per plural category of each language.
        public static func averageOfCourses(_ count: Int) -> LocalizedStringResource {
            LocalizedStringResource(
                "dashboard.hero.averageOfCourses",
                defaultValue: "Average of \(count) courses",
                bundle: Bundle.main,
                comment: "Dashboard hero caption above the average percentage. The number is how many courses are in the average."
            )
        }
    }
}
