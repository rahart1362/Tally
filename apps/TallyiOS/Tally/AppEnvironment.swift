import Foundation
import TallyCanvasAPI
import TallyDomain
import TallyFeatures
import TallyPlatform
import TallyStore

/// The composition root's object graph (architecture.md §3.1). `live()` performs pure construction
/// only — no file reads, no Keychain calls, no network — so it is safe to call synchronously from
/// `TallyApp.init` (perf-app-runtime.md §2.4 L1, < 5 ms). Adapters are injected as protocols;
/// `TallyFeatures` never imports `TallyPlatform` directly (architecture.md §3.1: "Features never
/// import TallyPlatform; the app's composition root injects adapters through protocols").
///
/// - `accountEnvironment`: the platform services an account needs (Keychain credential and vault
///   keys, the Keychain app-lock setting, the ephemeral `URLSession` transport, notifications,
///   widget reloads, the App Group store root). Only `@concurrent` functions and actors use them.
/// - `accountRuntime` (perf-app-runtime.md §7 step 7) owns the signed-in account's one
///   `RefreshCoordinator`, shared by the Home (through `appModel`) and `.backgroundTask`. It
///   resolves the account lazily, off the main actor (`AccountSessionFactory.activeCoordinator`:
///   `accounts.json`, then the cached snapshot, decoded once).
/// - `appModel` is the one `AppModel` the whole app shares; its `launch()` runs the launch
///   bootstrapper (perf-app-runtime.md §7 step 8).
struct AppEnvironment {
    let logger: any TallyPlatformLogger
    let accountRuntime: AccountRuntime
    let appModel: AppModel
    /// UX-WP-08/09: the sign-in pages' services (the real `ASWebAuthenticationSession` presenter and
    /// token exchange; the institution search and enablement list are still unavailable, GL-02).
    let signIn: SignInServices

    /// `@MainActor`: `WebAuthPresenter` is main-actor isolated (it drives
    /// `ASWebAuthenticationSession`, which must run on the main thread), and `AppModel` is
    /// `@MainActor @Observable`. `TallyApp` conforms to `App`, itself a main-actor protocol.
    @MainActor
    static func live() -> AppEnvironment {
        // One `os.Logger` adapter for the platform's own events and for TallyCore's logging port
        // (plan 06 A8: `OSLogPlatformLogger` conforms to both).
        let logger = OSLogPlatformLogger()
        let transport = URLSessionTransport()
        let appGroupID = StoreLocation.appGroupID
        // No explicit Keychain access groups yet: an explicit group fails with
        // errSecMissingEntitlement under CI's ad-hoc signing (KeychainVaultKeyStoreTests' known
        // issue), so every key lives in the app's default group until a real Team ID exists
        // (GL-02). The widget's glance key needs the App Group group then (M2-C2).
        var accountEnvironment = AccountEnvironment(
            storeRoot: { try StoreLocation.root(appGroupID: appGroupID) },
            // The legacy mock item is removed on a fresh install's first launch instead
            // (`removeLegacyCredentials`), off the main actor.
            credentialStore: KeychainCredentialStore(removeLegacyMockItemOnInit: false),
            keyring: VaultKeyring(store: KeychainVaultKeyStore()),
            lockPreferences: KeychainAppLockPreferenceStore(),
            transport: transport,
            notifications: UNNotificationScheduler(),
            reloadWidgets: { WidgetReloader().reloadAllTimelines() },
            logger: logger,
            clock: SystemDateProvider(),
            removeLegacyCredentials: { _ = KeychainCredentialStore() })
        var signIn = SignInServices(webAuthPresenter: WebAuthPresenter(),
                                    makeTokenExchange: SignInServices.canvasTokenExchange(transport: transport))
        var authenticator: any AppLockAuthenticating = LocalAuthenticationAdapter()

        #if true || TALLY_TEST_HOOKS
        // UI tests only (LaunchTestHooks); never compiled into a shipping Release build.
        let hooks = LaunchTestHooks(arguments: ProcessInfo.processInfo.arguments)
        if hooks.isActive {
            accountEnvironment = hooks.configure(accountEnvironment)
            signIn = hooks.configure(signIn)
            authenticator = hooks.configure(authenticator)
        }
        #endif

        let resolvedEnvironment = accountEnvironment
        let accountRuntime = AccountRuntime(resolve: { await AccountSessionFactory.activeCoordinator(resolvedEnvironment) })
        let lock = AppLockModel(authenticator: authenticator, preferences: accountEnvironment.lockPreferences)
        let appModel = AppModel(accountRuntime: accountRuntime, logger: logger, accountEnvironment: accountEnvironment,
                                lock: lock)
        #if true || TALLY_TEST_HOOKS
        if hooks.isActive { appModel.testHooks = hooks }
        #endif
        return AppEnvironment(logger: logger, accountRuntime: accountRuntime, appModel: appModel, signIn: signIn)
    }
}
