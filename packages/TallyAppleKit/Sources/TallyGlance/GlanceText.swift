import Foundation
import TallyDomain
import TallyStore
import TallyStrings

/// The widgets' and the intents' words, as pure functions (plan 08 §3.2's renderer pattern): each
/// takes the locale explicitly, defaulting to `TallyLocale.effective`, resolves catalog text
/// (`L10n.Widgets`), and formats times and dates for that locale in `calendar`'s time zone
/// (`TallyFormat`). Canvas titles and course codes pass through untouched, except under "Hide
/// course names" (PMO R10). The views only lay out what these return.
enum GlanceText {
    /// The em dash the screens show for a grade that is not in Canvas (plan 08 §4.5).
    static let dash = "—"

    static func resolve(_ resource: LocalizedStringResource, _ locale: Locale) -> String {
        var resource = resource
        resource.locale = locale
        return String(localized: resource)
    }

    // MARK: Grades

    static func bandLabel(_ band: GradeBand, locale: Locale = TallyLocale.effective) -> String {
        resolve(bandResource(band), locale)
    }

    static func bandResource(_ band: GradeBand) -> LocalizedStringResource {
        switch band {
        case .aRange: L10n.Widgets.bandA()
        case .bRange: L10n.Widgets.bandB()
        case .cRange: L10n.Widgets.bandC()
        case .dRange: L10n.Widgets.bandD()
        case .fRange: L10n.Widgets.bandF()
        case .passing: L10n.Widgets.bandPassing()
        case .failing: L10n.Widgets.bandNotPassing()
        case .unknown: L10n.Widgets.bandNone()
        }
    }

    /// What the Standing widget says when it has no band to show (plan 08 §4.4 row 14), or nil
    /// when it has one. "Choose to show grades" only when the student has not opted in: an
    /// opted-in student with no band is told why instead.
    static func standingMessage(_ grades: GlanceGradeSummary) -> (title: LocalizedStringResource, detail: LocalizedStringResource)? {
        switch grades {
        case .band:
            return nil
        case .notOptedIn:
            return (title: L10n.Glance.standingHiddenTitle(), detail: L10n.Glance.standingHiddenDetail())
        case .noneYet:
            return (title: L10n.Glance.standingNoneYetTitle(), detail: L10n.Glance.standingNoneYetDetail())
        case .notInCanvas:
            return (title: L10n.Glance.standingNotInCanvasTitle(), detail: L10n.Glance.standingNotInCanvasDetail())
        }
    }

    /// The Standing widget's caption under the band: the Dashboard hero's "Average of 3 courses",
    /// and "2 courses not included" when the average leaves some out (plan 08 §4.4 rows 1-2).
    static func standingCaptions(_ summary: GlanceSummary, locale: Locale = TallyLocale.effective) -> [String] {
        var lines = [resolve(L10n.Dashboard.averageOfCourses(summary.averagedCourseCount), locale)]
        if summary.excludedCourseCount > 0 {
            lines.append(resolve(L10n.Dashboard.coursesNotIncluded(summary.excludedCourseCount), locale))
        }
        return lines
    }

    /// A course row on the medium Standing widget: the band, or "—" with why (plan 08 §4.4 row 3).
    static func courseValue(_ value: GlanceSummary.CourseStanding.Value,
                            locale: Locale = TallyLocale.effective) -> (value: String, caption: String?) {
        switch value {
        case .band(let band): (bandLabel(band, locale: locale), nil)
        case .notInCanvas: (dash, resolve(L10n.Grades.notInCanvasCaption(), locale))
        case .notGradedInCanvas: (dash, resolve(L10n.Grades.notGradedCaption(), locale))
        case .hiddenByInstructor: (dash, resolve(L10n.Widgets.hiddenByInstructor(), locale))
        case .noGradeYet: (dash, resolve(L10n.Grades.noGradeYet(), locale))
        }
    }

    // MARK: Messages

    static func message(_ message: GlanceMessage, locale: Locale = TallyLocale.effective) -> String {
        resolve(messageResource(message), locale)
    }

    static func messageResource(_ message: GlanceMessage) -> LocalizedStringResource {
        switch message {
        case .signedOut, .unavailable: L10n.Widgets.messageOpenTally()
        case .waitingForFirstSync: L10n.Widgets.messageUpdate()
        case .locked: L10n.Widgets.messageUnlock()
        case .subscriptionRequired: L10n.Widgets.messageSubscribe()
        }
    }

    /// The Lock Screen's few words for the same states.
    static func shortMessage(_ message: GlanceMessage, locale: Locale = TallyLocale.effective) -> String {
        switch message {
        case .signedOut, .unavailable, .waitingForFirstSync: resolve(L10n.Widgets.shortOpenTally(), locale)
        case .locked: resolve(L10n.Widgets.shortUnlock(), locale)
        case .subscriptionRequired: resolve(L10n.Widgets.shortSubscribe(), locale)
        }
    }

    // MARK: Items

    /// The item's title, or a generic word with "Hide course names" on.
    static func title(_ item: GlanceSummary.Item, hidesNames: Bool, locale: Locale = TallyLocale.effective) -> String {
        hidesNames ? resolve(L10n.Widgets.hiddenAssignment(), locale) : item.title
    }

    /// The item's course code, or none with "Hide course names" on.
    static func courseCode(_ item: GlanceSummary.Item, hidesNames: Bool) -> String? {
        hidesNames ? nil : item.courseCode
    }

    /// "Due today, 6:00 PM", "Due tomorrow, 6:00 PM", "Due Tuesday, 6:00 PM" or "Due Oct 14". The
    /// day was worked out for the entry's date (`GlanceTimelinePlanner`).
    static func dueLine(_ item: GlanceSummary.Item, calendar: Calendar, locale: Locale = TallyLocale.effective) -> String {
        let time = TallyFormat.time(item.dueAt, calendar: calendar, locale: locale)
        switch item.day {
        case .today: return resolve(L10n.Widgets.dueToday(time), locale)
        case .tomorrow: return resolve(L10n.Widgets.dueTomorrow(time), locale)
        case .thisWeek: return resolve(L10n.Widgets.dueWeekday(weekday(item.dueAt, calendar: calendar, locale: locale), time), locale)
        case .later: return resolve(L10n.Widgets.dueDate(shortDate(item.dueAt, calendar: calendar, locale: locale)), locale)
        }
    }

    /// The Lock Screen's short due time: "6:00 PM", "Tomorrow 6:00 PM", "Tue 6:00 PM" or "Oct 14".
    static func shortWhen(_ item: GlanceSummary.Item, calendar: Calendar, locale: Locale = TallyLocale.effective) -> String {
        let time = TallyFormat.time(item.dueAt, calendar: calendar, locale: locale)
        switch item.day {
        case .today: return time
        case .tomorrow: return resolve(L10n.Widgets.shortTomorrow(time), locale)
        case .thisWeek:
            return resolve(L10n.Widgets.shortWeekday(weekdayShort(item.dueAt, calendar: calendar, locale: locale), time), locale)
        case .later: return shortDate(item.dueAt, calendar: calendar, locale: locale)
        }
    }

    /// The spoken due time: "today at 6:00 PM", "tomorrow at 6:00 PM", "Friday at 6:00 PM" or "Oct 14".
    static func spokenWhen(_ item: GlanceSummary.Item, calendar: Calendar, locale: Locale = TallyLocale.effective) -> String {
        let time = TallyFormat.time(item.dueAt, calendar: calendar, locale: locale)
        switch item.day {
        case .today: return resolve(L10n.Widgets.whenToday(time), locale)
        case .tomorrow: return resolve(L10n.Widgets.whenTomorrow(time), locale)
        case .thisWeek: return resolve(L10n.Widgets.whenWeekday(weekday(item.dueAt, calendar: calendar, locale: locale), time), locale)
        case .later: return shortDate(item.dueAt, calendar: calendar, locale: locale)
        }
    }

    /// The rectangular Lock Screen widget's second line: "BIO 101 · 6:00 PM", or the time alone.
    static func courseAndWhen(_ item: GlanceSummary.Item, hidesNames: Bool, calendar: Calendar,
                              locale: Locale = TallyLocale.effective) -> String {
        let when = shortWhen(item, calendar: calendar, locale: locale)
        guard let code = courseCode(item, hidesNames: hidesNames) else { return when }
        return resolve(L10n.Widgets.courseAndTime(code, when), locale)
    }

    /// The inline Lock Screen widget: "Next: Lab Report 4, 6:00 PM".
    static func inlineNext(_ item: GlanceSummary.Item, hidesNames: Bool, calendar: Calendar,
                           locale: Locale = TallyLocale.effective) -> String {
        resolve(L10n.Widgets.inlineNext(title(item, hidesNames: hidesNames, locale: locale),
                                        shortWhen(item, calendar: calendar, locale: locale)), locale)
    }

    /// "+2 more · 1 overdue"; `nil` when both are zero. "+2 or more" when the glance may hold only
    /// some of the later items.
    static func counts(later: Int, overdue: Int, laterIsLowerBound: Bool = false,
                       locale: Locale = TallyLocale.effective) -> String? {
        let laterText = later > 0
            ? resolve(laterIsLowerBound ? L10n.Widgets.laterAtLeast(later) : L10n.Widgets.laterCount(later), locale) : nil
        let overdueText = overdue > 0 ? resolve(L10n.Widgets.overdueCount(overdue), locale) : nil
        switch (laterText, overdueText) {
        case let (later?, overdue?): return resolve(L10n.Widgets.countsJoin(later, overdue), locale)
        case let (later?, nil): return later
        case let (nil, overdue?): return overdue
        case (nil, nil): return nil
        }
    }

    /// "As of 2:14 PM", or "As of Tue 2:14 PM" when the glance is from an earlier day
    /// (insights-at-a-glance.md §1.5).
    static func asOf(_ summary: GlanceSummary, calendar: Calendar, locale: Locale = TallyLocale.effective) -> String {
        resolve(L10n.Widgets.asOf(asOfTime(summary, calendar: calendar, locale: locale)), locale)
    }

    static func asOfTime(_ summary: GlanceSummary, calendar: Calendar, locale: Locale) -> String {
        guard summary.asOfIsBeforeToday else { return TallyFormat.time(summary.asOf, calendar: calendar, locale: locale) }
        return summary.asOf.formatted(style(calendar, locale).weekday(.abbreviated).hour().minute())
    }

    /// The footer under a list: "As of …" once stale, otherwise the counts, if any.
    static func footer(_ summary: GlanceSummary, shown: Int, calendar: Calendar,
                       locale: Locale = TallyLocale.effective) -> String? {
        if summary.isStale { return asOf(summary, calendar: calendar, locale: locale) }
        return counts(later: max(summary.upcoming.count - shown, 0), overdue: summary.overdueCount,
                      laterIsLowerBound: summary.laterIsLowerBound, locale: locale)
    }

    // MARK: Week ahead and today

    /// A day column's count: "3", "3+" when the glance may hold only some of that day's items, and
    /// "—" past what the glance holds.
    static func dayCount(_ day: GlanceSummary.Day, locale: Locale = TallyLocale.effective) -> String {
        switch day.coverage {
        case .complete: day.count.formatted(.number.locale(locale))
        case .atLeast: resolve(L10n.Widgets.atLeast(day.count), locale)
        case .unknown: dash
        }
    }

    static func busy(locale: Locale = TallyLocale.effective) -> String {
        resolve(L10n.Widgets.busy(), locale)
    }

    static func number(_ value: Int, locale: Locale = TallyLocale.effective) -> String {
        value.formatted(.number.locale(locale))
    }

    // MARK: Dates

    static func weekday(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        date.formatted(style(calendar, locale).weekday(.wide))
    }

    static func weekdayShort(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        date.formatted(style(calendar, locale).weekday(.abbreviated))
    }

    static func shortDate(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        date.formatted(style(calendar, locale).month(.abbreviated).day())
    }

    private static func style(_ calendar: Calendar, _ locale: Locale) -> Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    }
}
