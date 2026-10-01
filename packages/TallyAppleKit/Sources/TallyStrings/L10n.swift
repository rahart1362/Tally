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
                bundle: #bundle,
                comment: "Dashboard hero caption above the average percentage. The number is how many courses are in the average."
            )
        }
    }

    /// The widgets (`TallyGlance`).
    public enum Glance {
        /// The Standing widget when the student has not chosen to show grades in widgets (PMO R10).
        public static func standingHiddenTitle() -> LocalizedStringResource {
            LocalizedStringResource("glance.standing.hidden.title", defaultValue: "Grades are hidden", bundle: #bundle,
                                    comment: "Standing widget title when the student has not chosen to show grades in widgets.")
        }

        public static func standingHiddenDetail() -> LocalizedStringResource {
            LocalizedStringResource(
                "glance.standing.hidden.detail", defaultValue: "They appear here only if you choose to show grades in widgets.",
                bundle: #bundle, comment: "Standing widget, under 'Grades are hidden': how to show grades in the widget.")
        }

        /// Plan 08 §4.4 row 14: opted in, but no course has a grade to average yet.
        public static func standingNoneYetTitle() -> LocalizedStringResource {
            LocalizedStringResource(
                "glance.standing.noneYet.title", defaultValue: "No grades yet", bundle: #bundle,
                comment: "Standing widget title when the student chose to show grades in widgets, but no course has a grade to average yet.")
        }

        public static func standingNoneYetDetail() -> LocalizedStringResource {
            LocalizedStringResource("glance.standing.noneYet.detail",
                                    defaultValue: "Your average appears here once grades are posted in Canvas.",
                                    bundle: #bundle, comment: "Standing widget, under 'No grades yet'.")
        }

        /// Plan 08 §4.4 row 14 and §4.5: opted in, and the school does not appear to keep grades in Canvas.
        public static func standingNotInCanvasTitle() -> LocalizedStringResource {
            LocalizedStringResource(
                "glance.standing.notInCanvas.title", defaultValue: "Grades aren't in Canvas", bundle: #bundle,
                comment: "Standing widget title when the student's school does not appear to keep grades in Canvas (it uses another grading system).")
        }

        public static func standingNotInCanvasDetail() -> LocalizedStringResource {
            LocalizedStringResource("glance.standing.notInCanvas.detail",
                                    defaultValue: "Your school doesn't appear to post grades there.", bundle: #bundle,
                                    comment: "Standing widget, under 'Grades aren't in Canvas'. 'There' is Canvas.")
        }
    }
}
