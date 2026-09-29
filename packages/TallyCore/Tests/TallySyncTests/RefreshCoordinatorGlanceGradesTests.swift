import Foundation
import Testing
import TallyDomain
import TallyStore
import TallyTestSupport
@testable import TallySync

/// `RefreshCoordinator.updateIncludeGrades`: "Show Grades in Widgets" reaches the glance on disk at
/// once and every later commit (M3-A O11, PMO R10).
@Suite("RefreshCoordinator.updateIncludeGrades: the widget's grades follow the setting now",
       .timeLimit(.minutes(TestTimeBudget.minutes(1))))
struct RefreshCoordinatorGlanceGradesTests {
    private static func hasGrades(_ glance: GlanceProjection) -> Bool {
        glance.overallGradeBand != nil || glance.courses.contains { $0.currentGrade != nil }
    }

    private func glance(_ store: SnapshotStore) async -> GlanceProjection? {
        guard case .loaded(let glance) = await store.loadGlance() else { return nil }
        return glance
    }

    @Test func turningGradesOffRewritesTheGlanceNowAndLaterCommitsFollow() async throws {
        let (coordinator, store) = try makeCoordinator(gateway: ScriptedGateway(), includeGrades: true)
        _ = await coordinator.run(trigger: .manual)
        #expect(await glance(store).map(Self.hasGrades) == true, "committed with grades opted in")

        #expect(await coordinator.updateIncludeGrades(false), "the glance was rewritten")
        #expect(await glance(store).map(Self.hasGrades) == false, "no grades on disk, before any refresh")
        #expect(await coordinator.includeGrades == false)

        _ = await coordinator.run(trigger: .manual)
        let next = await glance(store)
        #expect(next?.generation == 2)
        #expect(next.map(Self.hasGrades) == false, "the next commit keeps them out")

        #expect(await coordinator.updateIncludeGrades(true))
        #expect(await glance(store).map(Self.hasGrades) == true, "turning them back on shows them now too")
    }

    @Test func anUnchangedValueOrNothingCommittedWritesNothing() async throws {
        let (coordinator, store) = try makeCoordinator(gateway: ScriptedGateway(), includeGrades: false)
        #expect(await coordinator.updateIncludeGrades(false) == false, "no change")
        #expect(await coordinator.updateIncludeGrades(true) == false, "nothing committed yet: nothing to rewrite")
        #expect(await store.loadGlance() == .absent)

        _ = await coordinator.run(trigger: .manual)
        #expect(await glance(store).map(Self.hasGrades) == true, "the first commit uses the value set before it")
    }
}
