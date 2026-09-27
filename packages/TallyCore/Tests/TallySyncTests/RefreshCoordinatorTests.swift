import Foundation
import Synchronization
import Testing
import TallyCanvasAPI
import TallyDomain
import TallyStore
import TallyTestSupport
@testable import TallySync

/// WP-D01 (architecture.md §3.4): single-flight, generation/epoch guards, the 10 s "delayed"
/// signal, partial-failure and 401 handling. Timing assertions use real (short) `Duration`
/// budgets injected into the coordinator, the same way `CanvasGatewayTests` speeds up
/// `BackoffPolicy`; `TestClock` supplies the domain-facing "now" that ends up in `RefreshRecord`.
@Suite("RefreshCoordinator: single-flight, generations, epochs, and failure handling")
struct RefreshCoordinatorTests {
    private let host = "canvas.northfield.example"
    private let userID = "4820117"

    /// Always fails: safe as the default refresher, since a successful run never needs one
    /// (the seeded credential's access token is valid for the whole test).
    private struct AlwaysInvalidGrantRefresher: TokenRefreshing {
        func refresh(_ credential: CanvasCredential) async throws -> CanvasCredential { throw TokenEndpointError.invalidGrant }
    }

    /// Records `RefreshCoordinator.Event`s from a background consumer task; a plain `var` would
    /// be a data race once a `Task {}` closure mutates it concurrently with the test body reading it.
    private final class EventLog: Sendable {
        private let state = Mutex<[RefreshCoordinator.Event]>([])
        func append(_ event: RefreshCoordinator.Event) { state.withLock { $0.append(event) } }
        var all: [RefreshCoordinator.Event] { state.withLock { $0 } }
    }

    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tally-sync-\(UUID().uuidString)")
        try ProtectedFile.prepareDirectory(url, excludeFromBackup: true)
        return url
    }

    private func makeSealer(accountKey: AccountKey) -> VaultSealer {
        VaultSealer(account: accountKey.rawValue, keyring: VaultKeyring(store: InMemoryVaultKeyStore()), mayCreateKeys: true)
    }

    private func makeGateway(transport: ReplayTransport, accountKey: AccountKey, clock: TestClock,
                             refresher: any TokenRefreshing = AlwaysInvalidGrantRefresher()) -> LiveCanvasGateway {
        let credential = CanvasCredential(host: host, userID: userID, accessToken: "token-1", refreshToken: "refresh-1",
                                          accessTokenExpiresAt: clock.now().addingTimeInterval(3600))
        let tokens = TokenCoordinator(initial: credential, store: InMemoryCredentialStore(credential), refresher: refresher, clock: clock)
        let client = CanvasClient(host: host, transport: transport, tokens: tokens,
                                  backoff: BackoffPolicy(base: .milliseconds(1), maxDelay: .milliseconds(5)))
        return LiveCanvasGateway(host: host, accountKey: accountKey, client: client)
    }

    /// Every helper below shares one recipe: a fresh temp-directory `SnapshotStore`, a
    /// `LiveCanvasGateway` over `ReplayTransport.persona("flagship")`, and a coordinator over both.
    /// `AccountKey.derive` (TallyStore) is used here exactly as the composition root would.
    private func makeHarness(
        clock: TestClock = TestClock(), refresher: any TokenRefreshing = AlwaysInvalidGrantRefresher(),
        liveRefreshBudget: Duration = TallyConfig.liveRefreshBudget,
        foregroundHardCeiling: Duration = TallyConfig.foregroundHardCeiling,
        backgroundBudget: Duration = TallyConfig.backgroundBudget
    ) throws -> (coordinator: RefreshCoordinator, store: SnapshotStore, transport: ReplayTransport, accountKey: AccountKey) {
        let accountKey = AccountKey.derive(host: host, userID: userID)
        let store = SnapshotStore(root: try tempDirectory(), accountKey: accountKey, sealer: makeSealer(accountKey: accountKey))
        let transport = try ReplayTransport.persona("flagship")
        let gateway = makeGateway(transport: transport, accountKey: accountKey, clock: clock, refresher: refresher)
        let coordinator = RefreshCoordinator(gateway: gateway, store: store, clock: clock, initialSnapshot: nil,
                                             liveRefreshBudget: liveRefreshBudget, foregroundHardCeiling: foregroundHardCeiling,
                                             backgroundBudget: backgroundBudget)
        return (coordinator, store, transport, accountKey)
    }

    // MARK: - Single-flight

    @Test func concurrentTriggersProduceExactlyOneFetch() async throws {
        let harness = try makeHarness()

        let finalStates = await withTaskGroup(of: FreshnessState.self) { group in
            for trigger in [RefreshTrigger.launch, .foreground, .manual, .intent, .manual] {
                group.addTask { await harness.coordinator.run(trigger: trigger) }
            }
            return await group.reduce(into: [FreshnessState]()) { $0.append($1) }
        }

        #expect(finalStates.count == 5)
        for state in finalStates {
            guard case .fresh = state else { Issue.record("expected every joiner to observe fresh, got \(state)"); return }
        }
        #expect(await harness.transport.requestCount == 13, "one fetch's worth of requests, matching the flagship fixture's own declared count")
        guard case .loaded(let snapshot) = await harness.store.loadSnapshot() else {
            Issue.record("expected exactly one committed snapshot"); return
        }
        #expect(snapshot.generation == 1)
    }

    // MARK: - The 10 s (here, scaled-down) delayed signal

    @Test func aSlowFetchIsSignalledDelayedThenLandsFresh() async throws {
        let harness = try makeHarness(liveRefreshBudget: .milliseconds(30), foregroundHardCeiling: .milliseconds(600),
                                      backgroundBudget: .milliseconds(600))
        await harness.transport.inject(latency: .milliseconds(90), times: 1, matching: { $0.url.path == "/api/v1/users/self/profile" })

        let log = EventLog()
        let stream = await harness.coordinator.events()
        let consumer = Task { for await event in stream { log.append(event) } }

        let final = await harness.coordinator.run(trigger: .manual)
        try await Task.sleep(for: .milliseconds(50)) // let the consumer drain what was already yielded
        consumer.cancel()

        guard case .fresh = final else { Issue.record("expected fresh once the slow fetch lands, got \(final)"); return }
        let states = log.all.compactMap { event -> FreshnessState? in
            guard case .stateChanged(let state) = event else { return nil }
            return state
        }
        #expect(states.contains { if case .delayed = $0 { true } else { false } }, "must pass through delayed before landing")
        guard case .fresh = states.last else { Issue.record("expected the last published state to be fresh, got \(String(describing: states.last))"); return }
        #expect(log.all.contains { if case .committed = $0 { true } else { false } })
    }

    // MARK: - Generation guard: an old slow run cannot overwrite a newer one

    @Test func anOldSlowRunCannotOverwriteANewerOne() async throws {
        let harness = try makeHarness()

        let first = await harness.coordinator.run(trigger: .manual)
        guard case .fresh = first else { Issue.record("expected fresh after the first run, got \(first)"); return }
        guard case .loaded(let firstSnapshot) = await harness.store.loadSnapshot() else {
            Issue.record("expected a committed first snapshot"); return
        }
        #expect(firstSnapshot.generation == 1)

        // Simulate a newer commit landing out of band (e.g. a different device or refresh path
        // writing the same account's store) while this coordinator still thinks generation 1 is
        // the latest it knows about.
        let outOfBand = CanvasSnapshot(
            generation: 5, accountKey: firstSnapshot.accountKey, host: firstSnapshot.host,
            fetchedAt: firstSnapshot.fetchedAt.addingTimeInterval(3600), profile: firstSnapshot.profile,
            courses: firstSnapshot.courses, groups: firstSnapshot.groups, gradingPeriods: firstSnapshot.gradingPeriods,
            planner: firstSnapshot.planner, events: firstSnapshot.events, announcements: firstSnapshot.announcements,
            courseColors: firstSnapshot.courseColors, sections: firstSnapshot.sections)
        try await harness.store.commit(outOfBand, includeGrades: false)

        // This run assigns itself generation 2 (its own committedGeneration + 1); it must lose to
        // the store's already-newer generation 5.
        let second = await harness.coordinator.run(trigger: .manual)
        guard case .fresh = second else { Issue.record("expected fresh (adopting the newer generation), got \(second)"); return }

        guard case .loaded(let onDisk) = await harness.store.loadSnapshot() else {
            Issue.record("expected the out-of-band snapshot to still be there"); return
        }
        #expect(onDisk.generation == 5, "the older, slower run must never overwrite the newer one already committed")
        #expect(onDisk == outOfBand)
    }

    // MARK: - Epoch guard: sign-out mid-flight discards the result

    @Test func signOutMidFlightDiscardsTheResult() async throws {
        let harness = try makeHarness(liveRefreshBudget: .seconds(5), foregroundHardCeiling: .seconds(10), backgroundBudget: .seconds(10))
        await harness.transport.inject(latency: .milliseconds(150), times: 1, matching: { $0.url.path == "/api/v1/users/self/profile" })

        let runTask = Task { await harness.coordinator.run(trigger: .manual) }
        try await Task.sleep(for: .milliseconds(20)) // let the fetch actually start before signing out
        await harness.coordinator.bumpEpochAndCancel()
        _ = await runTask.value

        let finalState = await harness.coordinator.currentState
        guard case .noCache = finalState else { Issue.record("expected .noCache after a discarded sign-out, got \(finalState)"); return }
        guard case .absent = await harness.store.loadSnapshot() else { Issue.record("expected nothing was ever committed"); return }
    }

    // MARK: - A required-section failure keeps the old snapshot

    @Test func requiredSectionFailureKeepsTheOldSnapshot() async throws {
        let harness = try makeHarness()

        let first = await harness.coordinator.run(trigger: .manual)
        guard case .fresh = first else { Issue.record("expected fresh after the first run, got \(first)"); return }
        guard case .loaded(let firstSnapshot) = await harness.store.loadSnapshot() else {
            Issue.record("expected a committed first snapshot"); return
        }

        await harness.transport.inject(response: try ReplayTransport.errorResponse("500-internal-server-error"), times: 3,
                                       matching: { $0.url.path == "/api/v1/users/self/profile" })
        let second = await harness.coordinator.run(trigger: .manual)
        guard case .failed(let failure, _) = second else { Issue.record("expected .failed, got \(second)"); return }
        #expect(failure == .server)

        guard case .loaded(let stillFirst) = await harness.store.loadSnapshot() else {
            Issue.record("expected the original snapshot to survive"); return
        }
        #expect(stillFirst == firstSnapshot, "the cache must never be touched on a required-section failure")
    }

    // MARK: - A 401 leads to reauth, and the cache is kept

    @Test func a401LeadsToReauthAndTheCacheIsKept() async throws {
        let harness = try makeHarness()

        let first = await harness.coordinator.run(trigger: .manual)
        guard case .fresh = first else { Issue.record("expected fresh after the first run, got \(first)"); return }
        guard case .loaded(let firstSnapshot) = await harness.store.loadSnapshot() else {
            Issue.record("expected a committed first snapshot"); return
        }

        await harness.transport.inject(response: try ReplayTransport.errorResponse("401-invalid-access-token"), times: 1,
                                       matching: { $0.url.path == "/api/v1/users/self/profile" })
        let second = await harness.coordinator.run(trigger: .manual)
        guard case .authExpired = second else { Issue.record("expected .authExpired, got \(second)"); return }

        guard case .loaded(let stillFirst) = await harness.store.loadSnapshot() else {
            Issue.record("expected the original snapshot to survive"); return
        }
        #expect(stillFirst == firstSnapshot, "the cache must never be touched when reauth is required")
    }

    // MARK: - CS-05: sign-out finishes `events()`, so a consumer's `for await` loop always ends

    /// Before the fix, `bumpEpochAndCancel()` never finished the event stream: a consumer
    /// iterating it with `for await` (e.g. `RefreshStatusModel`, if it ever forgot to separately
    /// call its own `detach()`) would suspend forever waiting for a next event that was never
    /// coming — leaking the task and everything its closure captured (the coordinator itself, its
    /// gateway, its store). This proves the stream now finishes (via `shutdown()`, SH-1), with
    /// `.noCache` as the last thing the subscriber sees.
    @Test func bumpEpochAndCancelFinishesTheEventStream() async throws {
        let harness = try makeHarness()
        let stream = await harness.coordinator.events()
        let consumer = Task { await drain(stream) } // only returns once the stream finishes

        await harness.coordinator.bumpEpochAndCancel()

        // `finished` cancels the consumer after 2 s, so a regression fails here instead of hanging.
        let seen = await finished(consumer, within: .seconds(2))
        #expect(seen != nil, "the consumer's for-await loop must end on its own within 2s, not hang forever")
        #expect(seen?.last == .stateChanged(.noCache))
    }

    /// CS-05 leak check: nothing outside the coordinator keeps it alive once the caller's own
    /// reference is dropped (weak-reference test, per the crash-safety charter).
    @Test func coordinatorDeallocatesAfterUse() async throws {
        weak var weakCoordinator: RefreshCoordinator?
        do {
            let harness = try makeHarness()
            weakCoordinator = harness.coordinator
            _ = await harness.coordinator.run(trigger: .manual)
            await harness.coordinator.bumpEpochAndCancel()
        }
        #expect(weakCoordinator == nil, "RefreshCoordinator must not leak once its own owner releases it")
    }
}
