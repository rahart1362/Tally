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

extension AccountLifecycleSuites {
    /// Plan 06 step 9 / plan 07 M2-C1 L-2 (perf-app-runtime.md §2.4 S2–S9): token exchange, then the
    /// Keychain, the account key, `accounts.json`, the first sync, and a root switch that releases the
    /// FirstSync model.
    @Suite("Sign-in: provisioning, first sync, and the root switch", .serialized)
    @MainActor
    struct SignInFirstSyncTests {
        /// Waits for `model.firstSync` to finish, starting it as its page's `.task` would.
        private func runFirstSync(_ model: AppModel) async throws -> Bool {
            let viewModel = try #require(model.firstSync)
            viewModel.start()
            return try await HomeTestSupport.waitUntil { viewModel.isFinished || viewModel.failure != nil } && viewModel.isFinished
        }

        @Test("S2 → S8: the credential, accounts.json and the store are written before the first fetch; .finished switches the root; the FirstSync model is released")
        func signInThroughFirstSyncToTheHome() async throws {
            let ordering = Mutex<[String]>([])
            let box = Mutex<AccountHarness?>(nil)
            // The box holds the harness, whose gateway closure holds the box: break that cycle on exit
            // (LeakSanitizer reported the harness's stores as leaked without this).
            defer { box.withLock { $0 = nil } }
            let harness = try AccountHarness(gateway: { account in
                FlagshipAccountGateway(account: account.accountKey, onFetch: {
                    // S3 before S5: everything provisioning writes is in place when the first sync fetches.
                    guard let harness = box.withLock({ $0 }) else { return }
                    let saved = harness.credentials.credential != nil
                    let listed = AccountDirectoryStore(root: harness.root).activeAccount() != nil
                    let prepared = FileManager.default.fileExists(atPath: harness.accountDirectory.path)
                    ordering.withLock { $0.append("fetch saved=\(saved) listed=\(listed) prepared=\(prepared)") }
                })
            })
            box.withLock { $0 = harness }
            let model = AppModel(accountEnvironment: harness.environment)
            model.bootstrap()

            model.signInSucceeded(harness.credential, target: AccountHarness.target)
            weak var firstSync = model.firstSync
            #expect(firstSync != nil)
            #expect(model.route == .welcome, "the sign-in switched the root before the first sync")
            #expect(try await runFirstSync(model))

            #expect(ordering.withLock { $0 } == ["fetch saved=true listed=true prepared=true"])
            #expect(harness.credentials.credential == harness.credential, "the credential is not in the Keychain")
            #expect(AccountDirectoryStore(root: harness.root).activeAccount() == harness.record)
            let store = harness.environment.snapshotStore(for: harness.account, root: harness.root)
            guard case .loaded(let committed) = await store.loadSnapshot() else {
                Issue.record("the first sync committed nothing")
                return
            }
            #expect(committed.generation == 1)
            guard case .loaded = await store.loadGlance() else {
                Issue.record("the first sync wrote no glance")
                return
            }

            model.finishFirstSync()
            #expect(model.route == .signedIn(harness.account), "no root switch")
            #expect(model.firstSync == nil)
            #expect(model.activeAccount == harness.record)
            #expect(try await HomeTestSupport.waitUntil { firstSync == nil }, "the FirstSync model outlived the root switch")

            // S7: the Home projects the committed value itself.
            let home = try #require(model.home)
            await home.start()
            #expect(home.phase == .loaded)
            #expect(home.dashboard.hero.courseCount == 5)
            let coordinator = try #require(await model.accountRuntime.coordinator())
            #expect(await home.projector.installedSnapshot == coordinator.committedSnapshot)
            await model.awaitLaunchWork()
            #expect(harness.widgetReloads.value == 1, "S9: the widgets were not reloaded after the first glance")

            await home.end()
            await model.accountRuntime.end()
        }

        @Test("a failed first sync shows the failure; Retry runs the same coordinator again")
        func retryReusesTheCoordinator() async throws {
            let failFirst = Mutex(true)
            let harness = try AccountHarness(gateway: { account in
                FlagshipAccountGateway(account: account.accountKey, onFetch: {
                    if failFirst.withLock({ let first = $0; $0 = false; return first }) { throw RefreshFailure.offline }
                })
            })
            let model = AppModel(accountEnvironment: harness.environment)
            model.bootstrap()
            model.signInSucceeded(harness.credential, target: AccountHarness.target)
            let first = try #require(model.firstSync)
            first.start()
            #expect(try await HomeTestSupport.waitUntil { first.failure != nil })
            #expect(first.failure == .offline)
            let provisioned = try #require(await model.accountRuntime.coordinator())

            model.retryFirstSync()
            let second = try #require(model.firstSync)
            #expect(second !== first, "Retry must hand the page a fresh model")
            #expect(try await runFirstSync(model))
            #expect(await model.accountRuntime.coordinator() === provisioned, "Retry provisioned a second coordinator")

            model.finishFirstSync()
            #expect(model.route == .signedIn(harness.account))
            await model.home?.end()
            await model.accountRuntime.end()
        }

        @Test("Choose a Different School after a failure purges the half-made account")
        func abandonPurgesTheAccount() async throws {
            let harness = try AccountHarness(gateway: { account in
                FlagshipAccountGateway(account: account.accountKey, onFetch: { throw RefreshFailure.server })
            })
            let model = AppModel(accountEnvironment: harness.environment)
            model.bootstrap()
            model.signInSucceeded(harness.credential, target: AccountHarness.target)
            let viewModel = try #require(model.firstSync)
            viewModel.start()
            #expect(try await HomeTestSupport.waitUntil { viewModel.failure != nil })
            #expect(harness.credentials.credential != nil)

            model.abandonSignIn()
            #expect(model.firstSync == nil)
            await model.awaitTeardown()
            #expect(harness.credentials.credential == nil, "the abandoned sign-in's credential survived")
            #expect(AccountDirectoryStore(root: harness.root).activeAccount() == nil)
            #expect(!FileManager.default.fileExists(atPath: harness.accountDirectory.path))
            #expect(await model.accountRuntime.coordinator() == nil)
            #expect(model.route == .welcome)
        }

        @Test("a provisioning that stops part-way (after the credential and accounts.json), then Choose a Different School: nothing of it is left")
        func abandonAfterAFailedProvisioningPurgesWhatItWrote() async throws {
            let harness = try AccountHarness()
            // A plain file where the account's store directory goes: `SnapshotStore.prepare()`, the
            // last write of S3, fails after the credential and the `accounts.json` record are written.
            try FileManager.default.createDirectory(at: harness.accountDirectory.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data().write(to: harness.accountDirectory)
            let model = AppModel(accountEnvironment: harness.environment)
            model.bootstrap()
            model.signInSucceeded(harness.credential, target: AccountHarness.target)
            let viewModel = try #require(model.firstSync)
            viewModel.start()
            #expect(try await HomeTestSupport.waitUntil { viewModel.failure != nil })
            #expect(harness.credentials.credential != nil, "the provisioning did not get as far as the credential")
            #expect(AccountDirectoryStore(root: harness.root).activeAccount()?.accountKey == harness.account)

            model.abandonSignIn()
            await model.awaitTeardown()
            #expect(harness.credentials.credential == nil, "the abandoned sign-in's credential survived a failed provisioning")
            #expect(AccountDirectoryStore(root: harness.root).activeAccount() == nil,
                    "the abandoned sign-in's accounts.json record survived: the next launch would sign in to it")
            #expect(await model.accountRuntime.coordinator() == nil)
            #expect(model.route == .welcome)
        }

        @Test("abandoned while provisioning, which then stops part-way: what it wrote after the abandon's purge goes too")
        func abandonDuringAFailingProvisioningPurgesItsLateWrites() async throws {
            let harness = try AccountHarness()
            let gated = GatedCredentialStore(base: harness.credentials)
            let root = harness.root
            let environment = AccountEnvironment(
                storeRoot: { root }, credentialStore: gated, keyring: harness.keyring,
                lockPreferences: harness.lockPreferences, transport: harness.transport, notifications: harness.notifications,
                gatewayOverride: { account in FlagshipAccountGateway(account: account.accountKey) })
            let model = AppModel(accountEnvironment: environment)
            model.bootstrap()
            model.signInSucceeded(harness.credential, target: AccountHarness.target)
            let viewModel = try #require(model.firstSync)
            viewModel.start()
            #expect(try await HomeTestSupport.waitUntil { gated.saveStarted }, "provisioning never reached the Keychain")

            // The abandon's purge runs to the end while the credential is still unwritten.
            model.abandonSignIn()
            await model.awaitTeardown()
            // Then the provisioning goes on: the credential and `accounts.json` land after that purge,
            // and the store cannot be prepared (a plain file where its directory goes).
            try FileManager.default.createDirectory(at: harness.accountDirectory.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data().write(to: harness.accountDirectory)
            gated.open()
            #expect(try await HomeTestSupport.waitUntil { gated.saveFinished })
            #expect(try await HomeTestSupport.waitUntil(timeout: .seconds(10)) {
                harness.credentials.credential == nil && AccountDirectoryStore(root: root).activeAccount() == nil
            }, "a write that landed after the abandon's purge survived")
            _ = viewModel
        }
    }
}

/// `CoordinatorFirstSyncPublisher`'s mapping of coordinator states to a first sync's end.
@Suite("CoordinatorFirstSyncPublisher: which states end a first sync")
struct CoordinatorFirstSyncPublisherTests {
    @Test(arguments: [
        (FreshnessState.failed(.server, showing: nil), RefreshFailure?.some(.server)),
        (.offline(showing: nil), .offline),
        (.authExpired(showing: nil), .authExpired),
        (.noCache, nil),
        (.refreshing(showing: nil), nil),
        (.delayed(showing: nil), nil),
        (.fresh(at: Date(timeIntervalSince1970: 0)), nil),
    ])
    func failureStates(_ state: FreshnessState, _ expected: RefreshFailure?) {
        #expect(CoordinatorFirstSyncPublisher.failure(in: state) == expected)
    }

    @Test("provisioning that fails reports .failed at once and finishes the stream")
    func provisioningFailureFinishes() async {
        let publisher = CoordinatorFirstSyncPublisher(prepare: { nil })
        var events: [FirstSyncEvent] = []
        for await event in publisher.events() { events.append(event) }
        #expect(events == [.failed(.unknown)])
    }
}
#endif
