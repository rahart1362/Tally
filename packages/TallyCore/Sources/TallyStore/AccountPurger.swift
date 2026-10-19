import Foundation
import TallyDomain

/// The file-storage side of sign-out / erase (WP-C02). Crypto-shreds both of the account's vault
/// keys, then deletes the account's own directory — never a sibling account's, and never the
/// shared `accounts` directory itself. That directory holds every file in `StoreLayout`'s list
/// (`StoreFile`): the snapshot, the glance, user state, the sync ledger and, since O5, the refresh
/// record (`RefreshStateStore`), so each of them goes with it. The caller (Security's `SignOutUseCase`/`EraseService`,
/// out of this worktree's scope) also revokes the Canvas token, removes notifications and
/// calendar events, and reloads widgets (encryption.md §3.7).
public enum AccountPurger {
    /// SEC1-08: marks the purge pending before it starts, so a crash or a failed shred/delete
    /// leaves a trail `retryPending` can find and finish later, and only clears that marker once
    /// a read-back confirms the account directory is actually gone.
    public static func purge(accountKey: AccountKey, root: URL, keyring: VaultKeyring) throws {
        let layout = StoreLayout(root: root, accountKey: accountKey)
        try? FileManager.default.createDirectory(at: layout.accountsDirectory, withIntermediateDirectories: true)
        _ = FileManager.default.createFile(atPath: layout.purgePendingMarker.path, contents: nil)

        var purgeError: Error?
        do {
            try VaultPurger.purge(account: accountKey.rawValue, keyring: keyring, directories: [layout.accountDirectory])
        } catch {
            purgeError = error
        }

        if !FileManager.default.fileExists(atPath: layout.accountDirectory.path) {
            try? FileManager.default.removeItem(at: layout.purgePendingMarker)
        }
        if let purgeError { throw purgeError }
    }

    /// The next foreground launch's retry (SEC1-08, called from `LaunchBootstrapper`): finishes
    /// any purge whose marker is still on disk. Best effort and silent either way — a marker with
    /// nothing left to shred or delete just gets cleared.
    public static func retryPending(root: URL, keyring: VaultKeyring) {
        for accountKey in StoreLayout.pendingPurges(root: root) {
            try? purge(accountKey: accountKey, root: root, keyring: keyring)
        }
    }
}
