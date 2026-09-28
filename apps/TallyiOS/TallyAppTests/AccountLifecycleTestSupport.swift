#if DEBUG
import Foundation
import Synchronization
import TallyCanvasAPI
import TallyDomain
import TallyStore
import TallySync
import TallyTestSupport
@testable import TallyFeatures

/// DEBUG only, like every suite that uses it: it stamps snapshots through the DEBUG/test-hook
/// `CanvasSnapshot.restamped(accountKey:generation:)`, and the Release test build (`make ios-perf`)
/// compiles no DEBUG test code.
///
/// Shared by the launch, sign-in, sign-out and lock suites (plan 07 M2-C1): a complete
/// `AccountEnvironment` over a temporary store root and in-memory ports, with every platform
/// side effect recorded. Every value is synthetic (the flagship fixtures, placeholder tokens).
struct AccountHarness: Sendable {
    let root: URL
    let credentials: InMemoryCredentialStore
    let vaultKeys: InMemoryVaultKeyStore
    let keyring: VaultKeyring
    let lockPreferences: InMemoryAppLockPreferenceStore
    let transport: RecordingTransport
    let notifications: FakeNotificationCenter
    let widgetReloads: CallCounter
    let environment: AccountEnvironment

    /// - Parameter gateway: the account's Canvas; `nil` makes one that serves the flagship snapshot.
    init(gateway: (@Sendable (AccountRecord) async -> any CanvasGateway)? = nil,
         lock: AppLockPreference? = nil) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("tally-lifecycle-\(UUID().uuidString)")
        try ProtectedFile.prepareDirectory(root, excludeFromBackup: true)
        credentials = InMemoryCredentialStore()
        vaultKeys = InMemoryVaultKeyStore()
        keyring = VaultKeyring(store: vaultKeys)
        lockPreferences = InMemoryAppLockPreferenceStore(lock)
        transport = RecordingTransport()
        notifications = FakeNotificationCenter()
        let widgetReloads = CallCounter()
        self.widgetReloads = widgetReloads
        let root = self.root
        environment = AccountEnvironment(
            storeRoot: { root }, credentialStore: credentials, keyring: keyring, lockPreferences: lockPreferences,
            transport: transport, notifications: notifications, reloadWidgets: { widgetReloads.increment() },
            gatewayOverride: gateway ?? { account in
                FlagshipAccountGateway(account: account.accountKey)
            })
    }

    static let host = "canvas.northfield.example"
    static let target = SignInTarget(host: host, clientID: "10000000000042", schoolDisplayName: "Northfield State University")
    /// A Canvas user ID of this harness's own, so its account key is unique: suites run in
    /// parallel, and the DEBUG live-instance counter is read per account.
    let userID = "4820117-\(UUID().uuidString)"
    var credential: CanvasCredential {
        CanvasCredential(host: Self.host, userID: userID, accessToken: "test-access", refreshToken: "test-refresh",
                         accessTokenExpiresAt: .distantFuture)
    }
    var record: AccountRecord {
        AccountRecord.derived(host: Self.host, canvasUserID: userID, clientID: Self.target.clientID,
                              displayLabel: Self.target.schoolDisplayName)
    }
    var account: AccountKey { record.accountKey }

    /// A signed-in account on disk, as a finished first sync leaves it: the credential, the
    /// `accounts.json` record and a committed flagship snapshot (generation 1) with its glance.
    /// The snapshot value goes out of scope here, so the launch under test owns the only decode.
    func seedSignedInAccount() async throws {
        try await credentials.save(credential)
        try AccountDirectoryStore(root: root).activate(record)
        let snapshot = try await FlagshipAccountGateway.flagship(account: account)
        let store = environment.snapshotStore(for: account, root: root)
        try await store.commit(snapshot, includeGrades: false)
        // The first launch's reconcile would shred these keys; this store was written by an
        // "earlier launch" of the same install.
        try ProtectedFile.atomicWrite(Data(), to: StoreLayout(root: root, accountKey: account).installSentinel,
                                      excludeFromBackup: true)
    }

    var accountDirectory: URL {
        StoreLayout(root: root, accountKey: account).accountDirectory
    }
}

/// The flagship persona's snapshot, fetched through the production pipeline over the source-tree
/// replay (`FlagshipSnapshotHarness`) and stamped with the account's key, so the DEBUG live-instance
/// counter counts it under that account. Counts fetches; an optional per-fetch hook runs first.
actor FlagshipAccountGateway: CanvasGateway {
    private let account: AccountKey
    private let onFetch: (@Sendable () async throws -> Void)?
    private(set) var fetches = 0

    init(account: AccountKey, onFetch: (@Sendable () async throws -> Void)? = nil) {
        self.account = account
        self.onFetch = onFetch
    }

    func fetchSnapshot(previous: CanvasSnapshot?, now: Date) async throws -> CanvasSnapshot {
        fetches += 1
        try await onFetch?()
        return try await Self.flagship(account: account, generation: (previous?.generation ?? 0) + 1)
    }

    static func flagship(account: AccountKey, generation: UInt64 = 1) async throws -> CanvasSnapshot {
        try await FlagshipSnapshotHarness.fetchSnapshot(now: Date()).restamped(accountKey: account, generation: generation)
    }
}

/// Records every request; answers the token endpoint (`POST`: a synthetic token; `DELETE`, the
/// sign-out revoke: 200) and 404s anything else.
final class RecordingTransport: HTTPTransport {
    private let log = Mutex<[HTTPRequest]>([])

    var requests: [HTTPRequest] { log.withLock { $0 } }

    func send(_ request: HTTPRequest) async throws(TransportError) -> HTTPResponse {
        log.withLock { $0.append(request) }
        guard request.url.path == "/login/oauth2/token" else { return HTTPResponse(status: 404) }
        if request.method == .delete { return HTTPResponse(status: 200) }
        let body = #"{"access_token":"test-access","refresh_token":"test-refresh","expires_in":3600,"user":{"id":4820117}}"#
        return HTTPResponse(status: 200, body: Data(body.utf8))
    }
}

final class CallCounter: Sendable {
    private let count = Mutex(0)
    var value: Int { count.withLock { $0 } }
    func increment() { count.withLock { $0 += 1 } }
}

/// An authenticator that answers with the queued results in order (the last one repeats), and
/// counts its attempts.
final class ScriptedAuthenticator: AppLockAuthenticating {
    private let state: Mutex<(results: [AppLockPolicy.AuthResult], attempts: Int)>
    private let available: AppLockAvailability

    init(_ results: [AppLockPolicy.AuthResult], availability: AppLockAvailability = .available(.faceID)) {
        state = Mutex((results, 0))
        available = availability
    }

    var attempts: Int { state.withLock { $0.attempts } }

    func authenticate(reason: String) async -> AppLockPolicy.AuthResult {
        state.withLock { state in
            state.attempts += 1
            guard let first = state.results.first else { return .failedOrCancelled }
            if state.results.count > 1 { state.results.removeFirst() }
            return first
        }
    }

    func evaluatedPolicyDomainState() async -> Data? { nil }
    func availability() async -> AppLockAvailability { available }
}

/// Holds every `save` until `open()`, so a test can act while a sign-in's provisioning is in
/// flight (between S2 and the Keychain write).
final class GatedCredentialStore: CredentialStore {
    private struct State {
        var isOpen = false
        var waiting: [CheckedContinuation<Void, Never>] = []
        var saveStarted = false
        var saveFinished = false
    }

    private let base: InMemoryCredentialStore
    private let state = Mutex(State())

    init(base: InMemoryCredentialStore) {
        self.base = base
    }

    var saveStarted: Bool { state.withLock { $0.saveStarted } }
    var saveFinished: Bool { state.withLock { $0.saveFinished } }

    func load() async -> CanvasCredential? { await base.load() }

    func save(_ credential: CanvasCredential) async throws {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumeNow = state.withLock { state -> Bool in
                state.saveStarted = true
                if state.isOpen { return true }
                state.waiting.append(continuation)
                return false
            }
            if resumeNow { continuation.resume() }
        }
        try await base.save(credential)
        state.withLock { $0.saveFinished = true }
    }

    func delete() async { await base.delete() }

    func open() {
        let waiting = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.isOpen = true
            let waiting = state.waiting
            state.waiting.removeAll()
            return waiting
        }
        for continuation in waiting { continuation.resume() }
    }
}
#endif
