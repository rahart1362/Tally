import Foundation
import TallyDomain

public enum SyncLedgerLoadResult: Equatable, Sendable {
    case loaded(SyncLedger)
    case absent
    case unavailable(VaultDisposition)
}

/// The store side of `sync-ledger.sealed` (architecture.md §3.1/§3.2, WP-C02). Unlike
/// `UserStateStore`, the ledger is rederivable (a reconciler can rebuild it by re-scanning the
/// dedicated Tally calendar and the pending-notification list), so a decode failure discards and
/// rebuilds it rather than resetting-and-telling the user.
public actor SyncLedgerStore {
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

    public func load() -> SyncLedgerLoadResult {
        switch access.read(.ledger, at: layout.url(for: .ledger)) {
        case .absent:
            return .absent
        case .failed(_, let disposition):
            return .unavailable(disposition)
        case .plaintext(let data):
            do {
                return .loaded(try SyncLedgerMigration.decode(data))
            } catch {
                // Rederivable: discard so the caller reconciles from scratch (StoreFile.ledger.isRederivable).
                if isOwner { ProtectedFile.remove(layout.url(for: .ledger)) }
                return .unavailable(.discardAndRebuild)
            }
        }
    }

    public func save(_ ledger: SyncLedger) throws {
        try prepare()
        try access.write(try JSONEncoder().encode(ledger), .ledger, to: layout.url(for: .ledger), excludeFromBackup: true)
    }
}
