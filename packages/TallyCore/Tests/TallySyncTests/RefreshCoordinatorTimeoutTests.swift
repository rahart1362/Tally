import Foundation
import Testing
import TallyDomain
import TallyStore
import TallyTestSupport
@testable import TallySync

/// O9 (m2-lifecycle-report §8): a fetch that never ends. The run must still signal `.delayed` at
/// `liveRefreshBudget`, cancel the fetch once the ceiling elapses, and then finish on its own. The
/// old `withTaskGroup` race did neither: the group waited on its `task.value` child, which cannot be
/// cancelled, so the run hung until the fetch ended some other way. A slow fetch that does finish
/// is covered by `RefreshCoordinatorTests.aSlowFetchIsSignalledDelayedThenLandsFresh`.
@Suite("RefreshCoordinator: a fetch that never ends is delayed, then cancelled at the ceiling (O9)",
       .timeLimit(.minutes(TestTimeBudget.minutes(1))))
struct RefreshCoordinatorTimeoutTests {
    private let budget: Duration = .milliseconds(50)
    private let ceiling: Duration = .milliseconds(400)

    @Test func aFetchThatNeverEndsIsSignalledDelayedThenCancelledAtTheCeiling() async throws {
        // Nothing in the test releases the gateway; only `finished`'s watchdog does, on a regression.
        let gateway = ScriptedGateway(holdUntilReleased: true)
        let (coordinator, store) = try makeCoordinator(gateway: gateway, liveRefreshBudget: budget, ceiling: ceiling)
        let inbox = EventInbox()
        let subscriber = await coordinator.events()
        let consumer = Task { await drain(subscriber, into: inbox) }
        defer { consumer.cancel() }

        let startedAt = ContinuousClock.now
        let caller = Task { await coordinator.run(trigger: .manual) }

        let final = await finished(caller, unblocking: { await gateway.release() })
        #expect(final != nil, "the run ends on its own: the ceiling cancelled the fetch")
        #expect(await gateway.cancellationsSeen == 1, "the fetch saw exactly one cancellation")
        if let seenAt = await gateway.lastCancellationSeenAt {
            #expect(seenAt - startedAt >= ceiling, "cancelled at the ceiling, not at the budget")
        }

        let states = await statesOnceSettled(inbox)
        let delayedAt = states.firstIndex { if case .delayed = $0 { true } else { false } }
        #expect(delayedAt != nil, "the budget elapsed while the fetch was held, so .delayed was published")
        if let delayedAt, let final {
            #expect(delayedAt < states.count - 1, ".delayed came before the run's final state")
            #expect(states.last == final)
        }
        if case .delayed = final { Issue.record("the run must leave .delayed once the fetch is cancelled") }
        if case .refreshing = final { Issue.record("the run must leave .refreshing once the fetch is cancelled") }
        #expect(await store.loadSnapshot() == .absent, "nothing is committed")
    }

    /// The published states, read once the inbox has held the same number of events for a short
    /// while (the consumer drains asynchronously after `run` returns).
    private func statesOnceSettled(_ inbox: EventInbox) async -> [FreshnessState] {
        var count = -1
        _ = await eventually {
            let now = await inbox.events.count
            defer { count = now }
            try? await Task.sleep(for: .milliseconds(20))
            return now == count && now > 0
        }
        return await inbox.events.compactMap { event -> FreshnessState? in
            guard case .stateChanged(let state) = event else { return nil }
            return state
        }
    }
}
