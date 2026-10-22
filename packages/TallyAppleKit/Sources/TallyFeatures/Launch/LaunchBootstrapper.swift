import Foundation
import Synchronization
import TallyDomain
import TallyStore

/// What a launch found on disk (perf-app-runtime.md §2.4 L3): enough to choose the route and paint
/// the first frame, and nothing that needs the snapshot decoded.
public nonisolated struct LaunchResolution: Sendable, Equatable {
    /// The active account from `accounts.json`, or `nil`: Welcome.
    public let account: AccountRecord?
    /// The app-lock setting (Keychain). Unreadable fails closed (`AppLockPreferenceRead.effective`).
    public let lock: AppLockPreference
    /// The account's sealed glance, mapped for the first paint. `nil` with an account means the
    /// Home starts from its skeleton (for example, a sign-in whose first sync never finished).
    public let glance: HomeGlance?
    /// The app-private store root this launch resolved (off the main actor), with an account only:
    /// the signed-in Home's `UserStateStore` opens under it (M3-A, Settings; M2-C1 O8), so the main
    /// actor never asks the file system for it itself.
    public let storeRoot: URL?
    /// O5 (PERF-L): the account's persisted refresh record, or `nil` when none could be read. The
    /// glance's freshness is derived from it, and the account's coordinator starts from it.
    public let record: RefreshRecord?
    /// AGE-1 (EB-01(b)): whether this launch is the one that just wrote the install sentinel
    /// (`VaultBootstrap.reconcileInstall`) — "first launch after install." `AppModel.apply(_:)`
    /// feeds this straight to `AgeAssuranceModel.evaluateIfDue`.
    public let isFirstLaunchAfterInstall: Bool

    public init(account: AccountRecord?, lock: AppLockPreference, glance: HomeGlance?, storeRoot: URL? = nil,
                record: RefreshRecord? = nil, isFirstLaunchAfterInstall: Bool = false) {
        self.account = account
        self.lock = lock
        self.glance = glance
        self.storeRoot = storeRoot
        self.record = record
        self.isFirstLaunchAfterInstall = isFirstLaunchAfterInstall
    }

    /// Nothing on disk: Welcome, with the lock off.
    public static let welcome = LaunchResolution(account: nil, lock: .disabled, glance: nil)
}

/// Resolves the launch route (`AppModel.launch()`). A port so tests and previews can supply one.
public nonisolated protocol LaunchBootstrapping: Sendable {
    func resolve() async -> LaunchResolution
}

/// The default when no account environment is injected: nothing on disk, so Welcome.
public nonisolated struct NoAccountLaunch: LaunchBootstrapping {
    public init() {}
    public func resolve() async -> LaunchResolution { .welcome }
}

/// L3 of the launch sequence (perf-app-runtime.md §2.4; plan 06 step 8), entirely off the main
/// actor (`@concurrent`), in ≤ 50 ms on device:
/// 0. `StoreMigration.migrateIfNeeded` (SEC1-09), synchronous and ahead of step 1: an existing
///    install's `accounts.json` and non-glance account files move from the old, combined root to
///    the app's own storage, carrying the install sentinel with them so step 1 never mistakes an
///    upgrading install for a fresh one. A no-op after the first launch that runs it, and a no-op
///    for any build where the App Group was never configured (there was only ever one root).
/// 1. `VaultBootstrap.reconcileInstall` on a fresh install's first launch only (its sentinel is
///    missing). Keychain items can outlive the app and files cannot, so a reinstall starts clean:
///    the inherited vault keys are shredded, and the Canvas credential and the app-lock setting
///    from the earlier install are removed with them.
/// 2. The app-lock setting (Keychain).
/// 3. `accounts.json`: the active account.
/// 4. `SnapshotStore.loadGlance()` for that account (≤ 16 KB; the snapshot is not touched here),
///    from the App Group root when SEC1-09's split applies (`environment.sharedRoot()`).
/// 5. The account's refresh record (`refresh-state.sealed`, O5): the first paint's freshness
///    (`HomeGlance.freshness`), and, handed over through `LaunchRecordHandoff`, the record the
///    account's coordinator starts from (`AccountSessionFactory`), so its launch refresh obeys
///    `FreshnessRules.shouldStart`. With no record, both start from the committed data's time and
///    the launch refreshes, as before.
///
/// **Concurrency (PERF-L, `Launch.Resolve`).** The reads that do not depend on each other run
/// together, in child tasks off the main actor: the app-lock setting (2) starts at once, alongside
/// the store root lookup, the migration (0), the reconcile (1) and the account's files (3, then 4
/// and 5 together). The result is the same as reading them one after another: the migration still
/// runs before the reconcile, the reconcile still runs before any file is read, and on the launch
/// where it runs (it resets the lock setting) the setting is read again after it.
///
/// The snapshot decode (L5) happens later, once, in `AccountSessionFactory`.
public nonisolated struct LaunchBootstrapper: LaunchBootstrapping {
    private let environment: AccountEnvironment
    /// Where step 5's record is left for the account's coordinator; `nil`: it reads the file itself.
    private let launchRecords: LaunchRecordHandoff?
    /// Tests only: called at each step with whether it ran on the main thread.
    private let threadProbe: (@Sendable (_ step: String, _ onMainThread: Bool) -> Void)?

    public init(environment: AccountEnvironment, launchRecords: LaunchRecordHandoff? = nil) {
        self.init(environment: environment, launchRecords: launchRecords, threadProbe: nil)
    }

    init(environment: AccountEnvironment, launchRecords: LaunchRecordHandoff? = nil,
         threadProbe: (@Sendable (_ step: String, _ onMainThread: Bool) -> Void)?) {
        self.environment = environment
        self.launchRecords = launchRecords
        self.threadProbe = threadProbe
    }

    @concurrent
    public func resolve() async -> LaunchResolution {
        // Step 2 needs nothing else, so it starts now and runs alongside everything below.
        async let lockRead = lockPreference()
        guard let root = try? environment.storeRoot() else {
            // No store location at all: nothing to open, but the lock setting still applies.
            return LaunchResolution(account: nil, lock: await lockRead, glance: nil)
        }
        let sharedRoot = environment.sharedRoot()
        // Step 0 (SEC1-09): before anything below opens `accounts.json` or an account's store,
        // move an existing install's files from the old, combined root to the new split one. Must
        // run before `reconcileInstallIfNeeded`: an upgrading install's sentinel has to land at the
        // new root too, or the very next line would read it as a fresh install and shred every
        // vault key the migration just carried forward.
        probe("storeMigration")
        StoreMigration.migrateIfNeeded(privateRoot: root, oldCombinedRoot: sharedRoot ?? root)
        probe("reconcileInstall")
        let reconciled = await Self.reconcileInstallIfNeeded(root: root, environment: environment)
        // SEC1-08: finish any sign-out purge that did not complete last time (its directory
        // delete or key shred failed, or the process died mid-purge). A launch with nothing
        // pending does one empty directory listing and returns at once.
        probe("retryPendingPurges")
        AccountPurger.retryPending(root: root, sharedRoot: sharedRoot, keyring: environment.keyring)

        async let stored = storedAccount(root: root, sharedRoot: sharedRoot)
        // The reconcile resets the lock setting, so on the launch where it ran, a read that may have
        // raced it is replaced by one made after it (a fresh install's first launch only).
        let earlyLock = await lockRead
        let lock = reconciled ? await lockPreference() : earlyLock
        guard let found = await stored else {
            return LaunchResolution(account: nil, lock: lock, glance: nil, isFirstLaunchAfterInstall: reconciled)
        }
        return LaunchResolution(account: found.account, lock: lock, glance: found.glance, storeRoot: root,
                                record: found.record, isFirstLaunchAfterInstall: reconciled)
    }

    /// Step 2: the app-lock setting (Keychain). Unreadable fails closed (`AppLockPreferenceRead.effective`).
    @concurrent
    private func lockPreference() async -> AppLockPreference {
        probe("lockPreference")
        return await environment.lockPreferences.load().effective
    }

    /// Steps 3 to 5: the active account from `accounts.json`, then its glance and its refresh record
    /// together; `nil` with no account.
    @concurrent
    private func storedAccount(root: URL, sharedRoot: URL?) async -> (account: AccountRecord, glance: HomeGlance?, record: RefreshRecord?)? {
        probe("accounts")
        guard let account = AccountDirectoryStore(root: root).activeAccount() else { return nil }

        async let recordRead = refreshRecord(for: account.accountKey, root: root)
        probe("glance")
        let store = environment.snapshotStore(for: account.accountKey, root: root, sharedRoot: sharedRoot)
        let projection: GlanceProjection?
        if case .loaded(let loaded) = await store.loadGlance() { projection = loaded } else { projection = nil }
        let read = await recordRead
        let record: RefreshRecord?
        switch read {
        case .loaded(let loaded):
            record = loaded
            launchRecords?.leave(loaded, for: account.accountKey)
        case .absent:
            record = nil
            launchRecords?.leave(nil, for: account.accountKey)
        case .unavailable:
            // Not readable now (the device locked, an I/O error): the coordinator tries again itself.
            record = nil
        }
        let glance = projection.map { HomeGlance.make(from: $0, now: environment.clock.now(), record: record) }
        return (account, glance, record)
    }

    /// Step 5: the account's refresh record (O5).
    @concurrent
    private func refreshRecord(for account: AccountKey, root: URL) async -> RefreshStateLoadResult {
        probe("refreshRecord")
        return RefreshStateStore(root: root, accountKey: account, sealer: environment.sealer(for: account)).load()
    }

    /// Step 1, also run by the test hooks before they seed a store (a seeded store written before
    /// the first launch's reconcile would have its keys shredded by it). Returns whether it ran
    /// (the sentinel was missing), whether or not the sentinel could then be written.
    @discardableResult
    static func reconcileInstallIfNeeded(root: URL, environment: AccountEnvironment) async -> Bool {
        let sentinel = StoreLayout(root: root, accountKey: AccountKey("install")).installSentinel
        guard !FileManager.default.fileExists(atPath: sentinel.path) else { return false }
        environment.removeLegacyCredentials()
        await environment.credentialStore.delete()
        await environment.lockPreferences.reset()
        do {
            try ProtectedFile.prepareDirectory(root, excludeFromBackup: true)
            // Shreds every vault key this process can see, then writes the sentinel.
            try VaultBootstrap.reconcileInstall(keyring: environment.keyring, sentinel: sentinel)
        } catch {
            // Protected data unavailable (a background launch before first unlock): the sentinel
            // is not written, so the next foreground launch reconciles instead.
        }
        return true
    }

    private func probe(_ step: String) {
        threadProbe?(step, pthread_main_np() != 0)
    }
}

/// Step 5's record, handed from the launch (`LaunchBootstrapper`, which reads it for the first
/// paint) to the account's coordinator (`AccountSessionFactory.activeCoordinator`), so a launch
/// reads the file once (O5, PERF-L). The composition root makes one per process and gives it to
/// both.
///
/// The first resolution in the process closes it, whatever it finds, and nothing can be left after
/// that: a background launch that resolves the account before the foreground launch has read
/// anything, a sign-in and any later resolution all read the file themselves, so a record left
/// here can never be taken by a resolution it was not read for.
public nonisolated final class LaunchRecordHandoff: Sendable {
    /// What the launch read for an account: its record, or `nil` for none on disk.
    public struct Handed: Equatable, Sendable {
        public let record: RefreshRecord?
    }

    private enum State: Sendable {
        case open
        case left(AccountKey, RefreshRecord?)
        case closed
    }

    private let state = Mutex(State.open)

    public init() {}

    /// The launch's read for `account`. Ignored once the handoff is closed, or if something was left.
    func leave(_ record: RefreshRecord?, for account: AccountKey) {
        state.withLock { state in
            if case .open = state { state = .left(account, record) }
        }
    }

    /// What the launch read for `account`, or `nil` when it read nothing for it (then read the file).
    /// Closes the handoff either way.
    func take(for account: AccountKey) -> Handed? {
        state.withLock { state in
            defer { state = .closed }
            guard case .left(let key, let record) = state, key == account else { return nil }
            return Handed(record: record)
        }
    }

    /// A resolution that found no account: nothing will be taken, and nothing may be left after it.
    func close() {
        state.withLock { $0 = .closed }
    }
}
