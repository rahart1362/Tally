import Foundation
import Testing
import TallyDomain
import TallyStore
import TallyTestSupport
@testable import TallySync

/// SH-3 (sync-hardening.md): `committedSnapshot` is the very value the coordinator committed (or
/// was initialised with), shared rather than re-decoded, and `shutdown()` releases it.
@Suite("RefreshCoordinator.committedSnapshot: the committed value, shared, released on shutdown (SH-3)")
struct RefreshCoordinatorSnapshotTests {
    /// Where an array keeps its elements. Arrays that share storage report the same address; a copy
    /// decoded from disk reports another. Only ever compared, never dereferenced.
    private func storage<Element>(of array: [Element]) -> UnsafeRawPointer? {
        array.withUnsafeBufferPointer { UnsafeRawPointer($0.baseAddress) }
    }

    @Test func afterACommitItIsTheCommittedValueSharedNotReDecoded() async throws {
        let gateway = ScriptedGateway()
        let (coordinator, store) = try makeCoordinator(gateway: gateway)
        #expect(await coordinator.committedSnapshot == nil, "a new account has nothing committed yet")

        _ = await coordinator.run(trigger: .manual)

        let committed = try #require(await coordinator.committedSnapshot)
        guard case .loaded(let onDisk) = await store.loadSnapshot() else { Issue.record("expected a committed snapshot"); return }
        #expect(committed == onDisk, "it is the value that was committed")
        let fetched = try #require(await gateway.returned.first)
        #expect(storage(of: committed.planner) == storage(of: fetched.planner), "it shares the fetched value's storage: never re-decoded")
        #expect(storage(of: committed.courses) == storage(of: fetched.courses))
        #expect(storage(of: onDisk.planner) != storage(of: fetched.planner), "(a decode makes a new copy, so the check above can tell)")
    }

    @Test func itStartsAsTheInitialSnapshotWithoutACopy() async throws {
        let initial = CanvasSnapshotFixture.make(generation: 7)
        let (coordinator, _) = try makeCoordinator(gateway: ScriptedGateway(), initialSnapshot: initial)

        let held = try #require(await coordinator.committedSnapshot)
        #expect(held == initial)
        #expect(storage(of: held.planner) == storage(of: initial.planner))
    }

    @Test func shutdownReleasesIt() async throws {
        let (coordinator, _) = try makeCoordinator(gateway: ScriptedGateway())
        _ = await coordinator.run(trigger: .manual)
        #expect(await coordinator.committedSnapshot != nil, "a commit keeps the committed snapshot in memory")

        await coordinator.shutdown()

        #expect(await coordinator.committedSnapshot == nil, "no decoded student data stays in memory after shutdown")
    }
}
