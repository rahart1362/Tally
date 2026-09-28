import Foundation
import Testing
import TallyCanvasAPI
import TallyDomain
import TallyStore
import TallySync
import TallyTestSupport
@testable import TallyFeatures

/// E04: `RefreshStatusModel` mirrors a real `RefreshCoordinator` end to end — the same harness
/// shape `TallyCore`'s own `RefreshCoordinatorTests` uses (`ReplayTransport.persona("flagship")`,
/// a temp-directory `SnapshotStore`, `VaultSealer`/`InMemoryVaultKeyStore`), proving the E04
/// wiring works even though the app itself has no signed-in account yet to exercise it with.
@Suite("RefreshStatusModel: mirrors a real RefreshCoordinator's events")
struct RefreshStatusModelTests {
    private struct AlwaysFail: TokenRefreshing {
        func refresh(_ credential: CanvasCredential) async throws -> CanvasCredential { throw AuthError.reauthRequired }
    }

    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tally-refresh-status-\(UUID().uuidString)")
        try ProtectedFile.prepareDirectory(url, excludeFromBackup: true)
        return url
    }

    private func makeCoordinator() throws -> RefreshCoordinator {
        let host = "canvas.northfield.example"
        let accountKey = AccountKey("refresh-status-test")
        let sealer = VaultSealer(account: accountKey.rawValue, keyring: VaultKeyring(store: InMemoryVaultKeyStore()), mayCreateKeys: true)
        let store = SnapshotStore(root: try tempDirectory(), accountKey: accountKey, sealer: sealer)
        let transport = try ReplayTransport.persona("flagship")
        let credential = CanvasCredential(host: host, userID: "4820117", accessToken: "t", refreshToken: "r",
                                          accessTokenExpiresAt: .distantFuture)
        let tokens = TokenCoordinator(initial: credential, store: InMemoryCredentialStore(credential),
                                     refresher: AlwaysFail(), clock: SystemDateProvider())
        let client = CanvasClient(host: host, transport: transport, tokens: tokens)
        let gateway = LiveCanvasGateway(host: host, accountKey: accountKey, client: client)
        return RefreshCoordinator(gateway: gateway, store: store, clock: SystemDateProvider(), initialSnapshot: nil)
    }

    @Test("attach() adopts the coordinator's current state, then a manual refresh reaches fresh")
    @MainActor
    func attachAndRefreshReachesFresh() async throws {
        let coordinator = try makeCoordinator()
        let model = RefreshStatusModel()
        #expect(model.freshness == .noCache)

        await model.attach(to: coordinator)
        #expect(model.freshness == .noCache) // nothing committed yet

        await model.refresh()
        // Allow the event stream's background task a turn to deliver the terminal event.
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.freshness.showing != nil)
        if case .fresh = model.freshness {} else { Issue.record("expected .fresh, got \(model.freshness)") }
    }

    @Test("detach() stops mirroring and resets to noCache")
    @MainActor
    func detachResets() async throws {
        let coordinator = try makeCoordinator()
        let model = RefreshStatusModel()
        await model.attach(to: coordinator)
        await model.refresh()
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.freshness != .noCache)

        model.detach()
        #expect(model.freshness == .noCache)

        // A further event from the (now-detached) coordinator must not resurrect state.
        await coordinator.run(trigger: .manual)
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.freshness == .noCache)
    }

    /// perf-app-runtime.md §7 step 7: with a stream per subscriber (SH-1), a detached model can
    /// attach again, and a new coordinator's events reach it.
    @Test("attach -> detach -> attach to a new coordinator: the new coordinator's events arrive")
    @MainActor
    func reattachToANewCoordinatorReceivesEvents() async throws {
        let model = RefreshStatusModel()
        let first = try makeCoordinator()
        await model.attach(to: first)
        model.detach()

        let second = try makeCoordinator()
        await model.attach(to: second)
        await model.refresh() // a manual run through `second`
        #expect(try await HomeTestSupport.waitUntil {
            if case .fresh = model.freshness { true } else { false }
        }, "got \(model.freshness)")
    }

    /// perf-app-runtime.md §7 step 7: the subscription task captures only its stream, so after
    /// `detach()` nothing in the model keeps the coordinator (and its snapshot) alive.
    @Test("after detach() and release, the coordinator deallocates")
    @MainActor
    func detachLetsTheCoordinatorGo() async throws {
        let model = RefreshStatusModel()
        weak var released: RefreshCoordinator?
        do {
            let coordinator = try makeCoordinator()
            released = coordinator
            await model.attach(to: coordinator)
            await model.refresh()
            #expect(try await HomeTestSupport.waitUntil {
                if case .fresh = model.freshness { true } else { false }
            })
        }
        model.detach()
        #expect(try await HomeTestSupport.waitUntil { released == nil }, "the detached model kept the coordinator alive")
    }
}
