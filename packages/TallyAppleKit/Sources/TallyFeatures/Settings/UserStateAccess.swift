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

/// A signed-in account's `UserState`: sealed on disk by `UserStateStore`, and every saved
/// `digestThresholds` is handed to the account's `RefreshCoordinator`
/// (`updateDigestThresholds`), so the next commit's "What changed" uses it (owner decision DG-1).
public actor AccountUserStateAccess: UserStateAccess {
    public enum AccessError: Error, Equatable {
        /// `UserStateStore.load()` reported a state this build must not overwrite (written by a
        /// newer build, or unreadable until the device is unlocked).
        case notWritable(VaultDisposition)
    }

    private let store: UserStateStore
    private let runtime: AccountRuntime

    public init(store: UserStateStore, runtime: AccountRuntime) {
        self.store = store
        self.runtime = runtime
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
        await runtime.coordinator()?.updateDigestThresholds(state.digestThresholds)
        return state
    }
}
