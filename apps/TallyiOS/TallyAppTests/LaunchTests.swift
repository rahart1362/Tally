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
        #expect(recorded.map(\.0) == ["reconcileInstall", "lockPreference", "accounts", "glance"])
        #expect(recorded.allSatisfy { !$0.1 }, "a launch step ran on the main thread: \(recorded)")
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
