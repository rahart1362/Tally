import Foundation
import Testing
import TallyCanvasAPI
import TallyDomain
import TallyIntents
import TallyStore
import TallySync
import TallyTestSupport
@testable import TallyFeatures
@testable import Tally

/// E04 + perf-app-runtime.md §7 step 1: the composition root's `AppModel` and its root route.
/// Every legal transition is exercised, and every method is also called from a route it is not
/// defined from, to prove that call is a no-op.
///
/// `.serialized`: `attach`/`detach` write the process-wide `RefreshIntentBridge`, so these tests
/// must never interleave with each other at a suspension point.
@Suite("AppModel / AppEnvironment: composition root and root route", .serialized)
@MainActor
struct AppModelTests {
    private static let account = AccountKey("route-test")

    @Test("live() builds synchronously, with one account runtime shared by the UI and the background task, and no coordinator yet")
    func liveHasNoCoordinatorYet() async {
        let environment = AppEnvironment.live()
        #expect(environment.accountRuntime === environment.appModel.accountRuntime)
        #expect(await environment.accountRuntime.coordinator() == nil)
        #expect(environment.appModel.refreshStatus.freshness == .noCache)
        #expect(environment.appModel.route == .launching)
    }

    @Test("a fresh AppModel starts detached, on the launch route, with the brand moment armed")
    func freshAppModel() async {
        let model = AppModel()
        #expect(await model.accountRuntime.coordinator() == nil)
        #expect(model.refreshStatus.freshness == .noCache)
        #expect(model.route == .launching)
        #expect(model.playsBrandMoment)
    }

    @Test("bootstrap: launching -> welcome, exactly once")
    func bootstrapGoesToWelcome() {
        let model = AppModel()
        model.bootstrap()
        #expect(model.route == .welcome)
        model.enterSample()
        model.bootstrap() // not from .launching: a no-op
        #expect(model.route == .sample)
    }

    @Test("enterSample/exitSample: welcome -> sample -> welcome, twice; a session per entry; no brand moment on exit")
    func sampleRoundTrips() {
        let model = AppModel()
        model.bootstrap()
        for _ in 0..<2 {
            model.enterSample()
            #expect(model.route == .sample)
            let session = model.home
            #expect(session != nil)
            model.enterSample() // already .sample: a no-op that keeps the same session
            #expect(model.route == .sample)
            #expect(model.home === session)
            model.exitSample()
            #expect(model.route == .welcome)
            #expect(model.home == nil)
            #expect(!model.playsBrandMoment)
        }
    }

    @Test("enterSample and exitSample are no-ops outside their source routes")
    func sampleTransitionsAreGuarded() {
        let model = AppModel()
        model.enterSample() // .launching
        #expect(model.route == .launching)
        model.exitSample() // .launching
        #expect(model.route == .launching)

        model.bootstrap()
        model.exitSample() // .welcome
        #expect(model.route == .welcome)
        #expect(model.playsBrandMoment) // an exit that did not happen changes nothing

        model.completeSignIn(Self.account)
        model.enterSample() // .signedIn
        #expect(model.route == .signedIn(Self.account))
        model.exitSample() // .signedIn
        #expect(model.route == .signedIn(Self.account))
    }

    @Test("completeSignIn: welcome -> signedIn(account); a no-op from launching and sample")
    func completeSignInIsGuarded() {
        let model = AppModel()
        model.completeSignIn(Self.account) // .launching
        #expect(model.route == .launching)
        model.bootstrap()
        model.enterSample()
        model.completeSignIn(Self.account) // .sample
        #expect(model.route == .sample)
        model.exitSample()
        model.completeSignIn(Self.account)
        #expect(model.route == .signedIn(Self.account))
        model.completeSignIn(AccountKey("another")) // already signed in: a no-op
        #expect(model.route == .signedIn(Self.account))
    }

    @Test("signOut: signedIn -> welcome with the brand moment re-armed; a no-op from welcome and sample")
    func signOutReturnsToWelcome() {
        let model = AppModel()
        model.bootstrap()
        model.signOut() // .welcome
        #expect(model.route == .welcome)
        model.enterSample()
        model.signOut() // .sample
        #expect(model.route == .sample)
        model.exitSample()
        #expect(!model.playsBrandMoment)

        model.completeSignIn(Self.account)
        model.signOut()
        #expect(model.route == .welcome)
        #expect(model.playsBrandMoment)
    }

    @Test("attach sets RefreshIntentBridge; detach and signOut clear it and release the coordinator")
    func attachAndDetachDriveTheIntentBridge() async throws {
        let model = AppModel()
        model.bootstrap()
        model.completeSignIn(Self.account)
        let coordinator = try RouteTestCoordinator.make()

        await model.attach(coordinator)
        #expect(await model.accountRuntime.coordinator() === coordinator)
        #expect(RefreshIntentBridge.coordinator === coordinator)

        model.detach() // not sign-out: the runtime keeps the account's coordinator
        #expect(RefreshIntentBridge.coordinator == nil)
        #expect(await model.accountRuntime.coordinator() === coordinator)

        await model.attach(coordinator)
        #expect(RefreshIntentBridge.coordinator === coordinator)
        model.signOut()
        #expect(model.route == .welcome)
        #expect(RefreshIntentBridge.coordinator == nil) // at once, before the teardown
        #expect(model.refreshStatus.freshness == .noCache)
        await model.awaitTeardown()
        #expect(await model.accountRuntime.coordinator() == nil)
    }

    /// perf-app-runtime.md §7 step 7 (and §4.3's sign-out order): the signed-in Home reads the
    /// account's coordinator; sign-out retires it, and nothing the app holds keeps it alive.
    @Test("completeSignIn builds the Home over the account; signOut releases the Home and the coordinator")
    func signOutReleasesTheAccount() async throws {
        let model = AppModel()
        model.bootstrap()
        weak var releasedCoordinator: RefreshCoordinator?
        weak var releasedHome: HomeModel?
        do {
            let coordinator = try RouteTestCoordinator.make()
            releasedCoordinator = coordinator
            await model.attach(coordinator)
        }
        model.completeSignIn(Self.account)
        releasedHome = model.home
        #expect(releasedHome != nil)

        model.signOut()
        #expect(model.home == nil)
        #expect(RefreshIntentBridge.coordinator == nil)
        await model.awaitTeardown()
        #expect(await model.accountRuntime.coordinator() == nil)
        #expect(try await HomeTestSupport.waitUntil { releasedHome == nil }, "the Home model outlived sign-out")
        #expect(try await HomeTestSupport.waitUntil { releasedCoordinator == nil }, "the coordinator outlived sign-out")
    }
}

/// A real `RefreshCoordinator` over the flagship replay (the same harness shape as
/// `RefreshStatusModelTests`); these tests only attach and detach it, so it never fetches.
enum RouteTestCoordinator {
    private struct AlwaysFail: TokenRefreshing {
        func refresh(_ credential: CanvasCredential) async throws -> CanvasCredential { throw AuthError.reauthRequired }
    }

    static func make() throws -> RefreshCoordinator {
        let host = "canvas.northfield.example"
        let accountKey = AccountKey("route-test")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tally-route-\(UUID().uuidString)")
        try ProtectedFile.prepareDirectory(directory, excludeFromBackup: true)
        let sealer = VaultSealer(account: accountKey.rawValue, keyring: VaultKeyring(store: InMemoryVaultKeyStore()),
                                 mayCreateKeys: true)
        let store = SnapshotStore(root: directory, accountKey: accountKey, sealer: sealer)
        let credential = CanvasCredential(host: host, userID: "4820117", accessToken: "t", refreshToken: "r",
                                          accessTokenExpiresAt: .distantFuture)
        let tokens = TokenCoordinator(initial: credential, store: InMemoryCredentialStore(credential),
                                     refresher: AlwaysFail(), clock: SystemDateProvider())
        let client = CanvasClient(host: host, transport: try ReplayTransport.persona("flagship"), tokens: tokens)
        let gateway = LiveCanvasGateway(host: host, accountKey: accountKey, client: client)
        return RefreshCoordinator(gateway: gateway, store: store, clock: SystemDateProvider(), initialSnapshot: nil)
    }
}
