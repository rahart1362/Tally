import Foundation
import TallyDomain

/// Phrases the Dashboard's structured rows (plan 08 §3.2, L10N-02): the "Next up" reason, the
/// "Needs attention" rows and the change chip. `DashboardBuilder` (TallyCore, Linux) returns
/// values; this is where they become words in the student's language, with times and dates in the
/// student's locale. Canvas titles and course codes are passed through untouched.
///
/// English is byte-identical to what the app showed before L10N-02: `DashboardBuilder`'s text,
/// with the time and date that `HomeProjector` re-rendered in the user's locale. Against
/// TallyCore's own former text these are the two named fixes: a localized time instead of a fixed
/// 24-hour `HH:mm`, and a localized date instead of an ISO `yyyy-MM-dd` (`RendererGoldenTests`).
public enum DashboardText {
    /// "Due in 6h · near a grade boundary · ~11% of BIO 101": each factor phrased
    /// (`PriorityScore.reasonPart` does the rounding), in order, joined by the catalog's separator
    /// (" · " in English) rather than a list format, which would change the English.
    public static func reason(
        _ factors: [PriorityScore.Factor], courseCode: String, locale: Locale = TallyLocale.effective
    ) -> String {
        let parts = factors.map { phrase(PriorityScore.reasonPart($0), courseCode: courseCode, locale: locale) }
        guard var joined = parts.first else { return "" }
        for part in parts.dropFirst() {
            joined = resolve(Key.reasonJoin(joined, part), locale)
        }
        return joined
    }

    /// A "Needs attention" row's title: "Lab Report 4 is missing", "BIO 101: missing work is
    /// closed", "Lab Report 4 due 2:30 PM", "Busy stretch starting Oct 2, 2026", or the title alone.
    /// Times and dates are in `calendar`'s time zone.
    public static func attentionTitle(
        _ content: DashboardProjection.AttentionItem.Content, calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = TallyLocale.effective
    ) -> String {
        switch content {
        case .missingOpen(let title, _):
            resolve(Key.missingOpenTitle(title), locale)
        case .missingClosed(let courseCode):
            resolve(Key.missingClosedTitle(courseCode), locale)
        case .dueSoon(let title, let dueAt, _):
            resolve(Key.dueSoonTitle(title, TallyFormat.time(dueAt, calendar: calendar, locale: locale)), locale)
        case .overload(let start):
            resolve(Key.overloadTitle(date(start, calendar: calendar, locale: locale)), locale)
        case .other(let title, _):
            title
        }
    }

    /// A "Needs attention" row's second line: "BIO 101 · still accepted", "Talk to your
    /// instructor", "Several items are due close together", or the course code alone.
    public static func attentionSubtitle(
        _ content: DashboardProjection.AttentionItem.Content, locale: Locale = TallyLocale.effective
    ) -> String {
        switch content {
        case .missingOpen(_, let courseCode): resolve(Key.missingOpenSubtitle(courseCode), locale)
        case .missingClosed: resolve(Key.missingClosedSubtitle(), locale)
        case .dueSoon(_, _, let courseCode): courseCode
        case .overload: resolve(Key.overloadSubtitle(), locale)
        case .other(_, let courseCode): courseCode
        }
    }

    /// "1 change since 2:13 PM", "6 changes since 2:13 PM": the count (a plural key) and the time
    /// of the refresh, in `calendar`'s time zone.
    public static func changeSummary(
        _ summary: DashboardProjection.ChangeSummary, calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = TallyLocale.effective
    ) -> String {
        let count = resolve(Key.changeCount(summary.count), locale)
        return resolve(Key.changesSince(count, TallyFormat.time(summary.asOf, calendar: calendar, locale: locale)), locale)
    }

    private static func phrase(_ part: PriorityScore.ReasonPart, courseCode: String, locale: Locale) -> String {
        switch part {
        case .dueInMinutes(let minutes): resolve(Key.dueInMinutes(minutes), locale)
        case .dueInHours(let hours): resolve(Key.dueInHours(hours), locale)
        case .overdue: resolve(Key.overdue(), locale)
        case .stillAccepted: resolve(Key.stillAccepted(), locale)
        case .courseWeightPercent(let percent):
            // A whole number already (`reasonPart` rounds it); the locale places the sign.
            resolve(Key.courseWeight(TallyFormat.percent(Double(percent), fractionDigits: 0, locale: locale), courseCode), locale)
        case .courseBelowGoal: resolve(Key.courseBelowGoal(), locale)
        case .nearBoundary: resolve(Key.nearBoundary(), locale)
        case .noDueDate: resolve(Key.noDueDate(), locale)
        }
    }

    /// "Oct 2, 2026" (en_US): the abbreviated date in `calendar`'s time zone.
    private static func date(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, calendar: calendar,
                                        timeZone: calendar.timeZone))
    }

    /// The catalog keys (`Resources/Localizable.xcstrings`). The `defaultValue` is only the
    /// fallback when a lookup finds nothing; the catalog holds the text.
    private enum Key {
        static func reasonJoin(_ first: String, _ second: String) -> LocalizedStringResource {
            LocalizedStringResource("dashboard.reason.join", defaultValue: "\(first) · \(second)", bundle: #bundle,
                                    comment: "Joins the parts of a Next Up item's reason, such as 'Due in 6h' and 'near a grade boundary'. 1: the parts so far. 2: the next part.")
        }
        static func dueInMinutes(_ minutes: Int) -> LocalizedStringResource {
            LocalizedStringResource("dashboard.reason.dueInMinutes", defaultValue: "Due in \(minutes)m", bundle: #bundle,
                                    comment: "Next Up reason, short: the item is due in this many minutes (under an hour). 'm' abbreviates minutes.")
        }
        static func dueInHours(_ hours: Int) -> LocalizedStringResource {
            LocalizedStringResource("dashboard.reason.dueInHours", defaultValue: "Due in \(hours)h", bundle: #bundle,
                                    comment: "Next Up reason, short: the item is due in this many hours. 'h' abbreviates hours.")
        }
        static func overdue() -> LocalizedStringResource {
            LocalizedStringResource("dashboard.reason.overdue", defaultValue: "Overdue", bundle: #bundle,
                                    comment: "Next Up reason: the due date has passed.")
        }
        static func stillAccepted() -> LocalizedStringResource {
            LocalizedStringResource("dashboard.reason.stillAccepted", defaultValue: "Still accepted", bundle: #bundle,
                                    comment: "Next Up reason, after the due-date part: the item is overdue but Canvas still accepts it.")
        }
        static func courseWeight(_ percent: String, _ courseCode: String) -> LocalizedStringResource {
            LocalizedStringResource("dashboard.reason.courseWeight", defaultValue: "~\(percent) of \(courseCode)", bundle: #bundle,
                                    comment: "Next Up reason: roughly how much of the course grade this item is worth. 1: a percentage such as '11%'. 2: the course code from Canvas.")
        }
        static func courseBelowGoal() -> LocalizedStringResource {
            LocalizedStringResource("dashboard.reason.courseBelowGoal", defaultValue: "course below your goal", bundle: #bundle,
                                    comment: "Next Up reason, after the due-date part: the course is below the student's goal.")
        }
        static func nearBoundary() -> LocalizedStringResource {
            LocalizedStringResource("dashboard.reason.nearBoundary", defaultValue: "near a grade boundary", bundle: #bundle,
                                    comment: "Next Up reason, after the due-date part: the course grade is just above a letter-grade cutoff.")
        }
        static func noDueDate() -> LocalizedStringResource {
            LocalizedStringResource("dashboard.reason.noDueDate", defaultValue: "No due date", bundle: #bundle,
                                    comment: "Next Up reason: the item has no due date.")
        }
        static func missingOpenTitle(_ title: String) -> LocalizedStringResource {
            LocalizedStringResource("dashboard.attention.missingOpen.title", defaultValue: "\(title) is missing", bundle: #bundle,
                                    comment: "Needs Attention row: this assignment (its title from Canvas) is missing.")
        }
        static func missingOpenSubtitle(_ courseCode: String) -> LocalizedStringResource {
            LocalizedStringResource("dashboard.attention.missingOpen.subtitle", defaultValue: "\(courseCode) · still accepted", bundle: #bundle,
                                    comment: "Needs Attention row, second line: the course code from Canvas, and that the missing work is still accepted.")
        }
        static func missingClosedTitle(_ courseCode: String) -> LocalizedStringResource {
            LocalizedStringResource("dashboard.attention.missingClosed.title", defaultValue: "\(courseCode): missing work is closed", bundle: #bundle,
                                    comment: "Needs Attention row: in this course (its code from Canvas), missing work can no longer be submitted.")
        }
        static func missingClosedSubtitle() -> LocalizedStringResource {
            LocalizedStringResource("dashboard.attention.missingClosed.subtitle", defaultValue: "Talk to your instructor", bundle: #bundle,
                                    comment: "Needs Attention row, second line, for closed missing work.")
        }
        static func dueSoonTitle(_ title: String, _ time: String) -> LocalizedStringResource {
            LocalizedStringResource("dashboard.attention.dueSoon.title", defaultValue: "\(title) due \(time)", bundle: #bundle,
                                    comment: "Needs Attention row: an assignment is due soon. 1: its title from Canvas. 2: the time it is due, such as '2:30 PM'.")
        }
        static func overloadTitle(_ date: String) -> LocalizedStringResource {
            LocalizedStringResource("dashboard.attention.overload.title", defaultValue: "Busy stretch starting \(date)", bundle: #bundle,
                                    comment: "Needs Attention row: many items are due close together from this date on, such as 'Oct 2, 2026'.")
        }
        static func overloadSubtitle() -> LocalizedStringResource {
            LocalizedStringResource("dashboard.attention.overload.subtitle", defaultValue: "Several items are due close together", bundle: #bundle,
                                    comment: "Needs Attention row, second line, for a busy stretch.")
        }
        static func changeCount(_ count: Int) -> LocalizedStringResource {
            LocalizedStringResource("dashboard.changes.count", defaultValue: "\(count) changes", bundle: #bundle,
                                    comment: "Dashboard chip, first part: how many things changed in Canvas since the last refresh (grades, new assignments, due dates, announcements).")
        }
        static func changesSince(_ changes: String, _ time: String) -> LocalizedStringResource {
            LocalizedStringResource("dashboard.changes.since", defaultValue: "\(changes) since \(time)", bundle: #bundle,
                                    comment: "Dashboard chip. 1: how many changes, such as '6 changes'. 2: the time of the refresh, such as '2:13 PM'.")
        }
    }
}
