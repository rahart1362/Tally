import Foundation
import TallyDomain

public enum RefreshStateLoadResult: Equatable, Sendable {
    case loaded(RefreshRecord)
    /// Never written, or discarded (an old version, or an undecodable blob): the last attempt is unknown.
    case absent
    /// Device locked, or an unclassified I/O error; the file is left as it is.
    case unavailable(VaultDisposition)
}

/// The store side of `refresh-state.sealed` (O5, PERF-L): one account's `RefreshRecord`, so a launch
/// knows when the last refresh was attempted and how it ended, and `FreshnessRules.shouldStart`
/// can throttle the launch refresh across launches as it already does within one. It holds no
/// student content (timestamps, a trigger and a failure category), but it lives with the account's
/// other files: sealed with the app key, in the account directory, so sign-out's purge
/// (`AccountPurger`) shreds and deletes it with them, and the orphan sweep keeps it
/// (`StoreLayout.allFileNames`).
///
/// Rederivable: a record that cannot be read or decoded is discarded, and the next launch refreshes
/// as if none had ever been written. A struct, not an actor: `RefreshCoordinator` writes it
/// synchronously on its own actor when a run ends, so a sign-out's epoch bump can never slip in
/// between its check and the write (a write after the purge would re-create the account directory
/// and mint a new key for a signed-out account).
public struct RefreshStateStore: Sendable {
    /// Bumped when `RefreshRecord`'s stored shape changes incompatibly; any other version is discarded.
    public static let currentVersion = 1

    private let layout: StoreLayout
    private let access: SealedFileAccess
    private let isOwner: Bool

    public init(root: URL, accountKey: AccountKey, sealer: any SnapshotSealer, isOwner: Bool = true) {
        layout = StoreLayout(root: root, accountKey: accountKey)
        access = SealedFileAccess(sealer: sealer, isOwner: isOwner)
        self.isOwner = isOwner
    }

    public func load() -> RefreshStateLoadResult {
        let url = layout.url(for: .refreshState)
        switch access.read(.refreshState, at: url) {
        case .absent:
            return .absent
        case .failed(_, let disposition):
            // `SealedFileAccess` already removed a blob that cannot be opened (discard and rebuild).
            return disposition == .discardAndRebuild ? .absent : .unavailable(disposition)
        case .plaintext(let data):
            guard let stored = try? JSONDecoder().decode(StoredRefreshState.self, from: data),
                  stored.version == Self.currentVersion else {
                if isOwner { ProtectedFile.remove(url) }
                return .absent
            }
            return .loaded(stored.record)
        }
    }

    /// The record, or `nil` whenever `load()` has none to give.
    public func loadRecord() -> RefreshRecord? {
        if case .loaded(let record) = load() { return record }
        return nil
    }

    public func save(_ record: RefreshRecord) throws {
        try ProtectedFile.prepareDirectory(layout.accountDirectory, excludeFromBackup: true)
        let data = try JSONEncoder().encode(StoredRefreshState(version: Self.currentVersion, record: record))
        try access.write(data, .refreshState, to: layout.url(for: .refreshState), excludeFromBackup: true)
    }

    /// The record an account's coordinator (and the first paint's freshness) starts from: the
    /// persisted one, unless the committed data is newer than its last success, which happens when
    /// the app stopped between a commit and the record's write. Then that commit counts as the last
    /// success (its failure, if any, is older). With no persisted record this is today's seed: a
    /// success at the committed data's `fetchedAt`, and no attempt known, so the launch refreshes.
    /// No in-flight mark survives a relaunch.
    public static func startingRecord(persisted: RefreshRecord?, committedDataFetchedAt fetchedAt: Date?) -> RefreshRecord {
        var record = persisted ?? RefreshRecord()
        if let fetchedAt, record.lastSuccessAt.map({ $0 < fetchedAt }) ?? true {
            record.succeeded(dataFetchedAt: fetchedAt)
        }
        return record.restoredAfterLaunch()
    }
}

/// The file's JSON: a version, then the record.
private struct StoredRefreshState: Codable {
    let version: Int
    let record: RefreshRecord
}
