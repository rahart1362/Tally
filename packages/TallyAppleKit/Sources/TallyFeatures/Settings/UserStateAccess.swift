import Foundation
import TallyDomain
import TallyStore

/// Settings' access to the account's `UserState` (UX-WP-20): the "What changed" thresholds today.
/// A write returns the state as saved; a read never fails (an unreadable file reads as defaults,
/// and writing is then refused, so a file this build cannot read is never overwritten).
public nonisolated protocol UserStateAccess: Sendable {
    func load() async -> UserState
    /// Applies `change` to the current state and saves it. Throws when the state cannot be saved.
    @discardableResult
    func update(_ change: @Sendable (inout UserState) -> Void) async throws -> UserState
}

/// Sample mode's `UserState`, for the session only (ASC-14: sample data is never persisted). Sample
/// mode has no `RefreshCoordinator`, so the thresholds have no digest to feed.
public actor InMemoryUserStateAccess: UserStateAccess {
    private var state: UserState

    public init(_ initial: UserState = UserState()) {
        state = initial
    }

    public func load() -> UserState { state }

    @discardableResult
    public func update(_ change: @Sendable (inout UserState) -> Void) -> UserState {
        change(&state)
        return state
    }
}

/// A signed-in account's `UserState`: sealed on disk by `UserStateStore`, and every save is handed
/// to the account's `RefreshCoordinator`: `digestThresholds` (`updateDigestThresholds`), so the
/// next commit's "What changed" uses it (owner decision DG-1); `showGradesInGlance`
/// (`updateIncludeGrades`), which rebuilds the glance on disk at once, then the widget reloads, so
/// turning grades off takes them off the widget now (PMO R10; M3-A O11); and the "grades kept
/// outside Canvas" answers (`updateGradeAvailabilityOverrides`, plan 08 XG-04), which every later
/// commit's index uses (the glance, the digest) and which rebuild the glance at once the same way,
/// so the widget agrees with the Dashboard.
public actor AccountUserStateAccess: UserStateAccess {
    public enum AccessError: Error, Equatable {
        /// `UserStateStore.load()` reported a state this build must not overwrite (written by a
        /// newer build, or unreadable until the device is unlocked).
        case notWritable(VaultDisposition)
    }

    private let store: UserStateStore
    private let runtime: AccountRuntime
    private let reloadWidgets: @Sendable () -> Void

    public init(store: UserStateStore, runtime: AccountRuntime, reloadWidgets: @escaping @Sendable () -> Void = {}) {
        self.store = store
        self.runtime = runtime
        self.reloadWidgets = reloadWidgets
    }

    public func load() async -> UserState {
        switch await store.load() {
        case .loaded(let state): state
        case .absent, .unavailable: UserState()
        }
    }

    @discardableResult
    public func update(_ change: @Sendable (inout UserState) -> Void) async throws -> UserState {
        var state: UserState
        switch await store.load() {
        case .loaded(let stored):
            state = stored
        case .absent, .unavailable(.resetUserStateAndTell):
            state = UserState()
        case .unavailable(let disposition):
            throw AccessError.notWritable(disposition)
        }
        change(&state)
        try await store.save(state)
        if let coordinator = await runtime.coordinator() {
            await coordinator.updateDigestThresholds(state.digestThresholds)
            let gradesRewrote = await coordinator.updateIncludeGrades(state.showGradesInGlance)
            let overridesRewrote = await coordinator.updateGradeAvailabilityOverrides(state.gradeAvailabilityOverrides)
            if gradesRewrote || overridesRewrote { reloadWidgets() }
        }
        return state
    }
}

extension AccountUserStateAccess {
    /// The signed-in Home's access (M2-C1 O8): the account's sealed `UserStateStore` under `root`,
    /// which the launch (`LaunchResolution.storeRoot`) or the sign-in resolved off the main actor.
    /// Construction only: no file is read until Settings loads.
    init(account: AccountKey, root: URL, environment: AccountEnvironment, runtime: AccountRuntime) {
        self.init(store: UserStateStore(root: root, accountKey: account, sealer: environment.sealer(for: account)),
                  runtime: runtime, reloadWidgets: environment.reloadWidgets)
    }

    /// What the account's coordinator starts from (`AccountSessionFactory`): the stored `UserState`,
    /// or the defaults when there is none or it cannot be read. The defaults never show grades in
    /// the glance (PMO R10).
    @concurrent
    static func stored(account: AccountKey, root: URL, environment: AccountEnvironment) async -> UserState {
        let store = UserStateStore(root: root, accountKey: account, sealer: environment.sealer(for: account))
        if case .loaded(let state) = await store.load() { return state }
        return UserState()
    }
}

extension AccountEnvironment {
    /// The store root, resolved off the main actor (`storeRoot` asks the file system for the App
    /// Group container); `nil` when there is none.
    @concurrent
    func resolvedStoreRoot() async -> URL? {
        try? storeRoot()
    }
}
