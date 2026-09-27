import Foundation
import TallyDomain

public enum UserStateLoadResult: Equatable, Sendable {
    case loaded(UserState)
    case absent
    /// `.resetUserStateAndTell` (undecodable; there is nothing left to recover) or
    /// `.retryAfterUnlock` / `.keepAndReport` (recoverable; the file is left untouched).
    case unavailable(VaultDisposition)
}

/// The store side of `user-state.sealed`: reminder rules, goals, quiet hours and manual class
/// times (architecture.md §3.1/§3.2, WP-C02). Unlike `SnapshotStore`, an undecodable payload here
/// is real data loss — it cannot be re-fetched from Canvas — so `UserState.currentSchemaVersion`
/// bumps go through `UserStateMigration` instead of a discard-and-rebuild rule.
public actor UserStateStore {
    private let layout: StoreLayout
    private let access: SealedFileAccess
    private let isOwner: Bool

    public init(root: URL, accountKey: AccountKey, sealer: any SnapshotSealer, isOwner: Bool = true) {
        layout = StoreLayout(root: root, accountKey: accountKey)
        access = SealedFileAccess(sealer: sealer, isOwner: isOwner)
        self.isOwner = isOwner
    }

    public func prepare() throws {
        try ProtectedFile.prepareDirectory(layout.accountDirectory, excludeFromBackup: true)
    }

    public func load() -> UserStateLoadResult {
        switch access.read(.userState, at: layout.url(for: .userState)) {
        case .absent:
            return .absent
        case .failed(_, let disposition):
            return .unavailable(disposition)
        case .plaintext(let data):
            do {
                return .loaded(try UserStateMigration.decode(data))
            } catch SchemaVersionProbeError.unsupportedFutureVersion {
                // Written by a build newer than this one. NEVER delete: a future app update (or a
                // rollback of the rollback) can still read it; there is no data to lose by waiting.
                return .unavailable(.keepAndReport)
            } catch {
                // Truly undecodable and cannot be re-derived from Canvas: start empty and tell the
                // user once, per encryption.md's disposition table for a non-rederivable file.
                if isOwner { ProtectedFile.remove(layout.url(for: .userState)) }
                return .unavailable(.resetUserStateAndTell)
            }
        }
    }

    public func save(_ state: UserState) throws {
        try prepare()
        try access.write(try JSONEncoder().encode(state), .userState, to: layout.url(for: .userState), excludeFromBackup: true)
    }
}
