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
}
