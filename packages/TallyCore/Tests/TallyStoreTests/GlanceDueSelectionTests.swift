import Foundation
import Testing
import TallyTestSupport
@testable import TallyStore
@testable import TallyDomain

/// Which planner items the glance keeps (m2-widget-compliance-report OI3). Its readers are the
/// launch paint's "Due soon" (`HomeGlance`: due from now on, the dashboard's rule) and the widget
/// (open items and how many are overdue). Items that serve neither must not crowd out ones that do.
@Suite("GlanceProjectionBuilder: due-item selection for the launch paint and the widget (OI3)")
struct GlanceDueSelectionTests {
    private static let asOf = Date(timeIntervalSince1970: 1_800_000_000)

    private func item(_ id: String, hours: Double?, submitted: Bool = false, excused: Bool = false,
                      missing: Bool = false, markedComplete: Bool = false) -> PlannerItem {
        PlannerItem(id: id, courseID: nil, title: id, plannableType: "assignment",
                    dueAt: hours.map { Self.asOf.addingTimeInterval($0 * 3600) }, pointsPossible: 10,
                    submitted: submitted, graded: false, missing: missing, late: false, excused: excused,
                    markedComplete: markedComplete, htmlURL: nil)
    }

    private func snapshot(_ planner: [PlannerItem]) -> CanvasSnapshot {
        let base = CanvasSnapshotFixture.make(fetchedAt: Self.asOf, courseCount: 1, dueItemCount: 0)
        return CanvasSnapshot(generation: base.generation, accountKey: base.accountKey, host: base.host,
                              fetchedAt: base.fetchedAt, profile: base.profile, courses: base.courses, groups: base.groups,
                              gradingPeriods: base.gradingPeriods, planner: planner, events: base.events,
                              announcements: base.announcements, courseColors: base.courseColors, sections: base.sections)
    }

    private func dueIDs(_ planner: [PlannerItem]) -> [String] {
        GlanceProjectionBuilder.build(from: snapshot(planner), includeGrades: false).dueSoon.map(\.id)
    }

    /// The report's scratch case: 6 submitted and 3 missing past items used to fill all 8 slots, so
    /// "Next up" read "Nothing to do right now" while 3 items were coming up.
    @Test func pastSubmittedAndExcusedItemsNeverCrowdOutUpcomingOnes() {
        let submitted = (1...6).map { item("submitted\($0)", hours: -Double(10 * $0), submitted: true) }
        let excused = [item("excused", hours: -5, excused: true)]
        let missing = (1...3).map { item("missing\($0)", hours: -Double($0), missing: true) }
        let upcoming = (1...3).map { item("upcoming\($0)", hours: Double($0)) }

        let ids = dueIDs(submitted + excused + missing + upcoming)

        #expect(ids == ["missing3", "missing2", "missing1", "upcoming1", "upcoming2", "upcoming3"])
    }

    @Test func upcomingItemsLeaveTheReserveForOverdueWork() {
        let overdue = (1...5).map { item("overdue\($0)", hours: -Double($0), missing: true) }
        let upcoming = (1...10).map { item("upcoming\($0)", hours: Double($0)) }

        let ids = dueIDs(upcoming + overdue)

        let reserve = TallyConfig.glanceOverdueItemReserve
        let upcomingSlots = TallyConfig.glanceDueItemLimit - reserve
        // The most recent overdue items (overdue1 is the latest), then the earliest upcoming ones.
        let expected = (1...reserve).reversed().map { "overdue\($0)" } + (1...upcomingSlots).map { "upcoming\($0)" }
        #expect(ids == expected)
        #expect(upcomingSlots >= 5, "the launch paint's 5 Due soon rows (HomeGlance.dueSoonLimit) must still fit")
    }

    @Test func slotsOneGroupLeavesUnusedGoToTheOther() {
        let limit = TallyConfig.glanceDueItemLimit
        let manyOverdue = (1...(limit + 2)).map { item("overdue\($0)", hours: -Double($0), missing: true) }
        let manyUpcoming = (1...(limit + 2)).map { item("upcoming\($0)", hours: Double($0)) }

        let fewUpcoming = dueIDs(manyOverdue + [item("upcoming1", hours: 1)])
        #expect(fewUpcoming.count == limit)
        #expect(fewUpcoming.last == "upcoming1")
        #expect(fewUpcoming.filter { $0.hasPrefix("overdue") }.count == limit - 1)

        let noOverdue = dueIDs(manyUpcoming)
        #expect(noOverdue == (1...limit).map { "upcoming\($0)" })

        let undatedFill = dueIDs([item("upcoming1", hours: 1), item("undated", hours: nil)])
        #expect(undatedFill == ["upcoming1", "undated"], "undated items fill leftover slots, last")
    }

    /// The launch paint (`HomeGlance.make`) applies the dashboard's Due soon rule to the glance's
    /// items, so at the glance's own `asOf` it must find exactly the rows the full dashboard shows,
    /// however many past items the snapshot holds.
    @Test func theGlanceCarriesEveryRowTheDashboardsDueSoonShows() {
        let past = (1...6).map { item("submitted\($0)", hours: -Double($0), submitted: true) }
            + (1...4).map { item("missing\($0)", hours: -Double(20 + $0), missing: true) }
        let upcoming = (1...9).map { item("upcoming\($0)", hours: Double(12 * $0), submitted: $0 == 2) }
        let snapshot = snapshot(past + upcoming + [item("later", hours: 24 * 9)])

        let glance = GlanceProjectionBuilder.build(from: snapshot, includeGrades: false)
        let dashboard = DashboardBuilder.build(from: snapshot, digest: nil, digestAsOf: nil, now: Self.asOf)

        let horizon = Self.asOf.addingTimeInterval(7 * 24 * 3600)
        let launchPaint = glance.dueSoon
            .filter { item in item.dueAt.map { $0 >= Self.asOf && $0 <= horizon } ?? false }
            .prefix(5).map(\.id)
        #expect(!dashboard.dueSoon.isEmpty)
        #expect(Array(launchPaint) == dashboard.dueSoon.map(\.id))
    }

    @Test func theResultIsEarliestFirstWithUndatedLast() {
        let planner = [item("undated", hours: nil), item("upcoming2", hours: 2), item("overdue", hours: -1, missing: true),
                       item("upcoming1", hours: 1)]
        #expect(dueIDs(planner) == ["overdue", "upcoming1", "upcoming2", "undated"])
    }
}
