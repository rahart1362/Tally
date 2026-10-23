import Foundation
import Testing
import TallyCanvasAPI
import TallyDomain
import TallyStore
import TallyTestSupport
@testable import TallySync

/// WP-SEC-06: the sign-out sequence (security.md §3.2 step 9): best-effort revoke, bump the epoch
/// and cancel refresh, remove notifications, crypto-shred and purge files, delete credentials.
/// Asserts nothing for the account remains: store, ledger, notifications, credentials.
@Suite("SignOutUseCase: revoke, epoch, notifications, purge, credentials", .timeLimit(.minutes(TestTimeBudget.minutes(1))))
struct SignOutUseCaseTests {
    private let host = "canvas.northfield.example"
    private let userID = "4820117"

    /// A trivial `CanvasGateway` so `RefreshCoordinator` can be driven to `.fresh` without the full
    /// Canvas fixture/transport machinery `RefreshCoordinatorTests` uses — sign-out itself never
    /// fetches anything, it only needs a coordinator whose epoch-bump effect is observable.
    private struct StubGateway: CanvasGateway {
        func fetchSnapshot(previous: CanvasSnapshot?, now: Date) async throws -> CanvasSnapshot {
            CanvasSnapshotFixture.make(generation: (previous?.generation ?? 0) + 1, fetchedAt: now)
        }
    }

    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tally-sec06-\(UUID().uuidString)")
        try ProtectedFile.prepareDirectory(url, excludeFromBackup: true)
        return url
    }

    private struct Harness {
        let accountKey: AccountKey
        let root: URL
        let keyring: VaultKeyring
        let snapshotStore: SnapshotStore
        let userStateStore: UserStateStore
        let ledgerStore: SyncLedgerStore
        let credentialStore: InMemoryCredentialStore
        let transport: ReplayTransport
        let notifications: FakeNotificationCenter
        let refreshCoordinator: RefreshCoordinator
    }

    private func makeHarness() async throws -> Harness {
        let accountKey = AccountKey.derive(host: host, userID: userID)
        let root = try tempDirectory()
        let keyring = VaultKeyring(store: InMemoryVaultKeyStore())
        let sealer = VaultSealer(account: accountKey.rawValue, keyring: keyring, mayCreateKeys: true)

        let snapshotStore = SnapshotStore(root: root, accountKey: accountKey, sealer: sealer)
        let userStateStore = UserStateStore(root: root, accountKey: accountKey, sealer: sealer)
        let ledgerStore = SyncLedgerStore(root: root, accountKey: accountKey, sealer: sealer)

        // Seed every store file this account has, so purge has something real to remove.
        try await snapshotStore.commit(CanvasSnapshotFixture.make(generation: 1, accountKey: accountKey), includeGrades: false)
        try await userStateStore.save(UserState(showGradesInGlance: true))
        let seededLedger = SyncLedger(notifications: ["tally.\(accountKey).due.1.due.86400": "sig-a"])
        try await ledgerStore.save(seededLedger)

        let credential = CanvasCredential(host: host, userID: userID, accessToken: "token-1", refreshToken: "refresh-1",
                                          accessTokenExpiresAt: Date().addingTimeInterval(3600))
        let credentialStore = InMemoryCredentialStore(credential)

        let transport = ReplayTransport(routes: [])
        let notifications = FakeNotificationCenter(seeding: [
            PendingReminder(id: "tally.\(accountKey).due.1.due.86400", kind: .due, fireDate: Date(),
                           interruptionLevel: .active, subjectID: "1"),
            PendingReminder(id: "tally.\(accountKey).digest.-.evening.0", kind: .digest, fireDate: Date(),
                           interruptionLevel: .passive, subjectID: "-"),
        ])

        let refreshCoordinator = RefreshCoordinator(gateway: StubGateway(), store: snapshotStore, clock: TestClock(), initialSnapshot: nil)
        _ = await refreshCoordinator.run(trigger: .manual) // drive it to .fresh, so bumpEpochAndCancel's effect is observable

        return Harness(accountKey: accountKey, root: root, keyring: keyring, snapshotStore: snapshotStore,
                       userStateStore: userStateStore, ledgerStore: ledgerStore, credentialStore: credentialStore,
                       transport: transport, notifications: notifications, refreshCoordinator: refreshCoordinator)
    }

    private func signOut(_ harness: Harness) async {
        await SignOutUseCase.signOut(
            accountKey: harness.accountKey, credentialStore: harness.credentialStore, transport: harness.transport,
            tokenEndpoint: TokenEndpoint(host: host, clientID: "tally-ios"), refreshCoordinator: harness.refreshCoordinator,
            ledgerStore: harness.ledgerStore, notifications: harness.notifications, storeRoot: harness.root,
            keyring: harness.keyring)
    }

    @Test func signOutRemovesEverythingForTheAccount() async throws {
        let harness = try await makeHarness()
        guard case .fresh = await harness.refreshCoordinator.currentState else {
            Issue.record("expected the seeded coordinator to be fresh before signing out"); return
        }

        await signOut(harness)

        #expect(await harness.transport.requestCount == 1, "the revoke request was attempted")
        guard case .absent = await harness.snapshotStore.loadSnapshot() else { Issue.record("expected the snapshot to be gone"); return }
        guard case .absent = await harness.userStateStore.load() else { Issue.record("expected user-state to be gone"); return }
        guard case .absent = await harness.ledgerStore.load() else { Issue.record("expected the ledger to be gone"); return }
        #expect(await harness.notifications.pendingIdentifiers().isEmpty, "expected every notification to be cancelled")
        #expect(await harness.credentialStore.load() == nil, "expected the credential to be deleted")
        guard case .noCache = await harness.refreshCoordinator.currentState else {
            Issue.record("expected the epoch bump to reset freshness state to .noCache"); return
        }
    }

    /// EB-26 ("Erase Saved Data"): the same local purge (notifications cancelled, store files
    /// gone) as `signOut`, but the credential survives — this is never a sign-out.
    @Test func eraseSavedDataPurgesFilesAndNotificationsButKeepsTheCredential() async throws {
        let harness = try await makeHarness()

        await SignOutUseCase.eraseSavedData(
            accountKey: harness.accountKey, ledgerStore: harness.ledgerStore, notifications: harness.notifications,
            storeRoot: harness.root, keyring: harness.keyring)

        guard case .absent = await harness.snapshotStore.loadSnapshot() else { Issue.record("expected the snapshot to be gone"); return }
        guard case .absent = await harness.userStateStore.load() else { Issue.record("expected user-state to be gone"); return }
        guard case .absent = await harness.ledgerStore.load() else { Issue.record("expected the ledger to be gone"); return }
        #expect(await harness.notifications.pendingIdentifiers().isEmpty, "expected every notification to be cancelled")
        #expect(await harness.credentialStore.load() != nil, "EB-26: the credential must survive — this is not a sign-out")
    }

    /// Idempotent, like `signOut`: a second call with nothing left to remove does nothing new.
    @Test func eraseSavedDataIsIdempotent() async throws {
        let harness = try await makeHarness()
        await SignOutUseCase.eraseSavedData(
            accountKey: harness.accountKey, ledgerStore: harness.ledgerStore, notifications: harness.notifications,
            storeRoot: harness.root, keyring: harness.keyring)

        await SignOutUseCase.eraseSavedData(
            accountKey: harness.accountKey, ledgerStore: harness.ledgerStore, notifications: harness.notifications,
            storeRoot: harness.root, keyring: harness.keyring)

        guard case .absent = await harness.snapshotStore.loadSnapshot() else { Issue.record("expected the snapshot to stay gone"); return }
        #expect(await harness.credentialStore.load() != nil)
    }

    /// SEC1-02: an access token that has already expired is refreshed once before the revoke
    /// call, rather than sending Canvas a bearer it will just reject; the result is logged.
    @Test func signOutRefreshesAnExpiredTokenBeforeRevoking() async throws {
        let harness = try await makeHarness()
        let expired = CanvasCredential(host: host, userID: userID, accessToken: "access-expired", refreshToken: "refresh-1",
                                       accessTokenExpiresAt: Date().addingTimeInterval(-60))
        try await harness.credentialStore.save(expired)
        let now = Date()

        // The refresh (POST, grant_type=refresh_token) and the revoke (DELETE) both hit the same
        // token endpoint URL, so they are told apart by method.
        await harness.transport.inject(response: HTTPResponse(status: 200, body: Data(
            #"{"access_token":"access-fresh","user":{"id":"\#(userID)"},"refresh_token":"refresh-2","expires_in":3600}"#.utf8)),
            matching: { $0.method == .post })
        await harness.transport.inject(response: HTTPResponse(status: 200), matching: { $0.method == .delete })

        let logger = RecordingLogger()
        let revokeDidFail = await SignOutUseCase.signOut(
            accountKey: harness.accountKey, credentialStore: harness.credentialStore, transport: harness.transport,
            tokenEndpoint: TokenEndpoint(host: host, clientID: "tally-ios"), refreshCoordinator: harness.refreshCoordinator,
            ledgerStore: harness.ledgerStore, notifications: harness.notifications, storeRoot: harness.root,
            keyring: harness.keyring, now: now, logger: logger)

        let requests = await harness.transport.requests()
        #expect(requests.count == 2, "expected one refresh and one revoke request")
        let revoke = try #require(requests.first { $0.method == .delete })
        #expect(revoke.headers["Authorization"] == "Bearer access-fresh", "the revoke must use the refreshed token, not the expired one")
        #expect(logger.events == [.signOutRevoked(ok: true)])
        #expect(await harness.credentialStore.load() == nil)
        #expect(!revokeDidFail, "SEC1-02 optional variant: a successful revoke must never report failure")
    }

    /// SEC1-02: a still-usable access token is revoked directly, with no refresh call first.
    @Test func signOutRevokesDirectlyWhenTheTokenIsStillUsable() async throws {
        let harness = try await makeHarness()
        let logger = RecordingLogger()
        await harness.transport.inject(response: HTTPResponse(status: 200), matching: { $0.method == .delete })

        let revokeDidFail = await SignOutUseCase.signOut(
            accountKey: harness.accountKey, credentialStore: harness.credentialStore, transport: harness.transport,
            tokenEndpoint: TokenEndpoint(host: host, clientID: "tally-ios"), refreshCoordinator: harness.refreshCoordinator,
            ledgerStore: harness.ledgerStore, notifications: harness.notifications, storeRoot: harness.root,
            keyring: harness.keyring, logger: logger)

        #expect(await harness.transport.requestCount == 1, "no refresh call for a token that is still usable")
        #expect(logger.events == [.signOutRevoked(ok: true)])
        #expect(!revokeDidFail, "SEC1-02 optional variant: a successful revoke must never report failure")
    }

    /// SEC1-02 optional variant (security.md §3.2 step 9.4): the condition behind the one-time
    /// "we couldn't confirm Canvas revoked this" notice — `true` only when a credential existed
    /// and the revoke did not end in a 2xx (offline, a transport error or any other status);
    /// `false` both on a successful revoke (the two tests above) and when there was nothing to
    /// revoke at all, so a repeat sign-out can never resurface the notice.
    @Test func signOutReportsAFailedRevokeForTheOptionalNotice() async throws {
        let harness = try await makeHarness()
        await harness.transport.inject(response: HTTPResponse(status: 500), matching: { $0.method == .delete })

        let revokeDidFail = await SignOutUseCase.signOut(
            accountKey: harness.accountKey, credentialStore: harness.credentialStore, transport: harness.transport,
            tokenEndpoint: TokenEndpoint(host: host, clientID: "tally-ios"), refreshCoordinator: harness.refreshCoordinator,
            ledgerStore: harness.ledgerStore, notifications: harness.notifications, storeRoot: harness.root,
            keyring: harness.keyring)
        #expect(revokeDidFail, "a non-2xx revoke must report failure")

        // Idempotent repeat: no credential left, so nothing was attempted — never a false alarm.
        let nothingToRevoke = await SignOutUseCase.signOut(
            accountKey: harness.accountKey, credentialStore: harness.credentialStore, transport: harness.transport,
            tokenEndpoint: TokenEndpoint(host: host, clientID: "tally-ios"), refreshCoordinator: harness.refreshCoordinator,
            ledgerStore: harness.ledgerStore, notifications: harness.notifications, storeRoot: harness.root,
            keyring: harness.keyring)
        #expect(!nothingToRevoke, "nothing left to revoke must never report failure")
    }

    @Test func signOutTwiceIsIdempotent() async throws {
        let harness = try await makeHarness()
        await signOut(harness)
        let requestCountAfterFirst = await harness.transport.requestCount

        // A second call: no credential left to revoke with, nothing left to cancel or purge.
        await signOut(harness)

        #expect(await harness.transport.requestCount == requestCountAfterFirst, "no second revoke attempt without a credential")
        guard case .absent = await harness.snapshotStore.loadSnapshot() else { Issue.record("expected the snapshot to still be gone"); return }
        guard case .absent = await harness.ledgerStore.load() else { Issue.record("expected the ledger to still be gone"); return }
        #expect(await harness.notifications.pendingIdentifiers().isEmpty)
        #expect(await harness.credentialStore.load() == nil)
    }
}
