import Foundation
import Testing
import TallyDomain
@testable import TallyStore

/// CS-05 (crash-safety.md): "maximum items per snapshot, and snapshot size over budget: must
/// degrade gracefully, never crash." `SnapshotBudget` is a pure function, so every case here
/// is a direct, fast unit test rather than a full `RefreshCoordinator` round trip.
@Suite("SnapshotBudget: graceful degradation over the item cap (CS-05)")
struct SnapshotBudgetTests {
    private func snapshot(events: [CalendarEvent] = [], announcements: [Announcement] = [],
                         planner: [PlannerItem] = []) -> CanvasSnapshot {
        CanvasSnapshot(generation: 1, accountKey: AccountKey("t"), host: "canvas.example.edu",
                      fetchedAt: Date(timeIntervalSince1970: 1_790_600_400),
                      profile: UserProfile(id: "1", name: "S", shortName: "S", timeZone: nil, calendarFeedURL: nil),
                      courses: [], groups: [:], gradingPeriods: [:], planner: planner, events: events,
                      announcements: announcements, courseColors: [:], sections: [:])
    }

    private func event(_ i: Int) -> CalendarEvent {
        CalendarEvent(id: CanvasID("e\(i)"), courseID: nil, title: "E\(i)",
                     startAt: Date(timeIntervalSince1970: 1_790_600_400), endAt: nil, allDay: false,
                     locationName: nil, htmlURL: nil)
    }

    private func announcement(_ i: Int) -> Announcement {
        Announcement(id: CanvasID("n\(i)"), courseID: "1", title: "N\(i)", postedAt: nil, isRead: false, htmlURL: nil)
    }

    private func plannerItem(_ i: Int, dueAt: Date? = nil) -> PlannerItem {
        PlannerItem(id: "p\(i)", courseID: nil, title: "P\(i)", plannableType: "assignment",
                   dueAt: dueAt ?? Date(timeIntervalSince1970: 1_790_600_400), pointsPossible: nil,
                   submitted: false, graded: false, missing: false, late: false, excused: false,
                   markedComplete: false, htmlURL: nil)
    }

    @Test func underBudgetIsUntouched() {
        let s = snapshot(events: [event(0)], planner: [plannerItem(0)])
        let outcome = SnapshotBudget.enforce(s, maxItems: 1000)
        #expect(!outcome.degraded)
        #expect(outcome.snapshot == s)
    }

    @Test func overBudgetDropsEventsBeforeAnnouncementsOrPlanner() {
        let s = snapshot(events: (0..<5).map(event), planner: (0..<5).map { plannerItem($0) })
        let outcome = SnapshotBudget.enforce(s, maxItems: 6) // 5 planner + 5 events = 10 > 6
        #expect(outcome.degraded)
        #expect(outcome.droppedEvents == 5)
        #expect(outcome.droppedAnnouncements == 0)
        #expect(outcome.trimmedPlannerItems == 0)
        #expect(outcome.snapshot.events.isEmpty)
        #expect(outcome.snapshot.planner.count == 5, "dropping events alone was already enough")
    }

    @Test func overBudgetAfterEventsAndAnnouncementsTrimsPlannerToSoonestDue() {
        let base = Date(timeIntervalSince1970: 1_790_600_400)
        // Reverse due order: item i is due (9 - i) hours from base, so item 9 is soonest.
        let items = (0..<10).map { i in plannerItem(i, dueAt: base.addingTimeInterval(Double(9 - i) * 3600)) }
        let s = snapshot(events: [event(0)], announcements: [announcement(0)], planner: items)
        let outcome = SnapshotBudget.enforce(s, maxItems: 5)
        #expect(outcome.degraded)
        #expect(outcome.droppedEvents == 1 && outcome.droppedAnnouncements == 1)
        #expect(outcome.trimmedPlannerItems == 5)
        #expect(outcome.snapshot.planner.count == 5)
        #expect(Set(outcome.snapshot.planner.map(\.id)) == Set((5..<10).map { "p\($0)" }), "keeps the 5 soonest-due items")
    }

    @Test func neverCrashesOnAnExtremeSyntheticCount() {
        // The charter's synthetic stress persona is ~20 courses x 250 assignments; this checks
        // an order of magnitude beyond that for the planner array alone.
        let items = (0..<50_000).map { plannerItem($0) }
        let s = snapshot(planner: items)
        let outcome = SnapshotBudget.enforce(s) // default maxItems (TallyConfig.maxSnapshotItems)
        #expect(outcome.degraded)
        #expect(outcome.snapshot.planner.count == TallyConfig.maxSnapshotItems)
    }

    @Test func itemCountCountsAssignmentsInsideGroups() {
        let course = CanvasID<Course>("c1")
        let group = AssignmentGroup(id: "g1", name: "G", position: 0, weight: nil, rules: DropRules(),
                                    assignments: (0..<3).map { i in
                                        Assignment(id: CanvasID("a\(i)"), courseID: course, groupID: "g1", name: "A\(i)",
                                                  dueAt: nil, lockAt: nil, pointsPossible: nil, gradingType: .points,
                                                  omitFromFinalGrade: false, htmlURL: nil, submission: nil)
                                    })
        var s = snapshot()
        s = CanvasSnapshot(generation: s.generation, accountKey: s.accountKey, host: s.host, fetchedAt: s.fetchedAt,
                          profile: s.profile, courses: [], groups: [course: [group]], gradingPeriods: s.gradingPeriods,
                          planner: s.planner, events: s.events, announcements: s.announcements,
                          courseColors: s.courseColors, sections: s.sections)
        #expect(SnapshotBudget.itemCount(s) == 4) // 1 group + 3 assignments
    }
}
