import Foundation
import Testing
import TallyDomain
import TallyStore
@testable import TallyGlance

/// M3-D (UX-WP-29): what the new widgets and the App Shortcuts work out from the glance, before any
/// view draws it: the week strip and how much of it the glance covers, today's gauge, the Standing
/// widget's course rows and counts, Smart Stack relevance, the subscription seam, and the spoken
/// answers. Foundation and TallyCore only, so a scratch harness also runs this file on Linux.
@Suite("Widgets M3-D: week, today, standing rows, relevance and the intents' answers")
struct WidgetPlannerTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        return calendar
    }()

    /// Tuesday 2026-10-06, 10:00 in New York; the glance is from 08:30.
    private static let now = date(6, 10, 0)
    private static let asOf = date(6, 8, 30)

    private static func date(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute)) ?? .distantPast
    }

    private static func item(_ id: String, _ due: Date?, code: String? = "BIO 101", submitted: Bool = false,
                             excused: Bool = false) -> GlanceDueItem {
        GlanceDueItem(id: id, courseShortCode: code, title: "Item \(id)", dueAt: due, missing: false, late: false,
                      excused: excused, submitted: submitted)
    }

    /// M3-B2: enforcement is on, so a glance carries the student's entitlement (to December) unless a
    /// test says otherwise; with none, the widgets and the intents are locked.
    private static let entitledUntil = date(6, 10, month: 12)

    private static func glance(_ items: [GlanceDueItem], courses: [GlanceCourse] = [],
                               grades: GlanceGradeSummary = .notOptedIn,
                               entitledUntil: Date? = WidgetPlannerTests.entitledUntil) -> GlanceProjection {
        GlanceProjection(generation: 1, asOf: asOf, gradeSummary: grades, courses: courses, dueSoon: items,
                         entitledUntil: entitledUntil)
    }

    private static func summary(_ glance: GlanceProjection, at moment: Date = now) throws -> GlanceSummary {
        let plan = GlanceTimelinePlanner.plan(for: .loaded(glance), now: moment, calendar: calendar)
        guard case .summary(let summary) = plan.current.content else {
            throw PlannerTestError.noSummary("\(plan.current.content)")
        }
        return summary
    }

    private enum PlannerTestError: Error { case noSummary(String) }

    // MARK: Week ahead

    @Test("Week strip: seven days from today, open items per day, Busy at three, all complete when the glance has room")
    func weekStrip() throws {
        let summary = try Self.summary(Self.glance([
            Self.item("overdue-today", Self.date(6, 8)),
            Self.item("today", Self.date(6, 12)),
            Self.item("today-submitted", Self.date(6, 15), submitted: true),
            Self.item("wed-1", Self.date(7, 9)), Self.item("wed-2", Self.date(7, 10)), Self.item("wed-3", Self.date(7, 23, 59)),
            Self.item("fri", Self.date(9, 17)),
        ]))

        #expect(summary.week.count == GlanceTimelinePlanner.weekDays)
        #expect(summary.week.first?.start == Self.calendar.startOfDay(for: Self.now))
        // Today counts the open item already past due as well as the one still coming; the submitted one is done.
        #expect(summary.week.map(\.count) == [2, 3, 0, 1, 0, 0, 0])
        #expect(summary.week.map(\.isBusy) == [false, true, false, false, false, false, false])
        #expect(summary.week.allSatisfy { $0.coverage == .complete })
        #expect(!summary.laterIsLowerBound)
        #expect(GlanceTimelinePlanner.upcomingCutoff(of: Self.glance([Self.item("a", Self.date(7, 9))])) == nil)
    }

    @Test("A full glance: days through its last item are complete, that day is 'at least', later days unknown")
    func weekStripCoverage() throws {
        let full = Self.glance([
            Self.item("tue-1", Self.date(6, 12)), Self.item("tue-2", Self.date(6, 14)),
            Self.item("wed-1", Self.date(7, 9)), Self.item("wed-2", Self.date(7, 10)),
            Self.item("thu-1", Self.date(8, 9)), Self.item("thu-2", Self.date(8, 10)), Self.item("thu-3", Self.date(8, 11)),
            Self.item("fri-1", Self.date(9, 9)),
        ])
        #expect(full.dueSoon.count == TallyConfig.glanceDueItemLimit)
        #expect(GlanceTimelinePlanner.upcomingCutoff(of: full) == Self.date(9, 9))

        let summary = try Self.summary(full)
        #expect(summary.week.map(\.coverage) == [.complete, .complete, .complete, .atLeast, .unknown, .unknown, .unknown])
        #expect(summary.week.map(\.count) == [2, 2, 3, 1, 0, 0, 0])
        #expect(summary.week.map(\.isBusy) == [false, false, true, false, false, false, false])
        #expect(summary.laterIsLowerBound, "the glance may have dropped later items: '+7 or more'")

        // An undated item gets only a slot the dated items left, so a glance holding one dropped nothing.
        var withUndated = Array(full.dueSoon.dropLast())
        withUndated.append(Self.item("undated", nil))
        #expect(GlanceTimelinePlanner.upcomingCutoff(of: Self.glance(withUndated)) == nil)
        // A full glance of overdue items holds no upcoming item at all: nothing upcoming was dropped.
        let overdueOnly = (1...TallyConfig.glanceDueItemLimit).map { Self.item("late-\($0)", Self.date(5, $0)) }
        #expect(GlanceTimelinePlanner.upcomingCutoff(of: Self.glance(overdueOnly)) == nil)
    }

    // MARK: Due today

    @Test("Today: open and done (submitted or excused) items due today; nothing due reads as all done")
    func dueToday() throws {
        let summary = try Self.summary(Self.glance([
            Self.item("this-morning", Self.date(6, 8)),
            Self.item("noon", Self.date(6, 12)),
            Self.item("submitted", Self.date(6, 14), submitted: true),
            Self.item("excused", Self.date(6, 16), excused: true),
            Self.item("tomorrow", Self.date(7, 9)),
            Self.item("yesterday", Self.date(5, 23)),
        ]))
        #expect(summary.today == GlanceSummary.Today(open: 2, done: 2))
        #expect(summary.today.progress == 0.5)

        let empty = try Self.summary(Self.glance([Self.item("tomorrow", Self.date(7, 9))]))
        #expect(empty.today == .none)
        #expect(empty.today.progress == 1)
    }

    // MARK: Standing

    @Test("Standing rows: none unless opted in; a band, or why not, from each course's grade status; each course once")
    func standingRows() throws {
        func course(_ id: String, _ band: GradeBand?, _ status: CourseGradeStatus?) -> GlanceCourse {
            GlanceCourse(id: CanvasID(id), shortCode: "C\(id)", currentGrade: band, gradeStatus: status)
        }
        let courses = [
            course("1", .aRange, .averaged), course("2", nil, .keptOutsideCanvas), course("3", nil, .notGradedInCanvas),
            course("4", nil, .hiddenByInstructor), course("5", nil, .notYetPosted), course("6", nil, nil),
            course("1", .aRange, .averaged),
        ]
        let optedIn = try Self.summary(Self.glance([], courses: courses, grades: .band(.aRange)))
        #expect(optedIn.courses.map(\.id) == ["1", "2", "3", "4", "5", "6"])
        #expect(optedIn.courses.map(\.value) == [.band(.aRange), .notInCanvas, .notGradedInCanvas, .hiddenByInstructor,
                                                 .noGradeYet, .noGradeYet])
        #expect(optedIn.courses.first?.code == "C1")

        let optedOut = try Self.summary(Self.glance([], courses: courses, grades: .notOptedIn))
        #expect(optedOut.courses.isEmpty, "no course grade or status row unless the student opted into grades in widgets")
    }

    @Test("Standing counts: the courses the average covers and the ones it leaves out, as on the Dashboard hero")
    func standingCounts() throws {
        let courses = [
            GlanceCourse(id: CanvasID("1"), shortCode: "A", currentGrade: .aRange, gradeStatus: .averaged),
            GlanceCourse(id: CanvasID("2"), shortCode: "B", currentGrade: .bRange, gradeStatus: .averaged),
            GlanceCourse(id: CanvasID("3"), shortCode: "C", currentGrade: nil, gradeStatus: .keptOutsideCanvas),
            GlanceCourse(id: CanvasID("4"), shortCode: "D", currentGrade: nil, gradeStatus: .notYetPosted),
        ]
        let summary = try Self.summary(Self.glance([], courses: courses, grades: .band(.aRange)))
        #expect(summary.averagedCourseCount == 2)
        #expect(summary.excludedCourseCount == 2)
    }

    // MARK: Relevance, access, policy

    @Test("Relevance: high from 3 hours before the next item is due until it is due; low otherwise")
    func relevance() throws {
        let glance = Self.glance([Self.item("noon", Self.date(6, 12))])
        let inTwoHours = GlanceTimelinePlanner.relevance(of: .summary(try Self.summary(glance)), at: Self.now)
        #expect(inTwoHours == .init(score: GlanceTimelinePlanner.highRelevance, duration: 2 * 60 * 60))

        let early = Self.date(6, 8, 30)
        let threeAndAHalfHours = GlanceTimelinePlanner.relevance(of: .summary(try Self.summary(glance, at: early)), at: early)
        #expect(threeAndAHalfHours.score == GlanceTimelinePlanner.lowRelevance)
        #expect(GlanceTimelinePlanner.relevance(of: .message(.signedOut), at: Self.now).score == GlanceTimelinePlanner.lowRelevance)
        #expect(GlanceTimelinePlanner.relevance(of: .placeholder, at: Self.now).duration == 0)
    }

    @Test("The subscription seam (M3-B2): the glance's entitlement decides; none, or one past the offline grace, is locked")
    func accessSeam() throws {
        let items = [Self.item("noon", Self.date(6, 12))]
        let glance = Self.glance(items)
        #expect(GlanceAccess.isUnlocked(glance, at: Self.now))
        #expect(GlanceTimelinePlanner.moment(of: glance, at: Self.now, calendar: Self.calendar).content != .message(.subscriptionRequired))
        #expect(!GlanceDisplayPolicy.hidesCourseNames(glance), "the glance does not carry 'Hide course names' yet")
        let summary = try Self.summary(glance)
        #expect(!summary.hidesCourseNames)

        // No entitlement (never subscribed, lapsed, or a glance written before the field): locked.
        let unentitled = Self.glance(items, entitledUntil: nil)
        #expect(!GlanceAccess.isUnlocked(unentitled, at: Self.now))
        #expect(GlanceTimelinePlanner.moment(of: unentitled, at: Self.now, calendar: Self.calendar).content == .message(.subscriptionRequired))
        #expect(GlanceIntentAnswers.courses(.loaded(unentitled), now: Self.now).isEmpty)
        // Expired: open through the offline grace, locked from its end on (fails closed).
        let grace = SubscriptionConfig.offlineGracePeriod.timeInterval
        let expired = Self.glance(items, entitledUntil: Self.asOf)
        #expect(GlanceAccess.isUnlocked(expired, at: Self.asOf + grace - 1))
        #expect(!GlanceAccess.isUnlocked(expired, at: Self.asOf + grace))
    }

    @Test("M3-B2 O1: a timeline built before access ends gets a boundary right there, not just at the next one")
    func accessEndsIsATimelineBoundary() throws {
        // Due later than the entitlement's end, so the due-item boundary does not already cover it.
        let items = [Self.item("later", Self.date(9, 17))]
        let entitlementEndsSoon = Self.now.addingTimeInterval(3600)
        let glance = Self.glance(items, entitledUntil: entitlementEndsSoon)
        let accessEnds = try #require(EntitlementAccess.accessEnds(entitledUntil: entitlementEndsSoon))
        #expect(accessEnds > Self.now, "the fixture's offline grace must still be ahead of now")

        let plan = GlanceTimelinePlanner.plan(for: .loaded(glance), now: Self.now, calendar: Self.calendar)
        let atAccessEnd = try #require(plan.upcoming.first { $0.date == accessEnds },
                                       "no boundary at the instant access ends: \(plan.upcoming.map(\.date))")
        #expect(atAccessEnd.content == .message(.subscriptionRequired))

        // With no expiry at all, there is nothing to bound on.
        let never = Self.glance(items, entitledUntil: nil)
        let neverPlan = GlanceTimelinePlanner.plan(for: .loaded(never), now: Self.now, calendar: Self.calendar)
        #expect(EntitlementAccess.accessEnds(entitledUntil: nil) == nil)
        #expect(neverPlan.current.content == .message(.subscriptionRequired), "already locked: nothing to wait for")
    }

    // MARK: The intents' answers

    @Test("What's due next: the next three open items, then how many more and how many are overdue")
    func dueNextAnswer() throws {
        let glance = Self.glance([
            Self.item("overdue", Self.date(6, 8)), Self.item("noon", Self.date(6, 12)), Self.item("tomorrow", Self.date(7, 9)),
            Self.item("friday", Self.date(9, 17)), Self.item("november", Self.date(3, 23, month: 11)),
            Self.item("submitted", Self.date(6, 11), submitted: true),
        ])
        guard case .list(let list) = GlanceIntentAnswers.dueNext(.loaded(glance), now: Self.now, calendar: Self.calendar) else {
            Issue.record("no list")
            return
        }
        #expect(list.kind == .dueNext)
        #expect(list.items.map(\.id) == ["noon", "tomorrow", "friday"])
        #expect(list.items.map(\.day) == [.today, .tomorrow, .thisWeek])
        #expect(list.moreCount == 1)
        #expect(list.overdueCount == 1)
        #expect(!list.isStale)

        guard case .list(let one) = GlanceIntentAnswers.dueNext(.loaded(glance), now: Self.now, calendar: Self.calendar,
                                                                limit: 1) else {
            Issue.record("no list")
            return
        }
        #expect(one.items.map(\.id) == ["noon"])
        #expect(one.moreCount == 3)
    }

    @Test("What's due today: today's open items still to come; other days are not counted as more")
    func dueTodayAnswer() throws {
        let glance = Self.glance([Self.item("noon", Self.date(6, 12)), Self.item("evening", Self.date(6, 23, 59)),
                                  Self.item("tomorrow", Self.date(7, 9))])
        guard case .list(let list) = GlanceIntentAnswers.dueToday(.loaded(glance), now: Self.now, calendar: Self.calendar) else {
            Issue.record("no list")
            return
        }
        #expect(list.kind == .dueToday)
        #expect(list.items.map(\.id) == ["noon", "evening"])
        #expect(list.moreCount == 0)
        #expect(!list.moreIsLowerBound)
    }

    @Test("Answers with no glance say why, as the widgets do; the Focus filter's courses come from the glance, once each")
    func answerMessagesAndCourses() {
        let cases: [(GlanceReadResult, GlanceMessage)] = [
            (.noAccount, .signedOut), (.noGlance, .waitingForFirstSync), (.locked, .locked), (.unavailable, .unavailable),
        ]
        for (result, message) in cases {
            #expect(GlanceIntentAnswers.dueNext(result, now: Self.now, calendar: Self.calendar) == .message(message))
            #expect(GlanceIntentAnswers.dueToday(result, now: Self.now, calendar: Self.calendar) == .message(message))
            #expect(GlanceIntentAnswers.courses(result, now: Self.now).isEmpty)
        }
        let courses = [
            GlanceCourse(id: CanvasID("7"), shortCode: "BIO 101", currentGrade: nil),
            GlanceCourse(id: CanvasID("3"), shortCode: "MATH 122", currentGrade: nil),
            GlanceCourse(id: CanvasID("7"), shortCode: "BIO 101", currentGrade: nil),
        ]
        #expect(GlanceIntentAnswers.courses(.loaded(Self.glance([], courses: courses)), now: Self.now)
            == [GlanceCourseOption(id: "7", code: "BIO 101"), GlanceCourseOption(id: "3", code: "MATH 122")])
    }

    @Test("Refresh: every freshness state maps to one honest answer; no account to refresh says to open Tally")
    func refreshAnswers() {
        let saved = Self.date(6, 9)
        let cases: [(FreshnessState?, RefreshAnswer)] = [
            (nil, .openTally), (.noCache, .openTally), (.fresh(at: Self.now), .updated),
            (.refreshing(showing: saved), .stillRefreshing), (.delayed(showing: saved), .stillRefreshing),
            (.offline(showing: saved), .offline(showing: saved)), (.offline(showing: nil), .offline(showing: nil)),
            (.authExpired(showing: saved), .signInExpired),
            (.failed(.server, showing: saved), .failed(showing: saved)), (.failed(.unknown, showing: nil), .failed(showing: nil)),
        ]
        for (state, answer) in cases {
            #expect(RefreshAnswer(state: state) == answer, "\(String(describing: state))")
        }
    }
}
