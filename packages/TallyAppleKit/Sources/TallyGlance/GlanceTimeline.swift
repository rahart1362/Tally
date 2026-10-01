import Foundation
import TallyDomain
import TallyStore

/// What a widget shows at one moment. Everything time-dependent (which item is next, which are
/// overdue, "today" or "tomorrow", whether the glance is stale) is worked out here, for the
/// moment's own date, so a view only formats what it is given.
public enum GlanceContent: Equatable, Sendable {
    /// WidgetKit's placeholder and the gallery preview: the layout with no data in it.
    case placeholder
    case message(GlanceMessage)
    case summary(GlanceSummary)
}

/// Why there is nothing to show (`GlanceReadResult`'s other cases), which decides the one line of copy.
public enum GlanceMessage: Equatable, Sendable {
    case signedOut
    case waitingForFirstSync
    case locked
    case unavailable
}

public struct GlanceSummary: Equatable, Sendable {
    public enum DueDay: Equatable, Sendable {
        case today, tomorrow
        /// Within the next seven days: the view shows the weekday.
        case thisWeek
        /// Later still: the view shows the date.
        case later
    }

    public struct Item: Equatable, Sendable {
        public let title: String
        public let courseCode: String?
        public let dueAt: Date
        public let day: DueDay
    }

    /// The first open item due after this moment. `nil`: nothing is coming up.
    public let nextUp: Item?
    /// Open items due after `nextUp`.
    public let laterCount: Int
    /// Open items whose due time has passed.
    public let overdueCount: Int
    /// What the Standing widget says (plan 08 §4.4 row 14): the overall grade band, present only
    /// when the user opted in (`UserState.showGradesInGlance`, PMO R10; the views mark it
    /// privacy-sensitive), or why there is none: not opted in, no grades yet, or grades not kept
    /// in Canvas.
    public let grades: GlanceGradeSummary
    public let asOf: Date
    /// The glance is at least `GlanceTimelinePlanner.staleAfter` old at this moment.
    public let isStale: Bool
    /// `asOf` falls on an earlier day than this moment, so "as of" needs the day, not only the time.
    public let asOfIsBeforeToday: Bool

    /// The overall grade band, when `grades` has one.
    public var standing: GradeBand? {
        if case .band(let band) = grades { return band }
        return nil
    }
}

public struct GlanceMoment: Equatable, Sendable {
    public let date: Date
    public let content: GlanceContent

    public init(date: Date, content: GlanceContent) {
        self.date = date
        self.content = content
    }
}

/// A widget timeline over one read of the glance (plan 06 step 11; perf-app-runtime.md §2.4 W2):
/// an entry now, one at each open item's due time (at most `TallyConfig.glanceDueItemLimit`),
/// one at the next local midnight (the day words change), and one when the glance turns stale
/// (the "as of" footer appears); WidgetKit asks again after the first of those boundaries.
///
/// Reloading at the first boundary re-reads the glance (≤ 16 KB), so a commit whose own reload
/// request WidgetKit deferred shows up by then at the latest; the later entries keep the display
/// right if WidgetKit defers that reload too. At most `glanceDueItemLimit` + 2 reloads a day come
/// from this policy, inside the 40-70 a day Apple documents as a typical widget budget
/// ("Keeping a widget up to date").
public enum GlanceTimelinePlanner {
    /// insights-at-a-glance.md §1.5: "When glance.v1 is more than 3 h old, the footer reads
    /// 'as of 2:14 PM'."
    public static let staleAfter: TimeInterval = 3 * 60 * 60
    /// Before the first unlock the glance cannot be read; that ends at the first unlock, so ask
    /// again soon.
    public static let lockedRetry: TimeInterval = 15 * 60
    /// A Keychain or container failure may be persistent (no Team ID, GL-02): ask again hourly,
    /// not at a rate that would spend WidgetKit's budget.
    public static let unavailableRetry: TimeInterval = 60 * 60

    public struct Plan: Equatable, Sendable {
        /// The moment for `now`.
        public let current: GlanceMoment
        /// The later boundaries, in order.
        public let upcoming: [GlanceMoment]
        /// WidgetKit's `.after(_:)`.
        public let reloadAfter: Date

        public var moments: [GlanceMoment] { [current] + upcoming }
    }

    public static func plan(for result: GlanceReadResult, now: Date, calendar: Calendar) -> Plan {
        switch result {
        case .loaded(let glance):
            let dates = boundaries(of: glance, after: now, calendar: calendar)
            return Plan(
                current: GlanceMoment(date: now, content: .summary(summary(of: glance, at: now, calendar: calendar))),
                upcoming: dates.map { GlanceMoment(date: $0, content: .summary(summary(of: glance, at: $0, calendar: calendar))) },
                reloadAfter: dates.first ?? nextMidnight(after: now, calendar: calendar))
        case .noAccount:
            // Sign-in and the first commit reload the widget from the app (perf-app-runtime.md §2.4 S9).
            return message(.signedOut, now: now, reloadAfter: nextMidnight(after: now, calendar: calendar))
        case .noGlance:
            return message(.waitingForFirstSync, now: now, reloadAfter: nextMidnight(after: now, calendar: calendar))
        case .locked:
            return message(.locked, now: now, reloadAfter: now.addingTimeInterval(lockedRetry))
        case .unavailable:
            return message(.unavailable, now: now, reloadAfter: now.addingTimeInterval(unavailableRetry))
        }
    }

    /// The times after `now` at which the display changes, sorted and unique: each open item's due
    /// time (at most `glanceDueItemLimit`), the next midnight and the stale time.
    static func boundaries(of glance: GlanceProjection, after now: Date, calendar: Calendar) -> [Date] {
        let dues = Set(glance.dueSoon.filter(isOpen).compactMap(\.dueAt).filter { $0 > now })
        var dates = Set(dues.sorted().prefix(TallyConfig.glanceDueItemLimit))
        dates.insert(nextMidnight(after: now, calendar: calendar))
        let staleAt = glance.asOf.addingTimeInterval(staleAfter)
        if staleAt > now { dates.insert(staleAt) }
        return dates.sorted()
    }

    static func summary(of glance: GlanceProjection, at moment: Date, calendar: Calendar) -> GlanceSummary {
        let dated = glance.dueSoon.filter(isOpen).compactMap { item in item.dueAt.map { (item, $0) } }
        let upcoming = dated.filter { $0.1 > moment }.sorted { ($0.1, $0.0.id) < ($1.1, $1.0.id) }
        let next = upcoming.first.map { item, due in
            GlanceSummary.Item(title: item.title, courseCode: item.courseShortCode, dueAt: due,
                               day: day(of: due, at: moment, calendar: calendar))
        }
        return GlanceSummary(
            nextUp: next,
            laterCount: max(upcoming.count - 1, 0),
            overdueCount: dated.count - upcoming.count,
            grades: glance.gradeSummary,
            asOf: glance.asOf,
            isStale: moment.timeIntervalSince(glance.asOf) >= staleAfter,
            asOfIsBeforeToday: glance.asOf < calendar.startOfDay(for: moment))
    }

    static func day(of due: Date, at moment: Date, calendar: Calendar) -> GlanceSummary.DueDay {
        let today = calendar.startOfDay(for: moment)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
              let dayAfter = calendar.date(byAdding: .day, value: 2, to: today),
              let weekOut = calendar.date(byAdding: .day, value: 7, to: today)
        else { return .later }
        if due < tomorrow { return .today }
        if due < dayAfter { return .tomorrow }
        return due < weekOut ? .thisWeek : .later
    }

    /// The first local midnight after `now` (DST-safe: a calendar day, not 24 hours).
    static func nextMidnight(after now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: 1, to: today) ?? now.addingTimeInterval(24 * 60 * 60)
    }

    /// Submitted and excused items need nothing more from the student.
    static func isOpen(_ item: GlanceDueItem) -> Bool { !item.submitted && !item.excused }

    private static func message(_ message: GlanceMessage, now: Date, reloadAfter: Date) -> Plan {
        Plan(current: GlanceMoment(date: now, content: .message(message)), upcoming: [], reloadAfter: reloadAfter)
    }
}
