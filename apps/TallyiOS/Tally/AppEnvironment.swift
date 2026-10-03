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
/// - PAY-03/04/07 (M3-B1): the subscription engine over StoreKit (`StoreKitEntitlementSource`), the
///   Keychain record and `BGTaskScheduler`, with the app's one `EntitlementGate`, which the account
///   environment hands to every coordinator and reminders pass. `TallyApp.init` starts it.
struct AppEnvironment {
    let logger: any TallyPlatformLogger
    let accountRuntime: AccountRuntime
    let appModel: AppModel
    /// UX-WP-08/09: the sign-in pages' services (the real `ASWebAuthenticationSession` presenter and
    /// token exchange; the institution search and enablement list are still unavailable, GL-02).
    let signIn: SignInServices
    /// M3-D2: exposed so `TallyApp.init` can register `MarkDoneIntentBridge.handler` directly over
    /// this process's one `accountEnvironment` and `accountRuntime`, without needing `AppModel`'s
    /// (private) copy or a UI session to have attached anything first.
    let accountEnvironment: AccountEnvironment

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
        // PAY-07: the one entitlement gate. Enforcement follows `SubscriptionConfig.isGatingEnforced`
        // (on since M3-B2 shipped the paywall).
        let entitlementGate = EntitlementGate(clock: SystemDateProvider())
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
            removeLegacyCredentials: { _ = KeychainCredentialStore() },
            entitlement: entitlementGate)
        var signIn = SignInServices(webAuthPresenter: WebAuthPresenter(),
                                    makeTokenExchange: SignInServices.canvasTokenExchange(transport: transport))
        var authenticator: any AppLockAuthenticating = LocalAuthenticationAdapter()

        #if DEBUG || TALLY_TEST_HOOKS
        // UI tests only (LaunchTestHooks); never compiled into a shipping Release build.
        let hooks = LaunchTestHooks(arguments: ProcessInfo.processInfo.arguments)
        if hooks.isActive {
            accountEnvironment = hooks.configure(accountEnvironment)
            signIn = hooks.configure(signIn)
            authenticator = hooks.configure(authenticator)
        }
        #endif

        let resolvedEnvironment = accountEnvironment
        // O5 (PERF-L): the launch reads the account's refresh record for its first paint and leaves
        // it here, so the account's coordinator starts from it without reading the file again.
        let launchRecords = LaunchRecordHandoff()
        let accountRuntime = AccountRuntime(resolve: {
            await AccountSessionFactory.activeCoordinator(resolvedEnvironment, launchRecords: launchRecords)
        })
        let lock = AppLockModel(authenticator: authenticator, preferences: accountEnvironment.lockPreferences)
        // PAY-01: the product IDs derive from the bundle ID (`Identity.xcconfig`).
        let products = SubscriptionProducts(bundleID: Bundle.main.bundleIdentifier ?? "dev.tally-app.tally")
        var source = entitlementSource(products: products)
        var appStore = Self.storefront(products: products)
        #if DEBUG || TALLY_TEST_HOOKS
        // M3-B2: UI tests' test-only entitlement and App Store (`SubscriptionTestHooks`); never compiled
        // into a shipping Release build.
        let subscriptionHooks = SubscriptionTestHooks(arguments: ProcessInfo.processInfo.arguments)
        if let hookedSource = subscriptionHooks.source(products: products), let hookedStorefront = subscriptionHooks.storefront() {
            source = hookedSource
            appStore = hookedStorefront
        }
        #endif
        let subscription = SubscriptionModel(engine: SubscriptionEngine(
            source: source, records: KeychainEntitlementStore(),
            gate: entitlementGate, scheduler: BackgroundRefreshScheduler(), products: products))
        let appModel = AppModel(accountRuntime: accountRuntime, logger: logger, accountEnvironment: accountEnvironment,
                                launcher: LaunchBootstrapper(environment: resolvedEnvironment, launchRecords: launchRecords),
                                lock: lock, subscription: subscription, storefront: appStore)
        #if DEBUG || TALLY_TEST_HOOKS
        if hooks.isActive { appModel.testHooks = hooks }
        #endif
        return AppEnvironment(logger: logger, accountRuntime: accountRuntime, appModel: appModel, signIn: signIn,
                             accountEnvironment: accountEnvironment)
    }

    /// PAY-03: the engine's StoreKit source. StoreKit itself, except in a Debug process that hosts
    /// TallyAppTests (XCTest sets `XCTestConfigurationFilePath` there, never in an app a UI test
    /// launches), where this process's own engine gets no StoreKit at all. StoreKit Testing serves a
    /// test session's products only to a process whose first StoreKit connection follows that
    /// `SKTestSession`; an earlier one stays in the Sandbox environment (RevenueCat's
    /// `StoreKitConfigTestCase` makes the same point). This engine starts at app init, before any
    /// test runs, and the StoreKit Testing suite was served nothing in runs 36943065198 and
    /// 36951037662 while it did.
    static func entitlementSource(products: SubscriptionProducts,
                                  environment: [String: String] = ProcessInfo.processInfo.environment)
        -> any EntitlementSourcing {
        #if DEBUG
        if environment["XCTestConfigurationFilePath"] != nil { return NoEntitlementSource() }
        #endif
        return StoreKitEntitlementSource(products: products)
    }

    /// PAY-05, PAY-08 (M3-B2): the App Store for the paywall's offer, Restore Purchases and Request a
    /// Refund. StoreKit itself, except in a Debug process that hosts TallyAppTests, for the reason
    /// `entitlementSource` gives: that process's first StoreKit connection must be the StoreKit
    /// Testing suite's.
    static func storefront(products: SubscriptionProducts,
                           environment: [String: String] = ProcessInfo.processInfo.environment)
        -> any SubscriptionStorefront {
        #if DEBUG
        if environment["XCTestConfigurationFilePath"] != nil { return UnavailableStorefront() }
        #endif
        return StoreKitStorefront(products: products)
    }
}
