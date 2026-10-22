import Foundation
import TallyCanvasAPI
import TallyDomain
import TallyStore
import TallySync

/// Everything an account needs from the platform (perf-app-runtime.md §2.1), injected by the
/// composition root: "Features never import TallyPlatform; the app's composition root injects
/// adapters through protocols" (architecture.md §3.1). Construction is pure. Every member that does
/// I/O is used only from `@concurrent` functions and actors (`LaunchBootstrapper`,
/// `AccountSessionFactory`, `AccountSignOut`), never on the main actor.
public nonisolated struct AccountEnvironment: Sendable {
    /// Resolves the app-private store root (`StoreLocation.privateRoot()`; SEC1-09): `accounts.json`
    /// and every account file except the glance. File-system I/O, so only ever called off the main
    /// actor.
    public let storeRoot: @Sendable () throws -> URL
    /// Resolves the App Group container (`StoreLocation.sharedRoot(appGroupID:)`; SEC1-09), or
    /// `nil` when its entitlement is unavailable. The only file that ever goes here is the glance
    /// — the one thing the widget reads. Defaults to `{ nil }`, which keeps every store on the one
    /// root `storeRoot` resolves (what every test harness and test hook still wants); only the
    /// composition root (`AppEnvironment.live()`) passes a real resolver.
    public let sharedRoot: @Sendable () -> URL?
    /// Canvas tokens (Keychain, `AfterFirstUnlockThisDeviceOnly`).
    public let credentialStore: any CredentialStore
    /// The process's one keyring (`VaultKeyring`: "One instance per process, built at the
    /// composition root"), shared by every sealed store the account opens.
    public let keyring: VaultKeyring
    public let lockPreferences: any AppLockPreferenceStoring
    /// FEAT-2: the local, non-account preference for the one school name the student most recently
    /// searched and found not enabled. Defaulted so every existing call site (tests, previews) is
    /// unaffected; only the composition root injects the real file-backed store.
    public let notEnabledSchoolPreferences: any NotEnabledSchoolPreferenceStoring
    /// FEAT-8 (Idea 7): the local, non-account preference for "Open Canvas links in: App /
    /// Browser". Defaulted so every existing call site (tests, previews) is unaffected; only the
    /// composition root injects the real file-backed store.
    public let canvasLinkPreferences: any CanvasLinkPreferenceStoring
    /// Canvas networking (`URLSessionTransport` in the app): API calls, token refresh and revoke.
    public let transport: any HTTPTransport
    public let notifications: any NotificationScheduling
    /// `WidgetCenter.reloadAllTimelines()` in the app.
    public let reloadWidgets: @Sendable () -> Void
    public let logger: any TallyLogger
    public let clock: any DateProviding
    /// Replaces the live Canvas gateway (test hooks: the bundled replay, or a blocked network).
    /// `nil` in production.
    public let gatewayOverride: (@Sendable (AccountRecord) async -> any CanvasGateway)?
    /// First launch of a fresh install: removes Keychain items an earlier build left behind.
    public let removeLegacyCredentials: @Sendable () -> Void
    /// PAY-07 (M3-B1): the subscription's one gate, which the account's coordinator (refresh, the
    /// glance's `entitledUntil`) and every reminders pass ask. The composition root passes the
    /// app's `EntitlementGate`; ungated by default (tests, previews).
    public let entitlement: any EntitlementGating

    public init(
        storeRoot: @escaping @Sendable () throws -> URL,
        sharedRoot: @escaping @Sendable () -> URL? = { nil },
        credentialStore: any CredentialStore,
        keyring: VaultKeyring,
        lockPreferences: any AppLockPreferenceStoring,
        notEnabledSchoolPreferences: any NotEnabledSchoolPreferenceStoring = InMemoryNotEnabledSchoolPreferenceStore(),
        canvasLinkPreferences: any CanvasLinkPreferenceStoring = InMemoryCanvasLinkPreferenceStore(),
        transport: any HTTPTransport,
        notifications: any NotificationScheduling,
        reloadWidgets: @escaping @Sendable () -> Void = {},
        logger: any TallyLogger = NoOpLogger(),
        clock: any DateProviding = SystemDateProvider(),
        gatewayOverride: (@Sendable (AccountRecord) async -> any CanvasGateway)? = nil,
        removeLegacyCredentials: @escaping @Sendable () -> Void = {},
        entitlement: any EntitlementGating = UngatedEntitlement()
    ) {
        self.storeRoot = storeRoot
        self.sharedRoot = sharedRoot
        self.credentialStore = credentialStore
        self.keyring = keyring
        self.lockPreferences = lockPreferences
        self.notEnabledSchoolPreferences = notEnabledSchoolPreferences
        self.canvasLinkPreferences = canvasLinkPreferences
        self.transport = transport
        self.notifications = notifications
        self.reloadWidgets = reloadWidgets
        self.logger = logger
        self.clock = clock
        self.gatewayOverride = gatewayOverride
        self.removeLegacyCredentials = removeLegacyCredentials
        self.entitlement = entitlement
    }

    /// A copy with the gateway replaced (test hooks).
    public func replacingGateway(_ override: @escaping @Sendable (AccountRecord) async -> any CanvasGateway) -> AccountEnvironment {
        AccountEnvironment(storeRoot: storeRoot, sharedRoot: sharedRoot, credentialStore: credentialStore, keyring: keyring,
                           lockPreferences: lockPreferences, notEnabledSchoolPreferences: notEnabledSchoolPreferences,
                           canvasLinkPreferences: canvasLinkPreferences,
                           transport: transport, notifications: notifications,
                           reloadWidgets: reloadWidgets, logger: logger, clock: clock, gatewayOverride: override,
                           removeLegacyCredentials: removeLegacyCredentials, entitlement: entitlement)
    }

    /// A copy with the transport replaced (test hooks: the stubbed token endpoint).
    public func replacingTransport(_ transport: any HTTPTransport) -> AccountEnvironment {
        AccountEnvironment(storeRoot: storeRoot, sharedRoot: sharedRoot, credentialStore: credentialStore, keyring: keyring,
                           lockPreferences: lockPreferences, notEnabledSchoolPreferences: notEnabledSchoolPreferences,
                           canvasLinkPreferences: canvasLinkPreferences,
                           transport: transport, notifications: notifications,
                           reloadWidgets: reloadWidgets, logger: logger, clock: clock, gatewayOverride: gatewayOverride,
                           removeLegacyCredentials: removeLegacyCredentials, entitlement: entitlement)
    }

    /// A copy with the entitlement gate replaced (PAY-06, M3-B1 O3: a sign-in's coordinator asks
    /// `FirstSyncAllowance` until its first sync has finished).
    public func replacingEntitlement(_ entitlement: any EntitlementGating) -> AccountEnvironment {
        AccountEnvironment(storeRoot: storeRoot, sharedRoot: sharedRoot, credentialStore: credentialStore, keyring: keyring,
                           lockPreferences: lockPreferences, notEnabledSchoolPreferences: notEnabledSchoolPreferences,
                           canvasLinkPreferences: canvasLinkPreferences,
                           transport: transport, notifications: notifications,
                           reloadWidgets: reloadWidgets, logger: logger, clock: clock, gatewayOverride: gatewayOverride,
                           removeLegacyCredentials: removeLegacyCredentials, entitlement: entitlement)
    }

    /// A copy with the clock replaced (MVP-2i: `LaunchTestHooks.fixedNow`, the a11y audit's
    /// determinism fix — pins "now" at the one seam every account path and Sample Data already
    /// read `clock` through, never a shipping-code change: production always passes
    /// `SystemDateProvider()` here and nothing calls this outside `LaunchTestHooks`).
    public func replacingClock(_ clock: any DateProviding) -> AccountEnvironment {
        AccountEnvironment(storeRoot: storeRoot, sharedRoot: sharedRoot, credentialStore: credentialStore, keyring: keyring,
                           lockPreferences: lockPreferences, notEnabledSchoolPreferences: notEnabledSchoolPreferences,
                           canvasLinkPreferences: canvasLinkPreferences,
                           transport: transport, notifications: notifications,
                           reloadWidgets: reloadWidgets, logger: logger, clock: clock, gatewayOverride: gatewayOverride,
                           removeLegacyCredentials: removeLegacyCredentials, entitlement: entitlement)
    }

    /// The account's sealed snapshot store (its `glance` and `snapshot` files). `sharedRoot`
    /// defaults to `nil`, which keeps the glance under `root` with everything else — pass
    /// `environment.sharedRoot()` explicitly wherever SEC1-09's split should actually apply
    /// (every production call site; test call sites that do not care about the split keep the
    /// single-root behaviour by omitting it).
    func snapshotStore(for account: AccountKey, root: URL, sharedRoot: URL? = nil) -> SnapshotStore {
        SnapshotStore(root: root, accountKey: account, sealer: sealer(for: account), sharedRoot: sharedRoot)
    }

    func sealer(for account: AccountKey) -> VaultSealer {
        VaultSealer(account: account.rawValue, keyring: keyring, mayCreateKeys: true)
    }
}

/// The school a sign-in is for (UX-WP-09): the registration's host and client ID, and the name the
/// student picked. Never a person's name.
public nonisolated struct SignInTarget: Sendable, Equatable {
    public let host: String
    public let clientID: String
    public let schoolDisplayName: String

    public init(host: String, clientID: String, schoolDisplayName: String) {
        self.host = host
        self.clientID = clientID
        self.schoolDisplayName = schoolDisplayName
    }
}

/// The refresh-token grant (`TokenRefreshing`) over the institution's token endpoint: public
/// PKCE client, no client secret (security.md WP-SEC-02). `TokenCoordinator` single-flights it
/// and saves the rotated credential before any waiter resumes.
public nonisolated struct CanvasTokenRefresher: TokenRefreshing {
    private let endpoint: TokenEndpoint
    private let transport: any HTTPTransport
    private let clock: any DateProviding

    public init(endpoint: TokenEndpoint, transport: any HTTPTransport, clock: any DateProviding = SystemDateProvider()) {
        self.endpoint = endpoint
        self.transport = transport
        self.clock = clock
    }

    public func refresh(_ credential: CanvasCredential) async throws -> CanvasCredential {
        let response = try await transport.send(endpoint.request(for: .refresh(refreshToken: credential.refreshToken)))
        return try endpoint.credential(from: response, previous: credential, now: clock.now())
    }
}
