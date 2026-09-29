#if DEBUG
import Foundation
import Synchronization
import Testing
import TallyCanvasAPI
import TallyDomain
import TallyStore
import TallySync
import TallyTestSupport
@testable import TallyFeatures

/// Plan 06 step 8 / plan 07 M2-C1 L-1: `LaunchBootstrapper` (perf-app-runtime.md §2.4 L3), off the
/// main actor.
@Suite("LaunchBootstrapper: accounts.json, the lock setting, the reconcile and the glance, off the main actor", .serialized)
@MainActor
struct LaunchBootstrapperTests {
    @Test("nothing on disk: Welcome with the lock off; the fresh-install reconcile runs once")
    func freshInstallGoesToWelcome() async throws {
        let harness = try AccountHarness()
        // Inherited from an earlier install: a vault key and a credential (Keychain items can
        // outlive the app, files cannot).
        _ = try harness.keyring.currentKey(for: KeyScope(account: "earlier", audience: .app), createIfMissing: true)
        try await harness.credentials.save(harness.credential)

        let resolution = await LaunchBootstrapper(environment: harness.environment).resolve()
        #expect(resolution == .welcome)
        #expect(harness.vaultKeys.count(KeyScope(account: "earlier", audience: .app)) == 0, "inherited keys survived")
        #expect(harness.credentials.credential == nil, "an inherited credential survived the fresh install")
        let sentinel = StoreLayout(root: harness.root, accountKey: AccountKey("install")).installSentinel
        #expect(FileManager.default.fileExists(atPath: sentinel.path))

        // Later launches never reconcile again.
        try await harness.credentials.save(harness.credential)
        _ = await LaunchBootstrapper(environment: harness.environment).resolve()
        #expect(harness.credentials.credential == harness.credential)
    }

    @Test("a signed-in account: its record, its glance (hero count, due soon, asOf) and the lock setting")
    func signedInAccountResolves() async throws {
        let harness = try AccountHarness(lock: AppLockPreference(isEnabled: true, gracePeriod: .fiveMinutes))
        try await harness.seedSignedInAccount()
        let snapshot = try await FlagshipAccountGateway.flagship(account: harness.account)

        let resolution = await LaunchBootstrapper(environment: harness.environment).resolve()
        #expect(resolution.account == harness.record)
        #expect(resolution.lock == AppLockPreference(isEnabled: true, gracePeriod: .fiveMinutes))
        let glance = try #require(resolution.glance)
        #expect(glance.generation == 1)
        #expect(glance.dashboard.hero.courseCount == snapshot.courses.count)
        #expect(glance.dashboard.hero.overallPercent == nil, "the glance never carries a percentage")
        #expect(glance.dashboard.dueSoon.count <= HomeGlance.dueSoonLimit)
        #expect(glance.freshness == .fresh(at: glance.asOf))
    }

    @Test("every step runs off the main thread, even when the launch is started from the main actor")
    func resolveRunsOffTheMainThread() async throws {
        let harness = try AccountHarness()
        try await harness.seedSignedInAccount()
        let steps = Mutex<[(String, Bool)]>([])
        let bootstrapper = LaunchBootstrapper(environment: harness.environment, threadProbe: { step, onMain in
            steps.withLock { $0.append((step, onMain)) }
        })
        _ = await bootstrapper.resolve()
        let recorded = steps.withLock { $0 }
        let names = recorded.map(\.0)
        // PERF-L: the lock setting is read alongside the files, so only the dependent steps are
        // ordered: the reconcile before any file, `accounts.json` before the account's glance.
        #expect(names.sorted() == ["accounts", "glance", "lockPreference", "reconcileInstall"], "\(names)")
        let order = { (step: String) in names.firstIndex(of: step) ?? .max }
        #expect(order("reconcileInstall") < order("accounts") && order("accounts") < order("glance"), "\(names)")
        #expect(recorded.allSatisfy { !$0.1 }, "a launch step ran on the main thread: \(recorded)")
    }

    @Test("PERF-L: the lock setting's read overlaps the account's file reads")
    func lockReadOverlapsTheFileReads() async throws {
        let harness = try AccountHarness()
        try await harness.seedSignedInAccount()
        let glanceStarted = Mutex(false)
        // The lock read waits for the glance step to start: it returns at once when the two run
        // together, and only at its timeout when the reads run one after another.
        let lock = ProbedLockPreferences(AppLockPreference(isEnabled: true),
                                         loadWaitsFor: { glanceStarted.withLock { $0 } })
        let bootstrapper = LaunchBootstrapper(environment: harness.environment(lockPreferences: lock), threadProbe: { step, _ in
            if step == "glance" { glanceStarted.withLock { $0 = true } }
        })
        let resolution = await bootstrapper.resolve()
        #expect(resolution.account == harness.record && resolution.glance != nil)
        #expect(resolution.lock == AppLockPreference(isEnabled: true))
        #expect(lock.loadsThatWaitedOut == 0, "the lock setting was read before the account's files, not alongside them")
    }

    @Test("a fresh install's first launch uses the lock setting as its reconcile left it, even when a read raced the reset")
    func reconcileResetWinsOverARacingLockRead() async throws {
        let harness = try AccountHarness()
        // Inherited from an earlier install: the setting is on. The reset waits until a read has
        // begun, so the launch's first read always sees the inherited value.
        let lock = ProbedLockPreferences(AppLockPreference(isEnabled: true), resetWaitsForALoad: true)
        let resolution = await LaunchBootstrapper(environment: harness.environment(lockPreferences: lock)).resolve()
        #expect(resolution == .welcome, "the inherited lock setting survived the reconcile: \(resolution.lock)")
        #expect(lock.loads == 2, "the setting was not read again after the reconcile")
        #expect(lock.loadsThatWaitedOut == 0)
    }

    @Test("an unreadable lock setting fails closed: the launch locks")
    func unreadableLockSettingFailsClosed() async throws {
        #expect(AppLockPreferenceRead.unavailable.effective.isEnabled)
        #expect(!AppLockPreferenceRead.notFound.effective.isEnabled)
        #expect(AppLockPreferenceRead.found(.disabled).effective == .disabled)
    }
}

extension AccountLifecycleSuites {
    /// Plan 07 M2-C1 L-1: the launch's route and paint order (perf-app-runtime.md §2.4 L4–L9).
    @Suite("Launch: the cached glance paints first, the one decoded snapshot follows, the network waits", .serialized)
    @MainActor
    struct LaunchSequenceTests {
        @Test("no account: Welcome")
        func noAccountLaunchesToWelcome() async throws {
            let harness = try AccountHarness()
            let model = AppModel(accountEnvironment: harness.environment)
            await model.launch()
            #expect(model.route == .welcome)
            #expect(model.home == nil)
            #expect(model.lock.isConfigured && !model.lock.isLocked)
        }

        @Test("no account, but the lock setting left on (a sign-out stopped before its last step): Welcome, never locked")
        func noAccountNeverLocksWelcome() async throws {
            let harness = try AccountHarness(lock: AppLockPreference(isEnabled: true))
            // Not a fresh install (its reconcile would reset the setting itself): an earlier
            // launch's sentinel is on disk, and no account.
            try ProtectedFile.atomicWrite(Data(), to: StoreLayout(root: harness.root, accountKey: harness.account).installSentinel,
                                          excludeFromBackup: true)
            let model = AppModel(accountEnvironment: harness.environment)

            await model.launch()
            #expect(model.route == .welcome)
            #expect(model.lock.isConfigured && !model.lock.isEnabled && !model.lock.isLocked,
                    "Welcome was locked, and its only escape (sign-out) has no account to sign out of")
            model.lock.scenePhaseChanged(to: .background)
            model.lock.scenePhaseChanged(to: .active)
            #expect(!model.lock.isLocked && !model.lock.showsPrivacyCover)
            #expect(await harness.lockPreferences.load() == .found(AppLockPreference(isEnabled: true)),
                    "the launch changed the setting")
        }

        @Test("a signed-in launch: .signedIn with the glance painted in the same assignment, then the full projection from one decoded snapshot")
        func signedInLaunchPaintsTheGlanceThenTheProjection() async throws {
            let harness = try AccountHarness()
            try await harness.seedSignedInAccount()
            let account = harness.account
            #expect(CanvasSnapshotInstances.liveCount(for: account) == 0, "the seeding kept a snapshot alive")
            let runtime = AccountRuntime(resolve: { [environment = harness.environment] in
                await AccountSessionFactory.activeCoordinator(environment)
            })
            let model = AppModel(accountRuntime: runtime, accountEnvironment: harness.environment)

            await model.launch()
            #expect(model.route == .signedIn(account))
            let home = try #require(model.home)
            #expect(home.phase == .glance, "the route switched without the glance on screen")
            #expect(home.dashboard.hero.courseCount == 5)

            await model.awaitLaunchWork()
            #expect(home.phase == .loaded)
            #expect(home.dashboard.hero.courseCount == 5)
            #expect(home.dashboard.hero.overallPercent != nil)
            let coordinator = try #require(await runtime.coordinator())
            #expect(await coordinator.committedSnapshot?.generation == 1)
            #expect(await home.projector.installedSnapshot == coordinator.committedSnapshot)
            // perf-app-runtime.md §2.2 rule 1: the coordinator and the projector share the one value
            // the launch decoded; no second copy is alive.
            #expect(CanvasSnapshotInstances.liveCount(for: account) == 1)

            await model.home?.end()
            await runtime.end()
        }

        @Test("the launch refresh (L9) runs only after the cached projection is on screen (L8)")
        func networkWaitsForTheCachedPaint() async throws {
            let phases = PhaseAtFetch()
            let harness = try AccountHarness(gateway: { account in
                FlagshipAccountGateway(account: account.accountKey, onFetch: { await phases.record() })
            })
            try await harness.seedSignedInAccount()
            let model = AppModel(accountRuntime: AccountRuntime(resolve: { [environment = harness.environment] in
                await AccountSessionFactory.activeCoordinator(environment)
            }), accountEnvironment: harness.environment)
            phases.model = model

            await model.launch()
            await model.home?.start() // what the Home shell's `.task` does once it is on screen
            #expect(try await AccountTestSupport.eventually { phases.recorded.count == 1 }, "the launch refresh never ran")
            #expect(phases.recorded == [.loaded], "the network ran before the cached projection was applied")

            await model.home?.end()
            await model.accountRuntime.end()
        }

        @Test("with the app lock on: locked at cold launch, projected behind the lock, no network until the Home is on screen")
        func lockedLaunchProjectsButDoesNotRefresh() async throws {
            let gateways = Mutex<[FlagshipAccountGateway]>([])
            let harness = try AccountHarness(gateway: { account in
                let gateway = FlagshipAccountGateway(account: account.accountKey)
                gateways.withLock { $0.append(gateway) }
                return gateway
            }, lock: AppLockPreference(isEnabled: true))
            try await harness.seedSignedInAccount()
            let model = AppModel(accountRuntime: AccountRuntime(resolve: { [environment = harness.environment] in
                await AccountSessionFactory.activeCoordinator(environment)
            }), accountEnvironment: harness.environment)

            await model.launch()
            #expect(model.lock.isLocked, "the lock did not lock at cold launch")
            #expect(model.route == .signedIn(harness.account))
            await model.awaitLaunchWork()
            #expect(model.home?.phase == .loaded, "the cached projection did not proceed behind the lock")
            var fetches = 0
            for gateway in gateways.withLock({ $0 }) { fetches += await gateway.fetches }
            #expect(fetches == 0, "the handshake ran while the app was locked")

            await model.home?.end()
            await model.accountRuntime.end()
        }
    }
}

/// Plan 07 M2-C1 L-1: `HomeModel.start()` awaits the source's first update before the launch
/// refresh (L9 never before L8), whatever the source.
@Suite("HomeModel: the launch refresh waits for the first update")
@MainActor
struct HomeLaunchOrderTests {
    @Test("a first update that takes 300 ms still lands before refresh(.launch) is asked for")
    func refreshWaitsForTheFirstUpdate() async throws {
        let snapshot = try await FlagshipSnapshotHarness.fetchSnapshot(now: HomeTestSupport.anchor)
        let source = DelayedFirstUpdateSource(
            first: HomeTestSupport.update(snapshot, generation: 1, freshness: .fresh(at: HomeTestSupport.anchor)),
            delay: .milliseconds(300))
        let model = HomeModel(source: source)
        source.onLaunchRefresh = { [weak model] in model?.phase }
        await model.start()
        #expect(source.phaseAtLaunchRefresh == .loaded, "refresh(.launch) ran before the cached projection")
        await model.end()
    }
}

/// A lock-setting store that makes the launch's concurrency observable: `load()` can wait (up to
/// `timeout`) for a condition, and `reset()` can wait for a `load()` to have begun. A wait that runs
/// out is counted, never hangs the test.
nonisolated final class ProbedLockPreferences: AppLockPreferenceStoring {
    private let stored: Mutex<AppLockPreference?>
    private let loadWaitsFor: (@Sendable () -> Bool)?
    private let resetWaitsForALoad: Bool
    private let counts = Mutex((loads: 0, waitedOut: 0))
    static let timeout: Duration = .seconds(5)

    init(_ preference: AppLockPreference?, loadWaitsFor: (@Sendable () -> Bool)? = nil, resetWaitsForALoad: Bool = false) {
        stored = Mutex(preference)
        self.loadWaitsFor = loadWaitsFor
        self.resetWaitsForALoad = resetWaitsForALoad
    }

    var loads: Int { counts.withLock { $0.loads } }
    var loadsThatWaitedOut: Int { counts.withLock { $0.waitedOut } }

    func load() async -> AppLockPreferenceRead {
        counts.withLock { $0.loads += 1 }
        let read = stored.withLock { $0.map(AppLockPreferenceRead.found) ?? .notFound }
        if let loadWaitsFor, await !Self.poll(loadWaitsFor) { counts.withLock { $0.waitedOut += 1 } }
        return read
    }

    func save(_ preference: AppLockPreference) async throws {
        stored.withLock { $0 = preference }
    }

    func reset() async {
        if resetWaitsForALoad, await !Self.poll({ self.loads > 0 }) { counts.withLock { $0.waitedOut += 1 } }
        stored.withLock { $0 = nil }
    }

    private static func poll(_ condition: @Sendable () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return true
    }
}

extension AccountHarness {
    /// This harness's environment with another app-lock setting store.
    func environment(lockPreferences: any AppLockPreferenceStoring) -> AccountEnvironment {
        AccountEnvironment(storeRoot: { [root] in root }, credentialStore: credentials, keyring: keyring,
                           lockPreferences: lockPreferences, transport: transport, notifications: notifications,
                           gatewayOverride: { account in FlagshipAccountGateway(account: account.accountKey) })
    }
}

/// Records the Home's phase each time the gateway is asked for data.
final class PhaseAtFetch: @unchecked Sendable {
    // Written once on the main actor before any fetch; read on the main actor.
    @MainActor weak var model: AppModel?
    private let phases = Mutex<[HomeModel.Phase?]>([])

    var recorded: [HomeModel.Phase?] { phases.withLock { $0 } }

    func record() async {
        let phase = await MainActor.run { model?.home?.phase }
        phases.withLock { $0.append(phase) }
    }
}

/// A source whose first update arrives `delay` after the subscription, and which records the
/// model's phase when the launch refresh is asked for.
@MainActor
final class DelayedFirstUpdateSource: HomeDataSource {
    private let first: HomeUpdate
    private let delay: Duration
    var onLaunchRefresh: (() -> HomeModel.Phase?)?
    private(set) var phaseAtLaunchRefresh: HomeModel.Phase?

    init(first: HomeUpdate, delay: Duration) {
        self.first = first
        self.delay = delay
    }

    nonisolated func updates() async -> AsyncStream<HomeUpdate> {
        let (stream, continuation) = AsyncStream<HomeUpdate>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let (first, delay) = await MainActor.run { (self.first, self.delay) }
        Task {
            try? await Task.sleep(for: delay)
            continuation.yield(first)
        }
        return stream
    }

    nonisolated func refresh(_ trigger: RefreshTrigger) async {
        guard trigger == .launch else { return }
        await MainActor.run { phaseAtLaunchRefresh = onLaunchRefresh?() }
    }

    nonisolated func end() async {}
}

#endif
