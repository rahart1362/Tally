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

    /// The Week-ahead strip's `ShareLink` (Idea 11): shares the plain-text weekly summary
    /// `WeekShareText` builds.
    public static func shareWeekButton() -> LocalizedStringResource {
        LocalizedStringResource("dashboard.weekAhead.shareButton", defaultValue: "Send My Week", bundle: #bundle,
                                comment: "Dashboard, Week-ahead strip: ShareLink label that shares the student's own plain-text weekly summary.")
    }

    /// `WeekShareText`'s first line: the week's total due count. The placeholder is that count.
    public static func shareWeekHeader(_ dueCount: Int) -> LocalizedStringResource {
        LocalizedStringResource("dashboard.weekAhead.shareHeader", defaultValue: "This week: \(dueCount) due", bundle: #bundle,
                                comment: "Shared weekly summary text, first line: how many items are due this week. The placeholder is the count.")
    }

    /// `WeekShareText`'s per-day line with \"Hide Course Names\" on (R10): a weekday and a count,
    /// never a title or a course code.
    public static func shareWeekDayCountOnly(_ weekday: String, _ dueCount: Int) -> LocalizedStringResource {
        LocalizedStringResource("dashboard.weekAhead.shareDayCountOnly", defaultValue: "\(weekday): \(dueCount) due", bundle: #bundle,
                                comment: "Shared weekly summary text, one day's line with \"Hide Course Names\" on: the weekday abbreviation and how many items are due that day, never a title or course code. Placeholders: the weekday, the count.")
    }

    /// `WeekShareText`'s per-day line with \"Hide Course Names\" off: a weekday and the day's
    /// items, titles joined by commas (course code first, like the Calendar tab's own drafts).
    public static func shareWeekDayTitles(_ weekday: String, _ titles: String) -> LocalizedStringResource {
        LocalizedStringResource("dashboard.weekAhead.shareDayTitles", defaultValue: "\(weekday): \(titles)", bundle: #bundle,
                                comment: "Shared weekly summary text, one day's line with \"Hide Course Names\" off: the weekday abbreviation and that day's item titles, comma-joined. Placeholders: the weekday, the already-joined titles.")
    }
}

extension L10n.Settings {
    /// Idea 7's picker row and section header (the same string serves both, so one key covers
    /// both places it reads).
    public static func canvasLinksLabel() -> LocalizedStringResource {
        LocalizedStringResource("settings.canvasLinks.label", defaultValue: "Open Canvas Links In", bundle: #bundle,
                                comment: "Settings: section header and picker label for the \"App\"/\"Browser\" choice that feeds CanvasLinkOpener.")
    }

    /// The Canvas Student app option (today's default).
    public static func canvasLinksOptionApp() -> LocalizedStringResource {
        LocalizedStringResource("settings.canvasLinks.optionApp", defaultValue: "App", bundle: #bundle,
                                comment: "Settings, \"Open Canvas Links In\" picker option: the Canvas Student app (falling back to the browser if it isn't installed) -- today's default.")
    }

    /// The device's default web browser option.
    public static func canvasLinksOptionBrowser() -> LocalizedStringResource {
        LocalizedStringResource("settings.canvasLinks.optionBrowser", defaultValue: "Browser", bundle: #bundle,
                                comment: "Settings, \"Open Canvas Links In\" picker option: always the device's browser, never the Canvas Student app.")
    }
}
