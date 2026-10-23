import Foundation
import TallyDomain
import TallyStrings

/// Idea 11 ("Send my week", `pmo-audit/.build-audit/ideas1/report.md`): the share sheet's
/// plain-text weekly summary, built the same way `PairingInviteText` builds its own (a pure
/// `String`, no `TallyDomain`-layer renderer -- this file is already the UI-only layer
/// `CalendarEventDraft`/`PairingInviteText` live in).
///
/// **Never a grade value, structurally**: the input, `DashboardProjection.WeekDayItem`, carries a
/// title, a course code and a due date -- no score, percentage or letter grade field exists to
/// leak (the same structural guarantee `NotificationContent.swift` documents for push content,
/// PMO R10).
///
/// **"Hide Course Names" (R10)**: with it on, a day's line names neither the course nor the
/// assignment -- a count only -- mirroring `NotificationMessage`'s own rule that the toggle hides
/// both the course code and the item's title, despite its name.
///
/// Student-only (PMO scope, 10-19): no family or parent account linkage.
enum WeekShareText {
    static func text(days: [DashboardProjection.WeekDay], hideCourseNames: Bool) -> String {
        let total = days.reduce(0) { $0 + $1.dueCount }
        let lines = days.compactMap { day in dayLine(for: day, hideCourseNames: hideCourseNames) }
        return ([String(localized: L10n.Dashboard.shareWeekHeader(total))] + lines).joined(separator: "\n")
    }

    /// `nil` for a day with nothing due: an empty week shares as the header line alone, never a
    /// list of empty days.
    private static func dayLine(for day: DashboardProjection.WeekDay, hideCourseNames: Bool) -> String? {
        guard !day.items.isEmpty else { return nil }
        let weekday = day.date.formatted(.dateTime.weekday(.abbreviated).locale(TallyLocale.effective))
        guard !hideCourseNames else {
            return String(localized: L10n.Dashboard.shareWeekDayCountOnly(weekday, day.items.count))
        }
        let titles = day.items.map { item in item.courseCode.map { "\($0): \(item.title)" } ?? item.title }
            .joined(separator: ", ")
        return String(localized: L10n.Dashboard.shareWeekDayTitles(weekday, titles))
    }
}
