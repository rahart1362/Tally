import Foundation

/// New strings for work package UX-FIX-2 (the 23 S3 items from the UX-1 review, ranks 17-39).
/// Kept in its own file, beside `L10n.swift` and `L10n+GradeControls.swift`, so these additions
/// never touch another stream's lines in those files (pmo-common-rules-v2.md rule 9). Every key
/// here is NEW -- never an edit to an existing English value -- and its wording was approved
/// 2026-10-23 (see the work package report's "Copy for owner approval").
extension L10n.Welcome {
    /// UX1-02 (option B): the same sentence as `tagline()`, with non-breaking spaces inside "at a
    /// glance" so that phrase never splits across two lines (Pro Max broke it as "...Canvas — at /
    /// a glance"; the smallest iPhone started its second line with the bare em dash, "— at a
    /// glance"). `tagline()` itself is unchanged and stays in use by nothing else.
    ///
    /// UX2-20 (owner-approved 2026-10-24, amends this still-pending key): on the smallest iPhone at
    /// std the second line still started with the bare em dash ("— at a glance") -- this fixed the
    /// phrase after the dash but left an ordinary space before it. A non-breaking space there too
    /// keeps "Canvas —" on the first line instead of leaving the dash to start the next one. The
    /// visible words are unchanged, in en and es alike.
    public static func taglineNoBreak() -> LocalizedStringResource {
        LocalizedStringResource(
            "welcome.tagline.noBreak",
            defaultValue: "Every class, grade and deadline from Canvas\u{00A0}— at\u{00A0}a\u{00A0}glance",
            bundle: #bundle,
            comment: "Welcome screen tagline, under the Tally wordmark. Same sentence as welcome.tagline; the non-breaking spaces around \"— at a glance\" keep that phrase (and the dash before it) from splitting across two lines.")
    }
}

extension L10n.CourseDetail {
    /// UX1-21: the same text as `whatIfButton()`, with a non-breaking hyphen (U+2011) in
    /// "What-If" so it never breaks as "Try What- / If Scores" at AX5, on either phone.
    public static func whatIfButtonNoBreak() -> LocalizedStringResource {
        LocalizedStringResource(
            "courseDetail.whatIf.button.noBreak", defaultValue: "Try What\u{2011}If Scores", bundle: #bundle,
            comment: "Button that opens the what-if calculator, where the student tries scores on work that isn't graded yet. Same text as courseDetail.whatIf.button; the non-breaking hyphen keeps \"What-If\" from splitting across two lines at large text sizes.")
    }
}

extension L10n.GradeOverride {
    /// UX1-22: `yes()`'s answer reworded as a statement ("the grades ARE kept outside Canvas")
    /// rather than a bare "Yes" to a question the flattened Course Options menu no longer asks
    /// aloud (the question itself, `menuRowTitle()`, is the menu's own section title right above
    /// these two choices). `yes()` is unchanged and stays in use by nothing else.
    public static func keptOutsideCanvas() -> LocalizedStringResource {
        LocalizedStringResource(
            "courseDetail.override.keptOutsideCanvas", defaultValue: "Kept outside Canvas", bundle: #bundle,
            comment: "Answer to 'This course's grades are kept outside Canvas', reworded from the frozen courseDetail.override.yes (\"Yes\") as a statement rather than a yes/no word.")
    }

    /// UX1-22: `no()`'s answer, reworded the same way.
    public static func trackedInCanvas() -> LocalizedStringResource {
        LocalizedStringResource(
            "courseDetail.override.trackedInCanvas", defaultValue: "Tracked in Canvas", bundle: #bundle,
            comment: "Answer to 'This course's grades are kept outside Canvas', reworded from the frozen courseDetail.override.no (\"No\") as a statement rather than a yes/no word.")
    }
}
