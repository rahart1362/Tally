import Foundation
import Synchronization
import Testing
import TallyCanvasAPI
import TallyDomain
import TallyStore
import TallySync
import TallyTestSupport
@testable import TallyFeatures

/// A `CanvasGateway` that serves one fixed snapshot after `latency` and counts its fetches.
actor CountingGateway: CanvasGateway {
    private let snapshot: CanvasSnapshot
    private let latency: Duration
    private(set) var fetches = 0

    init(snapshot: CanvasSnapshot, latency: Duration) {
        self.snapshot = snapshot
        self.latency = latency
    }

    func fetchSnapshot(previous: CanvasSnapshot?, now: Date) async throws -> CanvasSnapshot {
        fetches += 1
        try await Task.sleep(for: latency)
        return snapshot
    }
}

/// A `CanvasGateway` whose first fetch lands at once and every later one after `latency`. It
/// counts fetches, and the fetches that were cancelled before they landed.
actor SlowAfterFirstFetchGateway: CanvasGateway {
    private let snapshot: CanvasSnapshot
    private let latency: Duration
    private(set) var fetches = 0
    private(set) var cancelled = 0

    init(snapshot: CanvasSnapshot, latency: Duration) {
        self.snapshot = snapshot
        self.latency = latency
    }

    func fetchSnapshot(previous: CanvasSnapshot?, now: Date) async throws -> CanvasSnapshot {
        fetches += 1
        guard fetches > 1 else { return snapshot }
        do {
            try await Task.sleep(for: latency)
        } catch {
            cancelled += 1
            throw error
        }
        return snapshot
    }
}

enum AccountTestSupport {
    /// Polls an async `condition` every 10 ms for up to `timeout`.
    @MainActor
    static func eventually(timeout: Duration = .seconds(5), _ condition: () async -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !(await condition()) {
            guard ContinuousClock.now < deadline else { return false }
            try await Task.sleep(for: .milliseconds(10))
        }
        return true
    }

    /// A real `RefreshCoordinator` over `gateway`, committing to a temporary vault-sealed store.
    static func coordinator(gateway: any CanvasGateway, account: String = "account-runtime-test") throws -> RefreshCoordinator {
        let accountKey = AccountKey(account)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tally-account-\(UUID().uuidString)")
        try ProtectedFile.prepareDirectory(directory, excludeFromBackup: true)
        let sealer = VaultSealer(account: accountKey.rawValue, keyring: VaultKeyring(store: InMemoryVaultKeyStore()),
                                 mayCreateKeys: true)
        let store = SnapshotStore(root: directory, accountKey: accountKey, sealer: sealer)
        return RefreshCoordinator(gateway: gateway, store: store, clock: SystemDateProvider(), initialSnapshot: nil)
    }
}

/// perf-app-runtime.md §7 step 7: the account's one coordinator, shared by every trigger.
@Suite("AccountRuntime: one coordinator per account, single-flight across triggers", .serialized)
@MainActor
struct AccountRuntimeTests {
    @Test("two concurrent backgroundRefresh() calls produce one run through one coordinator")
    func concurrentBackgroundRefreshesShareOneRun() async throws {
        let snapshot = try await FlagshipSnapshotHarness.fetchSnapshot(now: Date())
        let gateway = CountingGateway(snapshot: snapshot, latency: .milliseconds(300))
        let coordinator = try AccountTestSupport.coordinator(gateway: gateway)
        let resolutions = Mutex(0)
        let runtime = AccountRuntime(resolve: {
            resolutions.withLock { $0 += 1 }
            return coordinator
        })

        async let first: Void = runtime.backgroundRefresh()
        async let second: Void = runtime.backgroundRefresh()
        _ = await (first, second)

        #expect(await gateway.fetches == 1)
        #expect(resolutions.withLock { $0 } == 1, "the coordinator was resolved more than once")
        #expect(await coordinator.committedSnapshot?.courses.count == 5)
    }

    @Test("without an account, backgroundRefresh() is a no-op")
    func noAccountIsANoOp() async {
        let runtime = AccountRuntime()
        await runtime.backgroundRefresh()
        #expect(await runtime.coordinator() == nil)
    }

    // `.timeLimit`: the test drains a stream, so a regression that never finishes it fails in a
    // minute instead of hanging the run.
    @Test("end() retires the coordinator: its streams end with .noCache, its snapshot goes, it is released",
          .timeLimit(.minutes(1)))
    func endRetiresTheCoordinator() async throws {
        let snapshot = try await FlagshipSnapshotHarness.fetchSnapshot(now: Date())
        weak var released: RefreshCoordinator?
        let runtime = AccountRuntime()
        do {
            let coordinator = try AccountTestSupport.coordinator(gateway: CountingGateway(snapshot: snapshot, latency: .zero))
            released = coordinator
            await runtime.install(coordinator)
            await runtime.backgroundRefresh()
            #expect(await coordinator.committedSnapshot != nil)
            let events = await coordinator.events()
            await runtime.end()
            var last: RefreshCoordinator.Event?
            for await event in events { last = event } // finishes: the coordinator shut down
            #expect(last == .stateChanged(.noCache))
            #expect(await coordinator.committedSnapshot == nil)
        }
        #expect(await runtime.coordinator() == nil)
        #expect(try await HomeTestSupport.waitUntil { released == nil }, "the retired coordinator outlived end()")
    }
}

/// perf-app-runtime.md §7 step 7 and plan 06 §5: the signed-in Home reads the coordinator through
/// its own `events()` stream and projects `committedSnapshot`, the committed value itself.
@Suite("AccountHomeSource: events() and committedSnapshot, no fan-out", .serialized)
@MainActor
struct AccountHomeSourceTests {
    /// The source reads `committedSnapshot` and never touches the store, so the Home projects the
    /// committed value itself, not a copy decoded from disk.
    @Test("a refresh's committed snapshot is what the Home projects; sign-out ends the stream with noCache")
    func committedSnapshotReachesTheHome() async throws {
        let snapshot = try await FlagshipSnapshotHarness.fetchSnapshot(now: Date())
        let coordinator = try AccountTestSupport.coordinator(gateway: CountingGateway(snapshot: snapshot, latency: .zero))
        let runtime = AccountRuntime()
        await runtime.install(coordinator)
        let projector = HomeProjector()
        let model = HomeModel(source: AccountHomeSource(runtime: runtime), projector: projector)

        await model.start() // subscribes, then refreshes (.launch) through the coordinator
        #expect(try await HomeTestSupport.waitUntil { model.phase == .loaded })
        #expect(model.dashboard.hero.courseCount == 5)
        let committed = await coordinator.committedSnapshot
        #expect(committed != nil)
        #expect(await projector.installedSnapshot == committed, "the Home projects the committed value itself")

        await runtime.end() // sign-out: .noCache, then every stream finishes
        #expect(try await HomeTestSupport.waitUntil { model.freshness == .noCache })
    }

    /// Plan 06 row 7 (SH-2): once every caller waiting on `RefreshCoordinator.run` is cancelled,
    /// the coordinator cancels the fetch and discards its result, and automatic refreshes then stay
    /// throttled for 5 minutes. So `.refreshable`'s task must never be the run's only caller: the
    /// run belongs to `HomeModel`, and cancelling the pull only stops the waiting.
    @Test("pull-to-refresh over the real coordinator: cancelling the view's task still commits the refresh",
          .timeLimit(.minutes(1)))
    func cancelledPullStillCommits() async throws {
        let snapshot = try await FlagshipSnapshotHarness.fetchSnapshot(now: Date())
        // The launch fetch lands at once; the pull's fetch takes 1.5 s, far past the 1 s a
        // cancelled pull may take to return.
        let gateway = SlowAfterFirstFetchGateway(snapshot: snapshot, latency: .milliseconds(1_500))
        let coordinator = try AccountTestSupport.coordinator(gateway: gateway)
        let runtime = AccountRuntime()
        await runtime.install(coordinator)
        let model = HomeModel(source: AccountHomeSource(runtime: runtime))
        await model.start() // the launch run commits generation 1
        #expect(try await HomeTestSupport.waitUntil { model.phase == .loaded })
        #expect(await coordinator.committedSnapshot?.generation == 1)

        let pull = Task { await model.refreshUntilSettledOrDelayed(budget: .seconds(10)) }
        #expect(try await AccountTestSupport.eventually { await gateway.fetches == 2 }, "the pull never started a fetch")
        let cancelledAt = ContinuousClock.now
        pull.cancel()
        await pull.value
        #expect(ContinuousClock.now - cancelledAt < .seconds(1), "the cancelled pull kept waiting")

        #expect(try await AccountTestSupport.eventually { await coordinator.committedSnapshot?.generation == 2 },
                "the refresh was abandoned with the view's task: nothing was committed")
        #expect(await gateway.cancelled == 0, "the coordinator cancelled the pull's fetch")
        #expect(try await HomeTestSupport.waitUntil {
            if case .fresh = model.freshness { return true }
            return false
        }, "the Home never showed the committed refresh as fresh")

        await model.end()
        await runtime.end()
    }

    @Test("without an account the source reports noCache once and finishes", .timeLimit(.minutes(1)))
    func noAccountFinishesAtOnce() async {
        let source = AccountHomeSource(runtime: AccountRuntime())
        var received: [HomeUpdate] = []
        for await update in await source.updates() { received.append(update) }
        #expect(received.count == 1)
        #expect(received.first?.freshness == .noCache)
        #expect(received.first?.snapshot == nil)
    }
}
