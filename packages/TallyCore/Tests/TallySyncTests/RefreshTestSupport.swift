import Foundation
import TallyCanvasAPI
import TallyDomain
import TallyStore
import TallyTestSupport
@testable import TallySync

/// A scripted `CanvasGateway` for the sync-hardening tests (the same seam `SignOutUseCaseTests`'
/// `StubGateway` uses, with a few more knobs). It counts calls, can hold every fetch until the
/// test releases it, records when a held fetch observed cancellation, and keeps what it returned.
actor ScriptedGateway: CanvasGateway {
    typealias SnapshotFactory = @Sendable (_ previous: CanvasSnapshot?, _ now: Date) -> CanvasSnapshot

    /// The small hand-built fixture, one generation past `previous`.
    static let fixture: SnapshotFactory = { previous, now in
        CanvasSnapshotFixture.make(generation: (previous?.generation ?? 0) + 1, fetchedAt: now)
    }

    private let makeSnapshot: SnapshotFactory
    private let honorsCancellation: Bool
    private var isHeld: Bool
    private(set) var calls = 0
    private(set) var cancellationsSeen = 0
    private(set) var lastCancellationSeenAt: ContinuousClock.Instant?
    private(set) var returned: [CanvasSnapshot] = []

    /// `honorsCancellation: false` notes a cancellation but keeps holding until `release()`, like
    /// a network call that is slow to wind down.
    init(holdUntilReleased: Bool = false, honorsCancellation: Bool = true,
         makeSnapshot: @escaping SnapshotFactory = ScriptedGateway.fixture) {
        isHeld = holdUntilReleased
        self.honorsCancellation = honorsCancellation
        self.makeSnapshot = makeSnapshot
    }

    /// Lets every held fetch (and any later one) complete.
    func release() { isHeld = false }

    func fetchSnapshot(previous: CanvasSnapshot?, now: Date) async throws -> CanvasSnapshot {
        calls += 1
        var noticedCancellation = false
        while isHeld {
            if Task.isCancelled, !noticedCancellation {
                noticedCancellation = true
                cancellationsSeen += 1
                lastCancellationSeenAt = .now
                if honorsCancellation { throw CancellationError() }
            }
            // The sleep runs in its own unstructured task, which this fetch's cancellation does not
            // reach, so a gateway scripted to ignore cancellation really does keep holding.
            await Task { try? await Task.sleep(for: .milliseconds(1)) }.value
        }
        let snapshot = makeSnapshot(previous, now)
        returned.append(snapshot)
        return snapshot
    }
}

/// Collects a subscriber's events on its consumer task; an actor, so a test can read it while the
/// consumer is still running.
actor EventInbox {
    private(set) var events: [RefreshCoordinator.Event] = []
    func append(_ event: RefreshCoordinator.Event) { events.append(event) }
}

/// Reads `stream` until it finishes (or the reading task is cancelled) and returns every event it
/// saw, also forwarding each one to `inbox` as it arrives.
func drain(_ stream: AsyncStream<RefreshCoordinator.Event>, into inbox: EventInbox? = nil) async -> [RefreshCoordinator.Event] {
    var seen: [RefreshCoordinator.Event] = []
    for await event in stream {
        seen.append(event)
        await inbox?.append(event)
    }
    return seen
}

/// `task`'s value if it finishes within `timeout`, else nil. On a timeout it cancels `task` and runs
/// `unblock` (e.g. releasing a held gateway a regressed `run` would otherwise wait on forever), so
/// a regression fails the test instead of hanging the whole run.
func finished<T: Sendable>(_ task: Task<T, Never>, within timeout: Duration = TestTimeBudget.seconds(5),
                           unblocking unblock: @escaping @Sendable () async -> Void = {}) async -> T? {
    let watchdog = Task {
        try await Task.sleep(for: timeout)
        task.cancel()
        await unblock()
    }
    let value = await task.value
    watchdog.cancel()
    if case .success = await watchdog.result { return nil } // it only ended because the watchdog cancelled it
    return value
}

/// Both helpers' default windows scale with `TALLY_TEST_TIME_SCALE` (`TestTimeBudget`). A fixed 5 s window
/// was missed once on the macOS runner's TallyCore step (app-core report O10), where these tests take 12-18 s.
///
/// Polls `condition` until it holds or `timeout` passes. Only for things with no completion
/// signal of their own, e.g. `onTermination`'s hop back onto the coordinator.
func eventually(within timeout: Duration = TestTimeBudget.seconds(5), _ condition: () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return await condition()
}

/// A coordinator over `gateway` and a fresh temp-directory `SnapshotStore`. The budgets default to
/// far longer than any test runs, so no timer fires unless a test asks for one.
func makeCoordinator(
    gateway: any CanvasGateway, clock: TestClock = TestClock(), initialSnapshot: CanvasSnapshot? = nil,
    liveRefreshBudget: Duration = .seconds(30), ceiling: Duration = .seconds(60)
) throws -> (coordinator: RefreshCoordinator, store: SnapshotStore) {
    let accountKey = AccountKey("sync-hardening")
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("tally-sync-hardening-\(UUID().uuidString)")
    try ProtectedFile.prepareDirectory(root, excludeFromBackup: true)
    let sealer = VaultSealer(account: accountKey.rawValue, keyring: VaultKeyring(store: InMemoryVaultKeyStore()), mayCreateKeys: true)
    let store = SnapshotStore(root: root, accountKey: accountKey, sealer: sealer)
    let coordinator = RefreshCoordinator(gateway: gateway, store: store, clock: clock, initialSnapshot: initialSnapshot,
                                         liveRefreshBudget: liveRefreshBudget, foregroundHardCeiling: ceiling,
                                         backgroundBudget: ceiling)
    return (coordinator, store)
}
