import Foundation
import Testing
import TallyDomain
import TallyStore
import TallyTestSupport
@testable import TallySync

/// SH-2 (sync-hardening.md): a caller's cancellation reaches the run it waits on. The run's fetch
/// is cancelled only once every caller waiting on it has been cancelled; a run still shared with a
/// waiting caller keeps going; a cancelled caller stops waiting at once; and an abandoned run's
/// outcome is discarded rather than recorded as a failure.
@Suite("RefreshCoordinator.run: caller cancellation reaches the fetch (SH-2)", .timeLimit(.minutes(TestTimeBudget.minutes(1))))
struct RefreshCoordinatorCancellationTests {
    private typealias Event = RefreshCoordinator.Event

    /// Far below the 60 s ceiling a missed cancellation would run to, and loose enough for TSan.
    private let promptly: Duration = .seconds(1)

    @Test func aCancelledSoleCallerCancelsTheFetchPromptlyAndTheOutcomeIsDiscarded() async throws {
        let gateway = ScriptedGateway(holdUntilReleased: true)
        let (coordinator, store) = try makeCoordinator(gateway: gateway)
        let subscriber = await coordinator.events()
        let consumer = Task { await drain(subscriber) }
        let caller = Task { await coordinator.run(trigger: .manual) }
        #expect(await eventually { await gateway.calls == 1 }, "the fetch is under way")

        let cancelledAt = ContinuousClock.now
        caller.cancel()

        #expect(await finished(caller, within: promptly, unblocking: { await gateway.release() }) != nil,
                "the cancelled caller stops waiting at once")
        #expect(await eventually(within: promptly) { await gateway.cancellationsSeen == 1 }, "the gateway sees the cancellation")
        if let seenAt = await gateway.lastCancellationSeenAt {
            #expect(seenAt - cancelledAt < promptly, "within a small bound, not at the 60 s ceiling")
        }
        await gateway.release() // had the cancellation not landed, a regression now fails below instead of hanging

        // Discarded, not recorded as a failure: the state reverts to what it was before the run.
        #expect(await eventually { await coordinator.currentState == .noCache })
        #expect(await store.loadSnapshot() == .absent, "nothing is committed")
        await coordinator.shutdown()
        #expect(await finished(consumer) == [.stateChanged(.noCache), .stateChanged(.refreshing(showing: nil)), .stateChanged(.noCache)])
    }

    @Test func cancellingOneOfTwoJoinersLeavesTheFetchRunningForTheOther() async throws {
        let clock = TestClock()
        let gateway = ScriptedGateway(holdUntilReleased: true)
        let (coordinator, store) = try makeCoordinator(gateway: gateway, clock: clock)
        let leaving = Task { await coordinator.run(trigger: .manual) }
        #expect(await eventually { await gateway.calls == 1 })
        let staying = Task { await coordinator.run(trigger: .intent) } // joins the run in flight
        #expect(await eventually { await coordinator.waiterCount == 2 }, "both callers wait on the one run")

        leaving.cancel()

        #expect(await finished(leaving, within: promptly, unblocking: { await gateway.release() }) != nil,
                "the cancelled joiner stops waiting at once, while the fetch is still held")
        #expect(await coordinator.waiterCount == 1)
        await gateway.release()
        #expect(await finished(staying) == .fresh(at: clock.now()), "the fetch completes for the caller still waiting")
        #expect(await gateway.cancellationsSeen == 0, "the fetch was still wanted, so it was never cancelled")
        #expect(await gateway.calls == 1, "one fetch served both callers (single-flight)")
        guard case .loaded(let committed) = await store.loadSnapshot() else {
            Issue.record("expected the shared run's snapshot to be committed"); return
        }
        #expect(committed.generation == 1)
    }

    @Test func anAlreadyCancelledCallerNeitherStartsNorJoinsARun() async throws {
        let gateway = ScriptedGateway()
        let (coordinator, store) = try makeCoordinator(gateway: gateway)
        let subscriber = await coordinator.events()
        let consumer = Task { await drain(subscriber) }
        let caller = Task { () -> FreshnessState in
            withUnsafeCurrentTask { $0?.cancel() } // cancelled before it ever calls `run`
            return await coordinator.run(trigger: .manual)
        }

        #expect(await finished(caller) == .noCache)
        #expect(await gateway.calls == 0, "no fetch for a caller nobody is waiting on")
        #expect(await store.loadSnapshot() == .absent)
        await coordinator.shutdown()
        #expect(await finished(consumer) == [.stateChanged(.noCache)], "and no .refreshing was ever published")
    }

    @Test func aCallerArrivingWhileAnAbandonedRunWindsDownGetsARunOfItsOwn() async throws {
        let clock = TestClock()
        // Notices the cancellation but keeps holding, so the abandoned run is still winding down.
        let gateway = ScriptedGateway(holdUntilReleased: true, honorsCancellation: false)
        let (coordinator, store) = try makeCoordinator(gateway: gateway, clock: clock)
        let subscriber = await coordinator.events()
        let consumer = Task { await drain(subscriber) }
        let leaving = Task { await coordinator.run(trigger: .manual) }
        #expect(await eventually { await gateway.calls == 1 })
        leaving.cancel()
        #expect(await finished(leaving, within: promptly, unblocking: { await gateway.release() }) != nil)
        #expect(await eventually { await gateway.cancellationsSeen == 1 }, "the run was abandoned and its fetch cancelled")

        let late = Task { await coordinator.run(trigger: .manual) }
        #expect(await eventually { await coordinator.waiterCount == 1 }, "the late caller waits the abandoned run out")
        await gateway.release() // the abandoned fetch now returns a snapshot anyway; it must be discarded

        #expect(await finished(late) == .fresh(at: clock.now()))
        #expect(await gateway.calls == 2, "the late caller got a fetch of its own, not the abandoned run's discarded outcome")
        await coordinator.shutdown()
        let commits = await finished(consumer)?.filter { event in
            if case .committed = event { true } else { false }
        }
        #expect(commits == [.committed(generation: 1, digest: .empty)], "only the late caller's run committed")
        guard case .loaded(let onDisk) = await store.loadSnapshot() else {
            Issue.record("expected the late caller's snapshot to be committed"); return
        }
        #expect(onDisk.generation == 1)
    }
}
