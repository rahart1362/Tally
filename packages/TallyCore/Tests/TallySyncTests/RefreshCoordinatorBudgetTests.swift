import Foundation
import Testing
import TallyDomain
import TallyStore
import TallyTestSupport
@testable import TallySync

/// SH-5 (sync-hardening.md): `SnapshotBudget` (CS-05) is tested as a pure function in
/// `SnapshotBudgetTests`; this pins its wiring, i.e. that `RefreshCoordinator.finish` applies it to
/// the fetched snapshot before `SnapshotStore.commit`, so what reaches the disk and
/// `committedSnapshot` is the budgeted snapshot, not the raw fetch.
@Suite("RefreshCoordinator applies SnapshotBudget before committing (SH-5)", .timeLimit(.minutes(TestTimeBudget.minutes(1))))
struct RefreshCoordinatorBudgetTests {
    /// The small fixture plus `TallyConfig.maxSnapshotItems` calendar events: over the item budget
    /// by the fixture's own items, so `SnapshotBudget` must drop the events before it may be stored.
    private static let overBudget: ScriptedGateway.SnapshotFactory = { previous, now in
        let base = ScriptedGateway.fixture(previous, now)
        let events = (0..<TallyConfig.maxSnapshotItems).map { index in
            CalendarEvent(id: CanvasID("e\(index)"), courseID: nil, title: "E\(index)", startAt: now, endAt: nil,
                          allDay: false, locationName: nil, htmlURL: nil)
        }
        return CanvasSnapshot(generation: base.generation, accountKey: base.accountKey, host: base.host,
                              fetchedAt: base.fetchedAt, profile: base.profile, courses: base.courses, groups: base.groups,
                              gradingPeriods: base.gradingPeriods, planner: base.planner, events: events,
                              announcements: base.announcements, courseColors: base.courseColors, sections: base.sections)
    }

    @Test func anOverBudgetFetchIsTrimmedBeforeItIsCommitted() async throws {
        let gateway = ScriptedGateway(makeSnapshot: Self.overBudget)
        let (coordinator, store) = try makeCoordinator(gateway: gateway)

        _ = await coordinator.run(trigger: .manual)

        let fetched = try #require(await gateway.returned.first)
        #expect(SnapshotBudget.itemCount(fetched) > TallyConfig.maxSnapshotItems, "the gateway really did return an over-budget snapshot")
        // The fetch is generation 1, which is also the coordinator's first attempt, so re-stamping
        // changes nothing and the expected commit is exactly the budgeted fetch.
        let budgeted = SnapshotBudget.enforce(fetched).snapshot
        #expect(budgeted.events.isEmpty)
        #expect(SnapshotBudget.itemCount(budgeted) <= TallyConfig.maxSnapshotItems)
        guard case .loaded(let onDisk) = await store.loadSnapshot() else { Issue.record("expected a committed snapshot"); return }
        #expect(onDisk == budgeted, "the store received the budgeted snapshot, not the raw fetch")
        #expect(onDisk.events.isEmpty)
        #expect(await coordinator.committedSnapshot == budgeted)
    }
}
