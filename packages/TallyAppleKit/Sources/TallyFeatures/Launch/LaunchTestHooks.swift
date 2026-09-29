#if DEBUG || TALLY_TEST_HOOKS
import Foundation
import Observation
import Synchronization
import TallyCanvasAPI
import TallyDomain
import TallySampleFixtures
import TallyStore
import TallySync

/// UI-test hooks for the account lifecycle (plan 07 M2-C1: a seeded signed-in launch, a
/// replay-backed demo sign-in, a blocked network, a scripted device authenticator). Launch
/// arguments, `-TallyTestHooks.<name> <value>`, read from the process's arguments (no
/// `UserDefaults` read at launch).
///
/// **Never in a shipping build.** This file compiles only under `DEBUG`, or under the explicit
/// `TALLY_TEST_HOOKS` condition that `make ios-perf` sets for its Release test build (the launch
/// budget is measured in Release, over a seeded account). CI's "shipping binaries" step builds the
/// Release app for the device with neither and fails if any binary in it contains the
/// `TallyTestHooks.` argument prefix.
///
/// Every value it writes is synthetic: the flagship persona from the bundled fixtures, and
/// placeholder tokens that no server issued.
public nonisolated struct LaunchTestHooks: Sendable {
    /// The launch-argument names. All share the `TallyTestHooks.` prefix the Release gate looks for.
    public nonisolated enum Key {
        public static let prefix = "TallyTestHooks."
        /// `flagship`: erase everything, then write a sealed flagship store, its `accounts.json`
        /// record and a synthetic credential, before the launch reads anything.
        public static let seed = "TallyTestHooks.seed"
        /// `YES`: erase every account, key, credential and the app-lock setting.
        public static let reset = "TallyTestHooks.reset"
        /// `on` / `off`: store the app-lock setting before the launch reads it.
        public static let appLock = "TallyTestHooks.appLock"
        /// An `AppLockPolicy.GracePeriod` raw value (`immediately`, `oneMinute`, …).
        public static let appLockGrace = "TallyTestHooks.appLockGrace"
        /// `success`, `cancel`, `lockout`, `passcodeNotSet` or `biometryUnavailable`, or a
        /// comma-separated sequence of them (the last repeats): a scripted device authenticator in
        /// place of `LAContext`.
        public static let deviceAuth = "TallyTestHooks.deviceAuth"
        /// `YES`: an account's Canvas gateway is the bundled flagship replay (no network).
        public static let replayAccounts = "TallyTestHooks.replayAccounts"
        /// `YES`: an account's Canvas gateway never answers (no network at all), and a banner
        /// reports how many requests were made before the first cached paint.
        public static let blockNetwork = "TallyTestHooks.blockNetwork"
        /// `YES`: sign-in against a stubbed token endpoint and the flagship replay (the demo school
        /// is the persona's host, typed as an address in school search).
        public static let demoSignIn = "TallyTestHooks.demoSignIn"
        /// `YES`: a sign-out button on the signed-in Home (Settings' own button is M3-A's).
        public static let signOutButton = "TallyTestHooks.signOutButton"
        /// `YES`: the window shows an empty view instead of `RootView`, whose task ends
        /// `Launch.ToTask`; nothing is read. `TallyPerfUITests` measures the phase's floor with it
        /// (process, scene and first frame on this simulator, with no app content).
        public static let emptyScene = "TallyTestHooks.emptyScene"
        /// `stale` (an hour ago) or `recent` (a minute ago): before the launch reads anything, the
        /// active account's refresh record says its last refresh was attempted then (O5). The launch
        /// refresh runs after a stale attempt and waits out `minAutoRefreshInterval` after a recent one.
        public static let lastRefreshAttempt = "TallyTestHooks.lastRefreshAttempt"
    }

    /// The demo school's registration (the flagship persona's host; a synthetic client ID).
    public static let demoClientID = "10000000000042"
    public static let demoSchoolName = "Northfield State University"

    public let seed: String?
    public let reset: Bool
    public let appLock: Bool?
    public let appLockGrace: AppLockPolicy.GracePeriod?
    public let deviceAuth: [AppLockPolicy.AuthResult]?
    public let replayAccounts: Bool
    public let blockNetwork: Bool
    public let demoSignIn: Bool
    public let signOutButton: Bool
    public let emptyScene: Bool
    public let lastRefreshAttempt: String?

    /// Parses `-TallyTestHooks.<name> <value>` pairs; anything else is ignored.
    public init(arguments: [String]) {
        var values: [String: String] = [:]
        var index = arguments.startIndex
        while index < arguments.endIndex {
            let argument = arguments[index]
            let next = arguments.index(after: index)
            if argument.hasPrefix("-\(Key.prefix)"), next < arguments.endIndex {
                values[String(argument.dropFirst())] = arguments[next]
                index = arguments.index(after: next)
            } else {
                index = next
            }
        }
        func flag(_ key: String) -> Bool { ["YES", "yes", "true", "1"].contains(values[key] ?? "") }
        seed = values[Key.seed]
        reset = flag(Key.reset)
        appLock = values[Key.appLock].map { $0 == "on" }
        appLockGrace = values[Key.appLockGrace].flatMap(AppLockPolicy.GracePeriod.init(rawValue:))
        deviceAuth = values[Key.deviceAuth].map { $0.split(separator: ",").compactMap { Self.authResult(String($0)) } }
            .flatMap { $0.isEmpty ? nil : $0 }
        replayAccounts = flag(Key.replayAccounts)
        blockNetwork = flag(Key.blockNetwork)
        demoSignIn = flag(Key.demoSignIn)
        signOutButton = flag(Key.signOutButton)
        emptyScene = flag(Key.emptyScene)
        lastRefreshAttempt = values[Key.lastRefreshAttempt]
    }

    /// Whether any hook is on. `AppEnvironment` keeps no hooks object when none is.
    public var isActive: Bool {
        seed != nil || reset || appLock != nil || deviceAuth != nil || replayAccounts || blockNetwork || demoSignIn
            || signOutButton || emptyScene || lastRefreshAttempt != nil
    }

    private static func authResult(_ name: String) -> AppLockPolicy.AuthResult? {
        switch name {
        case "success": .success(via: .biometric)
        case "cancel": .failedOrCancelled
        case "lockout": .biometryLockout
        case "passcodeNotSet": .passcodeNotSet
        case "biometryUnavailable": .biometryUnavailable
        default: nil
        }
    }

    // MARK: - Overrides (the composition root applies them before building the app model)

    /// The account's gateway and transport: a blocked network, or the flagship replay behind a
    /// stubbed token endpoint.
    public func configure(_ environment: AccountEnvironment) -> AccountEnvironment {
        var configured = environment
        if demoSignIn { configured = configured.replacingTransport(DemoCanvasTransport()) }
        if blockNetwork {
            configured = configured.replacingGateway { _ in BlockedNetworkGateway() }
        } else if replayAccounts || demoSignIn {
            let clock = environment.clock
            configured = configured.replacingGateway { account in ReplayAccountGateway(account: account.accountKey, clock: clock) }
        }
        return configured
    }

    /// The demo school, a web-auth sheet that answers at once, and the stubbed token endpoint.
    @MainActor
    public func configure(_ services: SignInServices) -> SignInServices {
        guard demoSignIn else { return services }
        var configured = services
        let host = SampleFixtures.demoHost
        configured.registry = ClientRegistry([ClientRegistration(host: host, clientID: Self.demoClientID)])
        configured.webAuthPresenter = DemoWebAuthPresenter()
        configured.makeTokenExchange = SignInServices.canvasTokenExchange(transport: DemoCanvasTransport())
        return configured
    }

    public func configure(_ authenticator: any AppLockAuthenticating) -> any AppLockAuthenticating {
        guard let deviceAuth else { return authenticator }
        return ScriptedAppLockAuthenticator(results: deviceAuth)
    }

    // MARK: - Before the launch reads anything

    /// Reset, seed and the app-lock setting, off the main actor. The fresh-install reconcile runs
    /// first, so it can never shred the keys of a store seeded on the simulator's first launch.
    @concurrent
    public func prepareLaunch(_ environment: AccountEnvironment) async {
        guard reset || seed != nil || appLock != nil || lastRefreshAttempt != nil,
              let root = try? environment.storeRoot() else { return }
        await LaunchBootstrapper.reconcileInstallIfNeeded(root: root, environment: environment)
        if reset || seed != nil { await Self.eraseEverything(root: root, environment: environment) }
        if seed == "flagship" { await Self.seedFlagship(root: root, environment: environment) }
        if let appLock {
            try? await environment.lockPreferences.save(AppLockPreference(isEnabled: appLock,
                                                                          gracePeriod: appLockGrace ?? .default))
        }
        if let lastRefreshAttempt { Self.writeLastRefreshAttempt(lastRefreshAttempt, root: root, environment: environment) }
    }

    /// The `lastRefreshAttempt` hook: a refresh record whose last attempt (a success) was an hour or
    /// a minute ago, for the active account.
    static func writeLastRefreshAttempt(_ value: String, root: URL, environment: AccountEnvironment) {
        guard let account = AccountDirectoryStore(root: root).activeAccount() else { return }
        let ago: TimeInterval = value == "recent" ? 60 : 3_600
        let attemptedAt = environment.clock.now().addingTimeInterval(-ago)
        var record = RefreshRecord()
        record.began(.launch, at: attemptedAt)
        record.succeeded(dataFetchedAt: attemptedAt)
        try? RefreshStateStore(root: root, accountKey: account.accountKey, sealer: environment.sealer(for: account.accountKey))
            .save(record)
    }

    @concurrent
    static func eraseEverything(root: URL, environment: AccountEnvironment) async {
        let directory = AccountDirectoryStore(root: root)
        if case .loaded(let accounts) = directory.load() {
            for account in accounts.accounts {
                try? AccountPurger.purge(accountKey: account.accountKey, root: root, keyring: environment.keyring)
            }
        }
        ProtectedFile.remove(directory.fileURL)
        try? environment.keyring.shredEverything()
        await environment.credentialStore.delete()
        await environment.lockPreferences.reset()
    }

    /// A sealed flagship store, exactly as a first sync would leave it: the bundled replay through
    /// the production pipeline, committed through `SnapshotStore` (snapshot, then glance).
    @concurrent
    static func seedFlagship(root: URL, environment: AccountEnvironment) async {
        let now = environment.clock.now()
        guard let gateway = try? await SampleDataCanvasGateway.make(dateProvider: environment.clock),
              let fetched = try? await gateway.fetchSnapshot(previous: nil, now: now) else { return }
        let record = AccountRecord.derived(host: fetched.host, canvasUserID: fetched.profile.id.rawValue,
                                           clientID: demoClientID, displayLabel: demoSchoolName)
        let credential = CanvasCredential(host: record.host, userID: record.canvasUserID,
                                          accessToken: "tally-test-hooks-access", refreshToken: "tally-test-hooks-refresh",
                                          accessTokenExpiresAt: .distantFuture)
        try? await environment.credentialStore.save(credential)
        try? AccountDirectoryStore(root: root).activate(record)
        let store = environment.snapshotStore(for: record.accountKey, root: root)
        _ = try? await store.commit(fetched.restamped(accountKey: record.accountKey, generation: 1), includeGrades: false)
    }
}

extension SampleFixtures {
    /// The flagship persona's Canvas host (`CanvasFixtures/manifest.json`): the demo school.
    nonisolated static let demoHost = "canvas.northfield.example"
}

extension CanvasSnapshot {
    /// The same value under another account key and generation (test hooks: the flagship replay
    /// stands in for an account's Canvas).
    nonisolated func restamped(accountKey: AccountKey, generation: UInt64) -> CanvasSnapshot {
        CanvasSnapshot(generation: generation, accountKey: accountKey, host: host, fetchedAt: fetchedAt, profile: profile,
                       courses: courses, groups: groups, gradingPeriods: gradingPeriods, planner: planner, events: events,
                       announcements: announcements, courseColors: courseColors, sections: sections)
    }
}

// MARK: - Stand-ins

/// The account's Canvas as the bundled flagship replay (the sample-mode pipeline, no network),
/// stamped with the account's key. The replay is built on the first fetch.
actor ReplayAccountGateway: CanvasGateway {
    private let account: AccountKey
    private let clock: any DateProviding
    private var base: SampleDataCanvasGateway?

    init(account: AccountKey, clock: any DateProviding) {
        self.account = account
        self.clock = clock
    }

    func fetchSnapshot(previous: CanvasSnapshot?, now: Date) async throws -> CanvasSnapshot {
        let gateway: SampleDataCanvasGateway
        if let base {
            gateway = base
        } else {
            gateway = try await SampleDataCanvasGateway.make(dateProvider: clock)
            base = gateway
        }
        let fetched = try await gateway.fetchSnapshot(previous: previous, now: now)
        return fetched.restamped(accountKey: account, generation: fetched.generation)
    }
}

/// No network at all: every fetch is recorded (`LaunchProbe`) and then never answers; the
/// coordinator's own ceiling ends it (`TallyConfig.foregroundHardCeiling`) and it reports offline.
nonisolated struct BlockedNetworkGateway: CanvasGateway {
    func fetchSnapshot(previous: CanvasSnapshot?, now: Date) async throws -> CanvasSnapshot {
        let requestedAt = ContinuousClock.now
        await LaunchProbe.shared.networkRequested(at: requestedAt)
        try await Task.sleep(for: TallyConfig.foregroundHardCeiling * 2)
        throw RefreshFailure.offline
    }
}

/// The stubbed token endpoint (`POST /login/oauth2/token`: a synthetic token for the flagship
/// persona's user) and revoke (`DELETE`: 200). Anything else is a 404: account data comes from the
/// replay gateway, never from here.
nonisolated struct DemoCanvasTransport: HTTPTransport {
    func send(_ request: HTTPRequest) async throws(TransportError) -> HTTPResponse {
        guard request.url.path == "/login/oauth2/token" else { return HTTPResponse(status: 404) }
        switch request.method {
        case .post:
            let body = #"{"access_token":"tally-demo-access","refresh_token":"tally-demo-refresh","expires_in":3600,"user":{"id":4820117}}"#
            return HTTPResponse(status: 200, headers: HTTPHeaders(["Content-Type": "application/json"]), body: Data(body.utf8))
        case .delete:
            return HTTPResponse(status: 200)
        case .get:
            return HTTPResponse(status: 404)
        }
    }
}

/// `ASWebAuthenticationSession` stand-in: answers at once with the registered callback, an
/// authorization code, and the request's own `state` (so `OAuthCallback` validates it as usual).
nonisolated struct DemoWebAuthPresenter: WebAuthPresenting {
    @MainActor
    func authenticate(url: URL, callbackHost: String, callbackPath: String, ephemeral: Bool) async throws -> URL {
        let state = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "state" }?.value
        var callback = URLComponents()
        callback.scheme = "https"
        callback.host = callbackHost
        callback.path = callbackPath
        callback.queryItems = [URLQueryItem(name: "code", value: "tally-demo-authorization-code"),
                               URLQueryItem(name: "state", value: state)]
        guard let callbackURL = callback.url else { throw WebAuthError.other }
        return callbackURL
    }
}

/// A device authenticator that answers `results` in order, the last one repeating (`LAContext`
/// stand-in).
nonisolated final class ScriptedAppLockAuthenticator: AppLockAuthenticating {
    private let queue: Mutex<[AppLockPolicy.AuthResult]>

    init(results: [AppLockPolicy.AuthResult]) {
        queue = Mutex(results)
    }

    func authenticate(reason: String) async -> AppLockPolicy.AuthResult {
        queue.withLock { queue in
            guard let next = queue.first else { return .failedOrCancelled }
            if queue.count > 1 { queue.removeFirst() }
            return next
        }
    }

    func evaluatedPolicyDomainState() async -> Data? { nil }

    func availability() async -> AppLockAvailability {
        queue.withLock { $0.first } == .passcodeNotSet ? .passcodeNotSet : .available(.faceID)
    }
}

/// With `blockNetwork`: when the first cached frame was painted, and when each Canvas request was
/// made, so the UI test can check that no request came before the paint.
@MainActor
@Observable
public final class LaunchProbe {
    /// Explicit and nonisolated (plan 06 A2): see `AppModel`'s deinit.
    nonisolated deinit {}

    public static let shared = LaunchProbe()

    public private(set) var paintedAt: ContinuousClock.Instant?
    public private(set) var requestInstants: [ContinuousClock.Instant] = []

    /// Requests made before the first cached paint (all of them, while nothing is painted).
    public var requestsBeforePaint: Int {
        guard let paintedAt else { return requestInstants.count }
        return requestInstants.count { $0 < paintedAt }
    }

    func painted() {
        if paintedAt == nil { paintedAt = .now }
    }

    func networkRequested(at instant: ContinuousClock.Instant) {
        requestInstants.append(instant)
    }
}
#endif
