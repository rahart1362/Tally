import Foundation
import Testing
import TallyDomain
import TallyStore
import TallyTestSupport
@testable import TallyGlance

/// Plan 06 step 11 (W2): one entry per due-item boundary (at most `glanceDueItemLimit`) plus the
/// next midnight, with `.after(next boundary)`; plus the stale time the "as of" footer needs
/// (insights-at-a-glance.md §1.5).
@Suite("Widget glance timeline")
struct WidgetGlanceTimelineTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        return calendar
    }()

    /// Tuesday 2026-10-06, 10:00 in New York.
    private static let now = date(2026, 10, 6, 10, 0)

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? .distantPast
    }

    private static func item(_ id: String, due: Date?, submitted: Bool = false, excused: Bool = false) -> GlanceDueItem {
        GlanceDueItem(id: id, courseShortCode: "BIO 101", title: "Item \(id)", dueAt: due,
                      missing: false, late: false, excused: excused, submitted: submitted)
    }

    private static let overdue = date(2026, 10, 6, 8, 0)
    private static let laterToday = date(2026, 10, 6, 12, 0)
    private static let tomorrowMorning = date(2026, 10, 7, 9, 0)
    private static let friday = date(2026, 10, 9, 17, 0)
    private static let nextMonth = date(2026, 11, 3, 23, 59)
    private static let asOf = date(2026, 10, 6, 8, 30)
    private static let staleAt = date(2026, 10, 6, 11, 30) // asOf + 3 h
    private static let midnight = date(2026, 10, 7, 0, 0)

    /// M3-B2: enforcement is on, so the glance carries the student's entitlement.
    private static func glance(grades: GradeBand? = nil) -> GlanceProjection {
        GlanceProjection(generation: 3, asOf: asOf, gradeSummary: grades.map(GlanceGradeSummary.band) ?? .notOptedIn,
                         courses: [], dueSoon: [
            item("overdue", due: overdue),
            item("later-today", due: laterToday),
            item("tomorrow", due: tomorrowMorning),
            item("friday", due: friday),
            item("next-month", due: nextMonth),
            item("submitted", due: date(2026, 10, 6, 11, 0), submitted: true),
            item("excused", due: date(2026, 10, 6, 14, 0), excused: true),
            item("undated", due: nil),
        ], entitledUntil: GlanceStoreFixture.entitledUntil)
    }

    private static func summary(_ moment: GlanceMoment) -> GlanceSummary? {
        if case .summary(let summary) = moment.content { return summary }
        return nil
    }

    @Test("entries: now, each open item's due time, the next midnight and the stale time; reload after the first")
    func boundaries() {
        let plan = GlanceTimelinePlanner.plan(for: .loaded(Self.glance()), now: Self.now, calendar: Self.calendar)

        #expect(plan.current.date == Self.now)
        #expect(plan.upcoming.map(\.date) == [Self.staleAt, Self.laterToday, Self.midnight, Self.tomorrowMorning,
                                              Self.friday, Self.nextMonth])
        #expect(plan.reloadAfter == Self.staleAt)
        // Submitted and excused items change nothing on screen, so their due times are no boundary.
        #expect(!plan.upcoming.map(\.date).contains(Self.date(2026, 10, 6, 11, 0)))
        #expect(!plan.upcoming.map(\.date).contains(Self.date(2026, 10, 6, 14, 0)))
    }

    @Test("now: the next open item, with later and overdue counts; submitted, excused and undated items never count")
    func summaryNow() throws {
        let plan = GlanceTimelinePlanner.plan(for: .loaded(Self.glance()), now: Self.now, calendar: Self.calendar)
        let summary = try #require(Self.summary(plan.current))

        #expect(summary.nextUp?.title == "Item later-today")
        #expect(summary.nextUp?.courseCode == "BIO 101")
        #expect(summary.nextUp?.day == .today)
        #expect(summary.laterCount == 3)
        #expect(summary.overdueCount == 1)
        #expect(summary.isStale == false)
        #expect(summary.standing == nil)
    }

    @Test("at an item's due time it becomes overdue and the next one is up")
    func dueBoundary() throws {
        let plan = GlanceTimelinePlanner.plan(for: .loaded(Self.glance()), now: Self.now, calendar: Self.calendar)
        let atDue = try #require(plan.upcoming.first { $0.date == Self.laterToday }.flatMap(Self.summary))

        #expect(atDue.nextUp?.title == "Item tomorrow")
        #expect(atDue.nextUp?.day == .tomorrow)
        #expect(atDue.laterCount == 2)
        #expect(atDue.overdueCount == 2)
    }

    @Test("at midnight the day words move on: tomorrow becomes today; the stale footer then needs the day")
    func midnightBoundary() throws {
        let plan = GlanceTimelinePlanner.plan(for: .loaded(Self.glance()), now: Self.now, calendar: Self.calendar)
        let atMidnight = try #require(plan.upcoming.first { $0.date == Self.midnight }.flatMap(Self.summary))

        #expect(atMidnight.nextUp?.title == "Item tomorrow")
        #expect(atMidnight.nextUp?.day == .today)
        #expect(atMidnight.isStale)
        #expect(atMidnight.asOfIsBeforeToday)
        #expect(GlanceTimelinePlanner.day(of: Self.friday, at: Self.midnight, calendar: Self.calendar) == .thisWeek)
        #expect(GlanceTimelinePlanner.day(of: Self.nextMonth, at: Self.midnight, calendar: Self.calendar) == .later)
    }

    @Test("the glance turns stale three hours after it was fetched, and not before")
    func staleBoundary() throws {
        let plan = GlanceTimelinePlanner.plan(for: .loaded(Self.glance()), now: Self.now, calendar: Self.calendar)
        let atStale = try #require(plan.upcoming.first { $0.date == Self.staleAt }.flatMap(Self.summary))
        #expect(atStale.isStale)
        #expect(atStale.asOfIsBeforeToday == false)

        let justBefore = GlanceTimelinePlanner.plan(for: .loaded(Self.glance()), now: Self.staleAt.addingTimeInterval(-1),
                                                    calendar: Self.calendar)
        #expect(Self.summary(justBefore.current)?.isStale == false)
    }

    @Test("at most glanceDueItemLimit due-time entries, whatever the glance holds")
    func dueBoundariesAreCapped() {
        let many = (1...12).map { Self.item("i\($0)", due: Self.now.addingTimeInterval(Double($0) * 600)) }
        let glance = GlanceProjection(generation: 1, asOf: Self.now, overallGradeBand: nil, courses: [], dueSoon: many)
        let dates = GlanceTimelinePlanner.boundaries(of: glance, after: Self.now, calendar: Self.calendar)
        let dueDates = Set(many.compactMap(\.dueAt))

        #expect(dates.filter(dueDates.contains).count == TallyConfig.glanceDueItemLimit)
        #expect(dates.contains(Self.midnight))
        #expect(dates == dates.sorted())
    }

    @Test("a grade reaches the widget only when the glance was built with grades (opt-in, PMO R10)")
    func gradesOnlyWhenOptedIn() throws {
        let snapshot = CanvasSnapshotFixture.make(fetchedAt: Self.asOf)
        let without = GlanceProjectionBuilder.build(from: snapshot, includeGrades: false,
                                                    entitledUntil: GlanceStoreFixture.entitledUntil)
        let with = GlanceProjectionBuilder.build(from: snapshot, includeGrades: true, entitledUntil: GlanceStoreFixture.entitledUntil)

        let hidden = GlanceTimelinePlanner.plan(for: .loaded(without), now: Self.now, calendar: Self.calendar)
        let shown = GlanceTimelinePlanner.plan(for: .loaded(with), now: Self.now, calendar: Self.calendar)

        #expect(hidden.moments.compactMap(Self.summary).allSatisfy { $0.standing == nil })
        let band = try #require(with.overallGradeBand)
        #expect(shown.moments.compactMap(Self.summary).allSatisfy { $0.standing == band })
    }

    @Test("nothing to read: one message entry; the app reloads the widget, and locked or failed reads retry later")
    func messages() {
        func plan(_ result: GlanceReadResult) -> GlanceTimelinePlanner.Plan {
            GlanceTimelinePlanner.plan(for: result, now: Self.now, calendar: Self.calendar)
        }
        #expect(plan(.noAccount).current.content == .message(.signedOut))
        #expect(plan(.noAccount).reloadAfter == Self.midnight)
        #expect(plan(.noGlance).current.content == .message(.waitingForFirstSync))
        #expect(plan(.noGlance).reloadAfter == Self.midnight)
        #expect(plan(.locked).current.content == .message(.locked))
        #expect(plan(.locked).reloadAfter == Self.now.addingTimeInterval(GlanceTimelinePlanner.lockedRetry))
        #expect(plan(.unavailable).current.content == .message(.unavailable))
        #expect(plan(.unavailable).reloadAfter == Self.now.addingTimeInterval(GlanceTimelinePlanner.unavailableRetry))
        #expect([GlanceReadResult.noAccount, .noGlance, .locked, .unavailable].allSatisfy { plan($0).upcoming.isEmpty })
    }

    @Test("the next midnight is a calendar day, across a daylight-saving change")
    func midnightAcrossDST() {
        // New York leaves daylight time at 02:00 on 2026-11-01: that day is 25 hours long, so its
        // midnight is 24.5 h after 00:30, not 23.5 h (start of day + 24 h would land at 23:00).
        let startOfTheLongDay = Self.date(2026, 11, 1, 0, 30)
        let next = GlanceTimelinePlanner.nextMidnight(after: startOfTheLongDay, calendar: Self.calendar)
        #expect(next == Self.date(2026, 11, 2, 0, 0))
        #expect(next.timeIntervalSince(startOfTheLongDay) == 24.5 * 60 * 60)
        let beforeTheChange = Self.date(2026, 10, 31, 23, 30)
        #expect(GlanceTimelinePlanner.nextMidnight(after: beforeTheChange, calendar: Self.calendar) == Self.date(2026, 11, 1, 0, 0))
    }
}
