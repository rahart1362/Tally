#if DEBUG
import Foundation
import Testing
import TallyCanvasAPI
import TallyDomain
import TallyIntents
import TallyStore
import TallySync
import TallyTestSupport
@testable import TallyFeatures

extension AccountLifecycleSuites {
    /// Plan 06 step 10 / plan 07 M2-C1 L-3: `AppModel.signOut()` in perf-app-runtime.md §4.3's order,
    /// and afterwards nothing of the account is reachable: no coordinator, projector, Home model or
    /// source (weak references), and no `CanvasSnapshot` (the DEBUG live-instance counter).
    @Suite("Sign-out: §4.3's order, and nothing of the account survives", .serialized)
    @MainActor
    struct SignOutTests {
        /// A signed-in app over a seeded account, launched and with its Home started (what the shell's
        /// `.task` does), its coordinator attached and its launch refresh landed.
        private func signedInApp(_ harness: AccountHarness, lock: AppLockModel? = nil) async throws -> AppModel {
            try await harness.seedSignedInAccount()
            let model = AppModel(accountRuntime: AccountRuntime(resolve: { [environment = harness.environment] in
                await AccountSessionFactory.activeCoordinator(environment)
            }), accountEnvironment: harness.environment, lock: lock)
            await model.launch()
            await model.awaitLaunchWork()
            return model
        }

        @Test("the seven steps run in §4.3's order")
        func stepsRunInOrder() async throws {
            let harness = try AccountHarness()
            let model = try await signedInApp(harness)
            await model.home?.start()
            #expect(RefreshIntentBridge.coordinator != nil)

            model.signOut()
            #expect(model.route == .welcome, "step 1 did not happen at once")
            #expect(model.refreshStatus.freshness == .noCache, "step 2 did not happen at once")
            await model.awaitTeardown()
            #expect(model.signOutSteps == [.route, .refreshStatus, .home, .intentBridge, .runtime, .purge, .widgets])
            #expect(model.playsBrandMoment)
        }

        @Test("afterwards: no coordinator, projector, Home model or source, no CanvasSnapshot, and the account is erased")
        func nothingSurvives() async throws {
            let harness = try AccountHarness()
            let account = harness.account
            let model = try await signedInApp(harness)
            weak var coordinator: RefreshCoordinator?
            weak var home: HomeModel?
            weak var projector: HomeProjector?
            weak var source: AccountHomeSource?
            do {
                let live = try #require(model.home)
                await live.start() // the launch refresh commits generation 2
                #expect(try await AccountTestSupport.eventually {
                    await model.accountRuntime.coordinator()?.committedSnapshot?.generation == 2
                })
                coordinator = await model.accountRuntime.coordinator()
                home = live
                projector = live.projector
                source = live.source as? AccountHomeSource
                #expect(coordinator != nil && home != nil && projector != nil && source != nil)
                #expect(CanvasSnapshotInstances.liveCount(for: account) >= 1)
            }

            model.signOut()
            await model.awaitTeardown()

            #expect(try await HomeTestSupport.waitUntil { coordinator == nil }, "the coordinator outlived sign-out")
            #expect(try await HomeTestSupport.waitUntil { home == nil }, "the Home model outlived sign-out")
            #expect(try await HomeTestSupport.waitUntil { projector == nil }, "the projector outlived sign-out")
            #expect(try await HomeTestSupport.waitUntil { source == nil }, "the account's Home source outlived sign-out")
            #expect(try await HomeTestSupport.waitUntil { CanvasSnapshotInstances.liveCount(for: account) == 0 },
                    "a CanvasSnapshot of the signed-out account is still reachable")
            #expect(RefreshIntentBridge.coordinator == nil)
            #expect(await model.accountRuntime.coordinator() == nil)

            // Step 6: revoked at Canvas, notifications, store, credential, accounts.json, lock setting.
            #expect(harness.transport.requests.contains { $0.method == .delete && $0.url.path == "/login/oauth2/token" },
                    "the token was not revoked")
            #expect(harness.credentials.credential == nil)
            #expect(!FileManager.default.fileExists(atPath: harness.accountDirectory.path))
            #expect(harness.vaultKeys.count(KeyScope(account: account.rawValue, audience: .app)) == 0)
            #expect(AccountDirectoryStore(root: harness.root).activeAccount() == nil)
            #expect(await harness.lockPreferences.load() == .notFound)
            // Step 7.
            #expect(harness.widgetReloads.value >= 1)
            #expect(model.home == nil && model.activeAccount == nil)
        }

        @Test("from the lock view (locked, the Home never on screen): the lock turns off, Welcome shows, and the account is still erased")
        func signOutFromTheLockView() async throws {
            let harness = try AccountHarness(lock: AppLockPreference(isEnabled: true))
            let lock = AppLockModel(authenticator: ScriptedAuthenticator([.passcodeNotSet], availability: .passcodeNotSet),
                                    preferences: harness.lockPreferences)
            let model = try await signedInApp(harness, lock: lock)
            #expect(model.lock.isLocked)

            model.signOut()
            #expect(!model.lock.isLocked && !model.lock.isEnabled, "sign-out left the app locked")
            #expect(model.route == .welcome)
            await model.awaitTeardown()
            #expect(harness.credentials.credential == nil)
            #expect(!FileManager.default.fileExists(atPath: harness.accountDirectory.path))
            #expect(await harness.lockPreferences.load() == .notFound, "the lock setting outlived sign-out")
            #expect(try await HomeTestSupport.waitUntil { CanvasSnapshotInstances.liveCount(for: harness.account) == 0 })
        }

        @Test("sign-out is a no-op outside .signedIn, and a second sign-out changes nothing")
        func signOutIsGuarded() async throws {
            let harness = try AccountHarness()
            let model = try await signedInApp(harness)
            model.signOut()
            await model.awaitTeardown()
            let steps = model.signOutSteps
            model.signOut()
            await model.awaitTeardown()
            #expect(model.signOutSteps == steps)
            #expect(model.route == .welcome)
        }
    }
}
#endif
