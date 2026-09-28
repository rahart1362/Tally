import Foundation
import Testing
import TallyDomain
import TallyStore
import TallyTestSupport
@testable import TallySync

/// SH-1 (sync-hardening.md): `events()` gives every subscriber its own bounded stream that starts
/// with the current state; `onTermination` removes only its own subscriber; `shutdown()` retires
/// the coordinator (finishes every stream, refuses new runs and new subscribers, discards the run
/// in flight, releases the decoded snapshot); and no stream keeps the coordinator alive.
@Suite("RefreshCoordinator.events(): per-subscriber streams and shutdown (SH-1)")
struct RefreshCoordinatorEventsTests {
    private typealias Event = RefreshCoordinator.Event

    /// Everything a subscriber that joined before one successful first run sees, in order.
    private func firstRunEvents(at now: Date) -> [Event] {
        [.stateChanged(.noCache), .stateChanged(.refreshing(showing: nil)),
         .committed(generation: 1, digest: .empty), .stateChanged(.fresh(at: now))]
    }

    @Test func twoSubscribersEachReceiveEveryEvent() async throws {
        let clock = TestClock()
        let (coordinator, _) = try makeCoordinator(gateway: ScriptedGateway(), clock: clock)
        let first = await coordinator.events()
        let second = await coordinator.events()
        let firstConsumer = Task { await drain(first) }
        let secondConsumer = Task { await drain(second) }

        _ = await coordinator.run(trigger: .manual)
        await coordinator.shutdown()

        let expected = firstRunEvents(at: clock.now())
        #expect(await finished(firstConsumer) == expected)
        #expect(await finished(secondConsumer) == expected, "a second subscriber gets every event too, not a share of them")
    }

    @Test func cancellingOneSubscriberLeavesTheOtherUntouched() async throws {
        let clock = TestClock()
        let (coordinator, _) = try makeCoordinator(gateway: ScriptedGateway(), clock: clock)
        let cancelled = await coordinator.events()
        let kept = await coordinator.events()
        #expect(await coordinator.subscriberCount == 2)
        let cancelledConsumer = Task { await drain(cancelled) }
        let keptConsumer = Task { await drain(kept) }

        cancelledConsumer.cancel()
        _ = await cancelledConsumer.value
        // `onTermination` hops back onto the coordinator to remove exactly that one subscriber.
        #expect(await eventually { await coordinator.subscriberCount == 1 }, "only the cancelled subscriber is removed")

        _ = await coordinator.run(trigger: .manual)
        await coordinator.shutdown()
        #expect(await finished(keptConsumer) == firstRunEvents(at: clock.now()), "the other subscriber still sees every event")
    }

    @Test func aSubscriberThatNeverReadsHoldsAtMostTheBufferLimit() async throws {
        let (coordinator, _) = try makeCoordinator(gateway: ScriptedGateway())
        let late = await coordinator.events() // subscribed, but nobody reads it until the end
        let emitted = 10_000
        for generation in 1...emitted {
            await coordinator.emit(.committed(generation: UInt64(generation), digest: .empty))
        }
        await coordinator.shutdown()

        let limit = TallyConfig.refreshEventBufferLimit
        let newest = ((emitted - limit + 1)...emitted).map { Event.committed(generation: UInt64($0), digest: .empty) }
        let received = await finished(Task { await drain(late) })
        #expect(received?.count == limit, "at most the buffer limit, not all \(emitted + 1) events")
        #expect(received == newest, "and it is the newest ones that are kept")
    }

    @Test func shutdownFinishesEverySubscribersStream() async throws {
        let (coordinator, _) = try makeCoordinator(gateway: ScriptedGateway())
        var consumers: [Task<[Event], Never>] = []
        for _ in 0..<3 {
            let stream = await coordinator.events()
            consumers.append(Task { await drain(stream) })
        }

        await coordinator.shutdown()

        for consumer in consumers {
            #expect(await finished(consumer) == [.stateChanged(.noCache)], "each for-await loop ends on its own")
        }
        #expect(await coordinator.subscriberCount == 0)
    }

    @Test func eventsAfterShutdownIsAlreadyFinished() async throws {
        let (coordinator, _) = try makeCoordinator(gateway: ScriptedGateway())
        await coordinator.shutdown()

        let stream = await coordinator.events()
        #expect(await finished(Task { await drain(stream) }) == [], "finished at once: no initial state, no events")
        #expect(await coordinator.subscriberCount == 0)
    }

    /// The crash-safety charter's weak-reference check, with subscribers attached: one active
    /// subscriber is cancelled and another still holds its stream when the owner lets go.
    @Test func coordinatorDeallocatesWithSubscribersAttachedAndTheirStreamsEnd() async throws {
        weak var weakCoordinator: RefreshCoordinator?
        let cancelledInbox = EventInbox(), heldInbox = EventInbox()
        let heldConsumer: Task<[Event], Never>
        do {
            let (coordinator, _) = try makeCoordinator(gateway: ScriptedGateway())
            weakCoordinator = coordinator
            _ = await coordinator.run(trigger: .manual)
            let cancelled = await coordinator.events()
            let held = await coordinator.events()
            let cancelledConsumer = Task { await drain(cancelled, into: cancelledInbox) }
            heldConsumer = Task { await drain(held, into: heldInbox) }
            // Both consumers are genuinely active: each has already read its initial state.
            #expect(await eventually {
                let cancelledIsReading = await !cancelledInbox.events.isEmpty
                let heldIsReading = await !heldInbox.events.isEmpty
                return cancelledIsReading && heldIsReading
            })
            cancelledConsumer.cancel()
            _ = await cancelledConsumer.value
        }
        // `heldConsumer` is still suspended in `for await` on its stream. Neither that stream nor the
        // cancelled subscriber's termination handler may keep the coordinator alive. Polled, not
        // read once: the handler's hop task holds a strong temporary for the instant it runs.
        #expect(await eventually { weakCoordinator == nil }, "RefreshCoordinator must deallocate once its owner releases it")
        // Released without `shutdown()`: its deinit still finishes the remaining subscriber's stream.
        #expect(await finished(heldConsumer) != nil, "a subscriber's loop must not outlive the coordinator")
    }

    @Test func aShutDownCoordinatorNeverFetchesAgain() async throws {
        let gateway = ScriptedGateway()
        let (coordinator, store) = try makeCoordinator(gateway: gateway)
        await coordinator.shutdown()

        #expect(await coordinator.run(trigger: .manual) == .noCache)
        #expect(await gateway.calls == 0, "a retired coordinator must never fetch")
        #expect(await store.loadSnapshot() == .absent, "nor re-create a store that sign-out has purged")
    }

    @Test func shutdownMidFlightCancelsTheFetchAndDiscardsTheLateResult() async throws {
        let gateway = ScriptedGateway(holdUntilReleased: true)
        let (coordinator, store) = try makeCoordinator(gateway: gateway)
        let caller = Task { await coordinator.run(trigger: .manual) }
        #expect(await eventually { await gateway.calls == 1 }, "the fetch is under way")

        await coordinator.shutdown()

        #expect(await eventually { await gateway.cancellationsSeen == 1 }, "shutdown cancels the fetch in flight")
        await gateway.release() // had the cancel not landed, the fetch now finishes, so a regression fails below instead of hanging
        #expect(await finished(caller) == .noCache)
        #expect(await coordinator.currentState == .noCache, "the in-flight mark is dropped, not left refreshing forever")
        #expect(await store.loadSnapshot() == .absent, "the late result is never committed")
        #expect(await coordinator.committedSnapshot == nil)
    }
    // That shutdown releases the committed snapshot is SH-3's `RefreshCoordinatorSnapshotTests.shutdownReleasesIt`.
}
