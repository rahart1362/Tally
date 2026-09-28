import Foundation
import TallyCanvasAPI
import TallyDomain
import TallyIntents
import TallyStore
import TallySync

/// The app's root routes (perf-app-runtime.md §3 item 1). Exactly one is on screen at a time:
/// `RootView` is a single `switch` over this value, so the Home shell (a `TabView`) is only ever
/// a root and never content pushed onto a `NavigationStack`.
public nonisolated enum RootRoute: Equatable, Sendable {
    /// The first frame: the launch colour, which doubles as the privacy cover (ADR 0001), until
    /// `AppModel.launch()` decides where to go.
    case launching
    /// Onboarding's `NavigationStack` (Welcome, school search, sign-in, first sync): plain pushed
    /// pages only.
    case welcome
    /// ASC-14 "Explore with Sample Data": the Home shell over the bundled flagship persona.
    case sample
    /// A signed-in account's Home shell.
    case signedIn(AccountKey)
}

/// E04: the composition root's top-level app state (architecture.md §3.1: "`AppModel` and
/// `RefreshStatusModel` (`@MainActor @Observable`), consuming `RefreshCoordinator` events"), and
/// the owner of the root route (perf-app-runtime.md §7 step 1) and of the account's lifecycle:
/// launch (plan 06 step 8), sign-in's first sync (step 9) and sign-out (step 10).
///
/// Route transitions are explicit methods, and each accepts only the routes it is defined from;
/// any other call is a no-op, so a stray or repeated tap can never land the app in an undefined
/// place:
///
/// | Method | From | To |
/// |---|---|---|
/// | `launch()` / `bootstrap()` | `.launching` | `.signedIn` (an account on disk) or `.welcome` |
/// | `enterSample()` | `.welcome` | `.sample` |
/// | `exitSample()` | `.sample` | `.welcome` |
/// | `finishFirstSync()` / `completeSignIn(_:)` | `.welcome` | `.signedIn` |
/// | `signOut()` | `.signedIn` | `.welcome` |
///
/// The account's coordinator lives in `accountRuntime` (perf-app-runtime.md §7 step 7), the one
/// owner that the Home, `.backgroundTask` and sign-out share. `attach(_:)`/`detach()` are where the
/// "Refresh Tally" intent's `RefreshIntentBridge` is set and cleared.
@MainActor
@Observable
public final class AppModel {
    /// Explicit and nonisolated (plan 06 A2). In this default-`MainActor` module the compiler makes an
    /// implicit deinit main-actor isolated, `@MainActor` on the class or not, and an isolated deinit
    /// (`swift_task_deinitOnExecutor`) aborts iOS 26.0-26.3 runtimes when it runs nested or in a
    /// task-local scope (swiftlang/swift#88036; the floor abort in CI run 36390172728). CI's `nm`
    /// gate keeps isolated deinits out of every shipping binary.
    nonisolated deinit {}

    public private(set) var route: RootRoute = .launching
    /// Whether the next Welcome appearance plays the brand moment. ux-ui.md §3.2 stage 1: it plays
    /// on "first run and after sign-out only", so it is `true` at launch and after `signOut()`,
    /// and `false` once the student has left Welcome for sample data and comes back.
    public private(set) var playsBrandMoment = true
    public let refreshStatus = RefreshStatusModel()
    /// The signed-in account's one `RefreshCoordinator` owner, shared with `.backgroundTask`
    /// (`AppEnvironment` builds it once and hands it to both).
    public let accountRuntime: AccountRuntime
    /// SEC-07: the app lock and the privacy cover (`RootView` renders them).
    public let lock: AppLockModel
    /// The Home shell's model: over a `SampleSession` while `route == .sample`, over the account's
    /// coordinator (`AccountHomeSource`) while `.signedIn`. Built by the route transition (pure
    /// construction); every fetch, digest and projection then runs off the main actor.
    public private(set) var home: HomeModel?
    /// The signed-in account (`accounts.json`'s active record), while `.signedIn`.
    public private(set) var activeAccount: AccountRecord?
    /// The model of the first sync in progress, between the token exchange and the root switch
    /// (perf-app-runtime.md §2.4 S4–S8). Owned here, not by a navigation destination builder
    /// (perf-app-runtime.md §3 item 6), so the root switch releases it.
    public private(set) var firstSync: FirstSyncViewModel?

    /// Ends the previous session after `exitSample()` or `signOut()`; owned here so it is never
    /// orphaned.
    private let teardown = TaskBox()
    /// The launch's projection (L5–L8) and the attach that follows it, or a sign-in's attach.
    private let launchWork = TaskBox()
    /// TallyCore's logging port (plan 06 A8): the composition root passes its `os.Logger`
    /// adapter, which the sample gateway (and later the account's gateway) reports to.
    private let logger: any TallyLogger
    private let launcher: any LaunchBootstrapping
    /// The platform services an account needs; `nil` in tests and previews that never sign in.
    private let accountEnvironment: AccountEnvironment?
    @ObservationIgnored private var pendingSignIn: PendingSignIn?
    @ObservationIgnored private var isLaunching = false

    #if DEBUG || TALLY_TEST_HOOKS
    /// UI-test hooks (`LaunchTestHooks`): never compiled into a shipping Release build.
    public var testHooks: LaunchTestHooks?
    #endif
    #if DEBUG
    /// Tests: the sign-out steps in the order they completed (perf-app-runtime.md §4.3).
    @ObservationIgnored private(set) var signOutSteps: [SignOutStep] = []
    #endif

    public init(accountRuntime: AccountRuntime = AccountRuntime(), logger: any TallyLogger = NoOpLogger(),
                accountEnvironment: AccountEnvironment? = nil, launcher: (any LaunchBootstrapping)? = nil,
                lock: AppLockModel? = nil) {
        self.accountRuntime = accountRuntime
        self.logger = logger
        self.accountEnvironment = accountEnvironment
        if let launcher {
            self.launcher = launcher
        } else if let accountEnvironment {
            self.launcher = LaunchBootstrapper(environment: accountEnvironment)
        } else {
            self.launcher = NoAccountLaunch()
        }
        self.lock = lock ?? AppLockModel()
    }

    // MARK: - Launch (plan 06 step 8; perf-app-runtime.md §2.4 L1–L9)

    /// The launch: `RootView`'s first frame is the launch colour (L2); this resolves the route off
    /// the main actor (L3, `LaunchBootstrapper`), then assigns it once (L4). Runs once.
    public func launch() async {
        guard route == .launching, !isLaunching else { return }
        isLaunching = true
        #if DEBUG || TALLY_TEST_HOOKS
        if let testHooks, let accountEnvironment { await testHooks.prepareLaunch(accountEnvironment) }
        #endif
        apply(await launcher.resolve())
    }

    /// The launch with nothing on disk: Welcome, with the lock off (tests and previews).
    public func bootstrap() {
        apply(.welcome)
    }

    /// L4: one assignment. The lock is configured first (it locks at cold launch when it is on),
    /// then the route. With an account, the Home paints the glance in the same frame, and the full
    /// projection (L5–L8: one snapshot decode, the coordinator, the projector) proceeds in a task
    /// this model owns, even while the lock is up. The Home's own `.task` starts the launch refresh
    /// (L9) only after that projection, and only once the Home is on screen, so after an unlock
    /// (ADR 0001's order: cover, lock, cached render, handshake).
    ///
    /// With no account the lock stays off, whatever the setting says: Welcome shows nothing to
    /// protect, and the lock view's only way out without a passcode, sign-out, has no account to
    /// sign out of. (A sign-out stopped between removing `accounts.json` and resetting the setting
    /// leaves exactly that.) The setting itself is left as it is.
    func apply(_ resolution: LaunchResolution) {
        guard route == .launching else { return }
        guard let account = resolution.account else {
            lock.configure(with: .disabled)
            route = .welcome
            return
        }
        lock.configure(with: resolution.lock)
        let home = HomeModel(source: AccountHomeSource(runtime: accountRuntime))
        if let glance = resolution.glance { home.showGlance(glance) }
        self.home = home
        activeAccount = account
        route = .signedIn(account.accountKey)
        launchWork.replace(with: Task { [weak self, home] in
            await home.prepare()
            await self?.attachActiveCoordinator(for: account.accountKey)
        })
    }

    private func attachActiveCoordinator(for account: AccountKey) async {
        guard let coordinator = await accountRuntime.coordinator(),
              !Task.isCancelled, route == .signedIn(account) else { return }
        await attach(coordinator)
    }

    // MARK: - Sample data

    /// Welcome's (and "school not enabled"'s) "Explore with Sample Data": a root switch, never a
    /// push. Only constructs the models (no I/O), so the shell paints in the same frame.
    public func enterSample() {
        guard route == .welcome else { return }
        home = HomeModel(source: SampleSession(logger: logger))
        route = .sample
    }

    /// The SAMPLE DATA banner's "Exit": back to Welcome without replaying the brand moment, then
    /// the session ends (perf-app-runtime.md §4.3). The route switches first, in this call, so the
    /// shell goes away and SwiftUI cancels its tasks; then `homeTeardown` ends the model, its
    /// projector and its session off the view's lifetime: streams finish, the snapshot is released.
    public func exitSample() {
        guard route == .sample else { return }
        playsBrandMoment = false
        route = .welcome
        guard let ending = home else { return }
        home = nil
        teardown.replace(with: Task { await ending.end() })
    }

    // MARK: - Sign-in and first sync (plan 06 step 9; perf-app-runtime.md §2.4 S1–S9)

    /// S2 done: the token exchange produced `credential` for `target`. Builds the FirstSync model
    /// (the Welcome stack pushes the FirstSync page next, S4). Provisioning (S3) and the first run
    /// (S5) start when that page's model starts. A second sign-in replaces an unfinished one.
    public func signInSucceeded(_ credential: CanvasCredential, target: SignInTarget) {
        guard route == .welcome else { return }
        abandonSignIn()
        let pending = PendingSignIn(credential: credential, target: target)
        pendingSignIn = pending
        firstSync = makeFirstSyncModel(for: pending)
    }

    /// FirstSync's Retry: a fresh model over the same sign-in. Its coordinator, once provisioned, is
    /// reused, so the retry is one more `run(.manual)` on it (perf-app-runtime.md §2.4).
    public func retryFirstSync() {
        guard route == .welcome, let pending = pendingSignIn else { return }
        firstSync = makeFirstSyncModel(for: pending)
    }

    /// S8: FirstSync reported `.finished` (the first snapshot and its glance are committed). A root
    /// switch, not a push: the Welcome stack and its models, this one's FirstSync model included,
    /// are released, and the Home projects the committed value itself (S7), with no decode.
    public func finishFirstSync() {
        guard route == .welcome, let pending = pendingSignIn, let record = pending.record,
              let coordinator = pending.coordinator else { return }
        pendingSignIn = nil
        firstSync = nil
        activeAccount = record
        completeSignIn(record.accountKey)
        let reloadWidgets = accountEnvironment?.reloadWidgets
        launchWork.replace(with: Task { [weak self] in
            await self?.attach(coordinator)
            reloadWidgets?() // S9: the account's first glance now exists
        })
    }

    /// The root switch to `account`'s Home shell over its coordinator (`AccountHomeSource`).
    public func completeSignIn(_ account: AccountKey) {
        guard route == .welcome else { return }
        home = HomeModel(source: AccountHomeSource(runtime: accountRuntime))
        route = .signedIn(account)
    }

    /// "Choose a Different School" after a failed first sync (perf-app-runtime.md §2.4: "calls
    /// `AccountSession.end()` and purges"): the half-made account is removed exactly as a sign-out
    /// removes one, by its derived record, whether or not provisioning finished (a provisioning
    /// that stopped part-way can have saved the credential and written `accounts.json`). A no-op
    /// without a sign-in in progress.
    public func abandonSignIn() {
        guard let pending = pendingSignIn else { return }
        pendingSignIn = nil
        firstSync = nil
        guard let environment = accountEnvironment else { return }
        let record = pending.record ?? AccountRecord.derived(credential: pending.credential, target: pending.target)
        let installed = pending.coordinator
        let runtime = accountRuntime
        teardown.replace(with: Task {
            let retired = installed == nil ? nil : await runtime.end()
            await AccountSignOut.purge(account: record, retired: retired ?? installed, environment: environment)
        })
    }

    private func makeFirstSyncModel(for pending: PendingSignIn) -> FirstSyncViewModel {
        let id = pending.id
        return FirstSyncViewModel(
            schoolDisplayName: pending.target.schoolDisplayName,
            publisher: CoordinatorFirstSyncPublisher(prepare: { [weak self] in await self?.firstSyncCoordinator(for: id) }))
    }

    /// S3, once per sign-in: the credential to the Keychain, the account key, `accounts.json`, the
    /// store directory, then the account's coordinator, installed as the runtime's (so the Home, the
    /// background task and the intent all use it after the root switch).
    func firstSyncCoordinator(for id: UUID) async -> RefreshCoordinator? {
        guard let pending = pendingSignIn, pending.id == id else { return nil }
        if let coordinator = pending.coordinator { return coordinator }
        guard let environment = accountEnvironment else { return nil }
        await teardown.value() // an abandoned sign-in's purge finishes before this one writes
        let provisioned: (AccountRecord, RefreshCoordinator)
        do {
            provisioned = try await AccountSessionFactory.provision(credential: pending.credential, target: pending.target,
                                                                    environment: environment)
        } catch {
            // Stopped part-way. Retry provisions again over what it wrote, and "Choose a Different
            // School" purges it; but if the sign-in was abandoned meanwhile, that purge may have
            // run before these writes, so purge again.
            if pendingSignIn?.id != id {
                await AccountSignOut.purge(account: .derived(credential: pending.credential, target: pending.target),
                                           retired: nil, environment: environment)
            }
            return nil
        }
        let (record, coordinator) = provisioned
        guard pendingSignIn?.id == id else {
            // Abandoned while provisioning: remove what it wrote.
            await AccountSignOut.purge(account: record, retired: coordinator, environment: environment)
            return nil
        }
        pendingSignIn?.record = record
        pendingSignIn?.coordinator = coordinator
        await accountRuntime.install(coordinator)
        return coordinator
    }

    // MARK: - Sign-out (plan 06 step 10; perf-app-runtime.md §4.3)

    /// "Sign Out & Erase" (UX-WP-20's button, M3-A; the lock view's passcode-less escape). In
    /// perf-app-runtime.md §4.3's order:
    /// 1. the route goes to `.welcome` (the Home's views go away and SwiftUI cancels their tasks);
    /// 2. `refreshStatus.detach()`;
    /// 3. `home.end()`: its subscription, source and projector end, and the projector releases
    ///    the snapshot;
    /// 4. `RefreshIntentBridge.coordinator = nil`;
    /// 5. the account runtime ends: `bumpEpochAndCancel()` discards any run in flight and shuts the
    ///    coordinator down (every stream finishes, its snapshot is released);
    /// 6. `AccountSignOut.purge` (`@concurrent`): `SignOutUseCase.signOut` (revoke, notifications,
    ///    crypto-shred and delete the store, delete the credential), then `accounts.json` and the
    ///    app-lock setting;
    /// 7. the widgets reload.
    ///
    /// Steps 3–7 run in a task this model owns, off the view's lifetime. The app lock turns off with
    /// step 1, so Welcome shows even when sign-out came from the lock view.
    public func signOut() {
        guard case .signedIn = route else { return }
        let account = activeAccount
        launchWork.cancel()
        route = .welcome
        playsBrandMoment = true
        lock.resetForSignOut()
        recordSignOutStep(.route)
        refreshStatus.detach()
        recordSignOutStep(.refreshStatus)
        let endingHome = home
        home = nil
        activeAccount = nil
        let runtime = accountRuntime
        let environment = accountEnvironment
        teardown.replace(with: Task { [weak self] in
            await endingHome?.end()
            self?.recordSignOutStep(.home)
            RefreshIntentBridge.coordinator = nil
            self?.recordSignOutStep(.intentBridge)
            let retired = await runtime.end()
            self?.recordSignOutStep(.runtime)
            if let account, let environment {
                await AccountSignOut.purge(account: account, retired: retired, environment: environment)
            }
            self?.recordSignOutStep(.purge)
            environment?.reloadWidgets()
            self?.recordSignOutStep(.widgets)
        })
    }

    /// Called once a `RefreshCoordinator` exists for the signed-in account: it becomes the
    /// runtime's coordinator, the intent's and the status model's. Sample data never comes
    /// through here: it must never reach the background task or the Siri "Refresh Tally" intent
    /// (ASC-14's "no network calls in sample mode" guarantee).
    public func attach(_ coordinator: RefreshCoordinator) async {
        await accountRuntime.install(coordinator)
        RefreshIntentBridge.coordinator = coordinator
        await refreshStatus.attach(to: coordinator)
    }

    /// Stops mirroring the coordinator and clears the intent's reference to it. The coordinator
    /// itself is retired by `signOut()`.
    public func detach() {
        RefreshIntentBridge.coordinator = nil
        refreshStatus.detach()
    }

    /// Tests: the pending teardown (sample exit, sign-out, abandoned sign-in), awaited.
    func awaitTeardown() async {
        await teardown.value()
    }

    /// Tests: the launch's projection and attach (or a sign-in's attach), awaited.
    func awaitLaunchWork() async {
        await launchWork.value()
    }

    private func recordSignOutStep(_ step: SignOutStep) {
        #if DEBUG
        signOutSteps.append(step)
        #endif
    }
}

/// perf-app-runtime.md §4.3's sign-out steps, in order (`AppModel.signOutSteps`, DEBUG).
nonisolated enum SignOutStep: Equatable, Sendable, CaseIterable {
    case route, refreshStatus, home, intentBridge, runtime, purge, widgets
}

/// A sign-in between the token exchange and the root switch: its credential and school, and,
/// once provisioned (S3), its `accounts.json` record and coordinator.
nonisolated struct PendingSignIn: Sendable {
    let id = UUID()
    let credential: CanvasCredential
    let target: SignInTarget
    var record: AccountRecord?
    var coordinator: RefreshCoordinator?
}
