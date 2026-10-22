import Foundation

/// FEAT-B (`pmo-featb-prompt.md`): the bundle -- Idea 10 ("Add this week to Calendar"), Idea 11
/// ("Send my week") and Idea 7 ("Open Canvas links in: App / Browser"),
/// `pmo-audit/.build-audit/ideas1/report.md`. Kept in its own file, beside `L10n.swift`, for the
/// same reason `L10n+GradeScreensSweep.swift` is: this stream's additions never touch the lines
/// another stream adds there, and every key is in the same catalog.
extension L10n.Dashboard {
    /// The Week-ahead strip's bulk action (Idea 10): walks the week's due items through the
    /// existing per-item calendar sheet, one at a time (zero permission, PMO R6).
    public static func addWeekButton() -> LocalizedStringResource {
        LocalizedStringResource("dashboard.weekAhead.addButton", defaultValue: "Add This Week to Calendar", bundle: #bundle,
                                comment: "Dashboard, Week-ahead strip: button that walks the week's due items through the existing per-item \"Add to Calendar\" sheet, one at a time.")
    }
}
