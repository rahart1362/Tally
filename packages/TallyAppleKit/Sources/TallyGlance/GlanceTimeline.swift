import Foundation
import TallyDomain
import TallyStore

/// What a widget shows at one moment. Everything time-dependent (which item is next, which are
/// overdue, "today" or "tomorrow", the week strip, whether the glance is stale) is worked out here,
/// for the moment's own date, so a view only formats what it is given.
public enum GlanceContent: Equatable, Sendable {
    /// WidgetKit's placeholder and the gallery preview: the layout with no data in it.
    case placeholder
    case message(GlanceMessage)
    case summary(GlanceSummary)
}

/// Why there is nothing to show, which decides the one line of copy.
public enum GlanceMessage: Equatable, Sendable, CaseIterable {
    case signedOut
    case waitingForFirstSync
    case locked
    case unavailable
    /// The student's access does not include widgets at this moment (pricing-licensing.md PAY-04,
    /// PAY-07: widgets fail closed). Nothing from the glance is shown. `GlanceAccess` decides.
    case subscriptionRequired
}

public struct GlanceSummary: Equatable, Sendable {
    public enum DueDay: Equatable, Sendable {
        case today, tomorrow
        /// Within the next seven days: the view shows the weekday.
        case thisWeek
        /// Later still: the view shows the date.
        case later
    }

    public struct Item: Equatable, Sendable, Identifiable {
        /// The glance item's opaque ID (`GlanceDueItem.id`); empty in tests that do not need it.
        public let id: String
        public let title: String
        public let courseCode: String?
        public let dueAt: Date
        public let day: DueDay

        public init(id: String = "", title: String, courseCode: String?, dueAt: Date, day: DueDay) {
            self.id = id
            self.title = title
            self.courseCode = courseCode
            self.dueAt = dueAt
            self.day = day
        }
    }

    /// Today's items at this moment, for the Lock Screen "Due today" gauge: how many are still open
    /// and how many are done (submitted or excused), as far as the glance knows (it keeps a past
    /// item only while it is open, so `done` is a lower bound once an item's due time has passed).
    public struct Today: Equatable, Sendable {
        public let open: Int
        public let done: Int

        public init(open: Int, done: Int) {
            self.open = open
            self.done = done
        }

        public static let none = Today(open: 0, done: 0)

        public var total: Int { open + done }
        /// The share done, 0...1; 1 when nothing is due today (nothing left to do).
        public var progress: Double { total == 0 ? 1 : Double(done) / Double(total) }
    }

    /// One column of the "Week ahead" strip.
    public struct Day: Equatable, Sendable {
        public enum Coverage: Equatable, Sendable {
            /// Every open item due that day is in the glance.
            case complete
            /// The glance holds `count` of that day's items and may have left out later ones.
            case atLeast
            /// The day is past the last item the glance holds: nothing is known about it.
            case unknown
        }

        /// The day's local midnight.
        public let start: Date
        /// Open items due that day that the glance holds.
        public let count: Int
        public let coverage: Coverage
        /// At least `GlanceTimelinePlanner.busyDayItemCount` open items are due that day.
        public let isBusy: Bool

        public init(start: Date, count: Int, coverage: Coverage, isBusy: Bool) {
            self.start = start
            self.count = count
            self.coverage = coverage
            self.isBusy = isBusy
        }
    }

    /// One course on the medium Standing widget: its code and band, or why it shows "—" instead
    /// (plan 08 §4.4 row 3, XG-02). Present only when the student opted into grades in widgets.
    public struct CourseStanding: Equatable, Sendable, Identifiable {
        public enum Value: Equatable, Sendable {
            case band(GradeBand)
            /// "—": the course's grades do not appear to be kept in Canvas.
            case notInCanvas
            /// "—": the course has no graded work in Canvas.
            case notGradedInCanvas
            /// The instructor hides the course total.
            case hiddenByInstructor
            /// No grade to show yet.
            case noGradeYet
        }

        public let id: String
        public let code: String
        public let value: Value

        public init(id: String, code: String, value: Value) {
            self.id = id
            self.code = code
            self.value = value
        }
    }

    /// The first open item due after this moment. `nil`: nothing is coming up.
    public let nextUp: Item?
    /// Every open item due after this moment that the glance holds, earliest first (`nextUp` first).
    public let upcoming: [Item]
    /// Open items due after `nextUp`.
    public let laterCount: Int
    /// The glance may have left out later items (`GlanceTimelinePlanner.upcomingCutoff`): the
    /// counts are lower bounds.
    public let laterIsLowerBound: Bool
    /// Open items whose due time has passed.
    public let overdueCount: Int
    public let today: Today
    /// Seven days from this moment's day, for the "Week ahead" strip.
    public let week: [Day]
    /// What the Standing widget says (plan 08 §4.4 row 14): the overall grade band, present only
    /// when the user opted in (`UserState.showGradesInGlance`, PMO R10; the views mark it
    /// privacy-sensitive), or why there is none: not opted in, no grades yet, or grades not kept
    /// in Canvas.
    public let grades: GlanceGradeSummary
    /// The Dashboard hero's counts, from the glance's per-course grade statuses (plan 08 §4.4 rows
    /// 1-2): how many courses the average covers, and how many it leaves out.
    public let averagedCourseCount: Int
    public let excludedCourseCount: Int
    /// Per course, only when the student opted into grades in widgets; otherwise empty.
    public let courses: [CourseStanding]
    /// PMO R10 "Hide course names": the views show a generic word instead of titles and codes.
    public let hidesCourseNames: Bool
    public let asOf: Date
    /// The glance is at least `GlanceTimelinePlanner.staleAfter` old at this moment.
    public let isStale: Bool
    /// `asOf` falls on an earlier day than this moment, so "as of" needs the day, not only the time.
    public let asOfIsBeforeToday: Bool

    // The memberwise shape the M2 widgets were built with comes first, so existing call sites keep
    // compiling; everything added for M3-D has a default.
    public init(nextUp: Item?, laterCount: Int, overdueCount: Int, grades: GlanceGradeSummary, asOf: Date,
                isStale: Bool, asOfIsBeforeToday: Bool, upcoming: [Item]? = nil, laterIsLowerBound: Bool = false,
                today: Today = .none, week: [Day] = [], averagedCourseCount: Int = 0, excludedCourseCount: Int = 0,
                courses: [CourseStanding] = [], hidesCourseNames: Bool = false) {
        self.nextUp = nextUp
        self.upcoming = upcoming ?? (nextUp.map { [$0] } ?? [])
        self.laterCount = laterCount
        self.laterIsLowerBound = laterIsLowerBound
        self.overdueCount = overdueCount
        self.today = today
        self.week = week
        self.grades = grades
        self.averagedCourseCount = averagedCourseCount
        self.excludedCourseCount = excludedCourseCount
        self.courses = courses
        self.hidesCourseNames = hidesCourseNames
        self.asOf = asOf
        self.isStale = isStale
        self.asOfIsBeforeToday = asOfIsBeforeToday
    }

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
/// one at the next local midnight (the day words and the week strip change), and one when the
/// glance turns stale (the "as of" footer appears); WidgetKit asks again after the first of those
/// boundaries.
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
    /// The "Week ahead" strip's length, in days, starting today.
    public static let weekDays = 7
    /// insights-at-a-glance.md §1.2 row 5 flags overloaded days. The glance carries no grade
    /// weights, so the widget's rule is a count: this many open items due on one day is "Busy".
    public static let busyDayItemCount = 3
    /// insights-at-a-glance.md §1.5: Smart Stack relevance is high when an item is due within 3 h.
    public static let relevantWithin: TimeInterval = 3 * 60 * 60
    public static let highRelevance: Float = 1
    public static let lowRelevance: Float = 0.1

    public struct Plan: Equatable, Sendable {
        /// The moment for `now`.
        public let current: GlanceMoment
        /// The later boundaries, in order.
        public let upcoming: [GlanceMoment]
        /// WidgetKit's `.after(_:)`.
        public let reloadAfter: Date

        public var moments: [GlanceMoment] { [current] + upcoming }
    }

    /// Smart Stack relevance for one moment: a score, and how long after the moment it holds.
    public struct Relevance: Equatable, Sendable {
        public let score: Float
        public let duration: TimeInterval
    }

    public static func plan(for result: GlanceReadResult, now: Date, calendar: Calendar) -> Plan {
        switch result {
        case .loaded(let glance):
            let dates = boundaries(of: glance, after: now, calendar: calendar)
            return Plan(
                current: moment(of: glance, at: now, calendar: calendar),
                upcoming: dates.map { moment(of: glance, at: $0, calendar: calendar) },
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

    /// A loaded glance's content at `date`: its summary, or the subscription message when access
    /// does not cover widgets then (`GlanceAccess`, the one seam M3-B1's entitlement wires into).
    static func moment(of glance: GlanceProjection, at date: Date, calendar: Calendar) -> GlanceMoment {
        guard GlanceAccess.isUnlocked(glance, at: date) else {
            return GlanceMoment(date: date, content: .message(.subscriptionRequired))
        }
        return GlanceMoment(date: date, content: .summary(summary(of: glance, at: date, calendar: calendar)))
    }

    /// The times after `now` at which the display changes, sorted and unique: each open item's due
    /// time (at most `glanceDueItemLimit`), the next midnight, the stale time, and (M3-B2's O1,
    /// M3-D2) the instant the glance's mirrored entitlement stops covering access
    /// (`EntitlementAccess.accessEnds`), so a timeline built before that moment still gets an entry
    /// right at it: before this, the locked message only appeared at whichever boundary came next.
    static func boundaries(of glance: GlanceProjection, after now: Date, calendar: Calendar) -> [Date] {
        let dues = Set(glance.dueSoon.filter(isOpen).compactMap(\.dueAt).filter { $0 > now })
        var dates = Set(dues.sorted().prefix(TallyConfig.glanceDueItemLimit))
        dates.insert(nextMidnight(after: now, calendar: calendar))
        let staleAt = glance.asOf.addingTimeInterval(staleAfter)
        if staleAt > now { dates.insert(staleAt) }
        if let accessEnds = EntitlementAccess.accessEnds(entitledUntil: glance.entitledUntil), accessEnds > now {
            dates.insert(accessEnds)
        }
        return dates.sorted()
    }

    static func summary(of glance: GlanceProjection, at moment: Date, calendar: Calendar) -> GlanceSummary {
        let dated = glance.dueSoon.filter(isOpen).compactMap { item in item.dueAt.map { (item, $0) } }
        let upcoming = dated.filter { $0.1 > moment }.sorted { ($0.1, $0.0.id) < ($1.1, $1.0.id) }
        let items = upcoming.map { item, due in
            GlanceSummary.Item(id: item.id, title: item.title, courseCode: item.courseShortCode, dueAt: due,
                               day: day(of: due, at: moment, calendar: calendar))
        }
        let cutoff = upcomingCutoff(of: glance)
        let hero = glance.hero
        return GlanceSummary(
            nextUp: items.first,
            laterCount: max(items.count - 1, 0),
            overdueCount: dated.count - upcoming.count,
            grades: glance.gradeSummary,
            asOf: glance.asOf,
            isStale: moment.timeIntervalSince(glance.asOf) >= staleAfter,
            asOfIsBeforeToday: glance.asOf < calendar.startOfDay(for: moment),
            upcoming: items,
            laterIsLowerBound: cutoff != nil,
            today: today(of: glance, at: moment, calendar: calendar),
            week: week(of: glance, at: moment, calendar: calendar, cutoff: cutoff),
            averagedCourseCount: hero.averagedCount,
            excludedCourseCount: hero.exclusions.values.reduce(0, +),
            courses: courseStandings(of: glance),
            hidesCourseNames: GlanceDisplayPolicy.hidesCourseNames(glance))
    }

    /// The items due today at `moment` (local day), open or done. Done means submitted or excused.
    static func today(of glance: GlanceProjection, at moment: Date, calendar: Calendar) -> GlanceSummary.Today {
        let start = calendar.startOfDay(for: moment)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return .none }
        let dueToday = glance.dueSoon.filter { item in item.dueAt.map { $0 >= start && $0 < end } ?? false }
        let open = dueToday.filter(isOpen).count
        return GlanceSummary.Today(open: open, done: dueToday.count - open)
    }

    /// Seven days from `moment`'s day: the open items due on each, how much of the day the glance
    /// covers (`upcomingCutoff`), and whether it is busy.
    static func week(of glance: GlanceProjection, at moment: Date, calendar: Calendar, cutoff: Date?) -> [GlanceSummary.Day] {
        let dues = glance.dueSoon.filter(isOpen).compactMap(\.dueAt)
        let first = calendar.startOfDay(for: moment)
        var days: [GlanceSummary.Day] = []
        for offset in 0..<weekDays {
            guard let start = calendar.date(byAdding: .day, value: offset, to: first),
                  let end = calendar.date(byAdding: .day, value: 1, to: start) else { break }
            let count = dues.filter { $0 >= start && $0 < end }.count
            let coverage: GlanceSummary.Day.Coverage
            if let cutoff {
                coverage = cutoff < start ? .unknown : (cutoff < end ? .atLeast : .complete)
            } else {
                coverage = .complete
            }
            days.append(GlanceSummary.Day(start: start, count: count, coverage: coverage,
                                          isBusy: coverage != .unknown && count >= busyDayItemCount))
        }
        return days
    }

    /// The latest due time up to which the glance is known to hold every item, or `nil` when it
    /// holds every upcoming one. `GlanceProjectionBuilder` keeps the earliest upcoming items and
    /// gives undated items only the slots left over, so a full glance with no undated item may have
    /// dropped items due after its latest upcoming one. Read from the glance alone, so it stays
    /// right if the builder's slot rules change.
    static func upcomingCutoff(of glance: GlanceProjection) -> Date? {
        guard glance.dueSoon.count >= TallyConfig.glanceDueItemLimit,
              !glance.dueSoon.contains(where: { $0.dueAt == nil }) else { return nil }
        return glance.dueSoon.compactMap(\.dueAt).filter { $0 >= glance.asOf }.max()
    }

    /// The medium Standing widget's rows (plan 08 §4.4 rows 3 and 15): a band where the glance has
    /// one, otherwise why not, from the course's grade status. Empty unless the student opted in.
    static func courseStandings(of glance: GlanceProjection) -> [GlanceSummary.CourseStanding] {
        guard glance.gradeSummary != .notOptedIn else { return [] }
        var seen = Set<CanvasID<Course>>()
        return glance.courses.filter { seen.insert($0.id).inserted }.map { course in
            GlanceSummary.CourseStanding(id: course.id.rawValue, code: course.shortCode, value: standingValue(of: course))
        }
    }

    static func standingValue(of course: GlanceCourse) -> GlanceSummary.CourseStanding.Value {
        if let band = course.currentGrade { return .band(band) }
        switch course.gradeStatus {
        case .keptOutsideCanvas?: return .notInCanvas
        case .notGradedInCanvas?: return .notGradedInCanvas
        case .hiddenByInstructor?: return .hiddenByInstructor
        case .averaged?, .noPercentage?, .lettersOnly?, .notYetPosted?, nil: return .noGradeYet
        }
    }

    /// High while the next item is due within `relevantWithin` (until it is due), low otherwise.
    public static func relevance(of content: GlanceContent, at date: Date) -> Relevance {
        guard case .summary(let summary) = content, let next = summary.nextUp else {
            return Relevance(score: lowRelevance, duration: 0)
        }
        let untilDue = next.dueAt.timeIntervalSince(date)
        guard untilDue > 0, untilDue <= relevantWithin else { return Relevance(score: lowRelevance, duration: 0) }
        return Relevance(score: highRelevance, duration: untilDue)
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
