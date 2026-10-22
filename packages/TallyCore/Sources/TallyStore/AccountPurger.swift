import Foundation
import TallyDomain

/// The file-storage side of sign-out / erase (WP-C02). Crypto-shreds both of the account's vault
/// keys, then deletes the account's own directory (directories, since SEC1-09: the widget's App
/// Group container holds only the glance, in its own directory, separate from everywhere else the
/// account's files live) — never a sibling account's, and never the shared `accounts` directory
/// itself. Together the two directories hold every file in `StoreLayout`'s list (`StoreFile`): the
/// snapshot, the glance, user state, the sync ledger and, since O5, the refresh record
/// (`RefreshStateStore`), so each of them goes with it. The caller (Security's
/// `SignOutUseCase`/`EraseService`, out of this worktree's scope) also revokes the Canvas token,
/// removes notifications and calendar events, and reloads widgets (encryption.md §3.7).
public enum AccountPurger {
    /// SEC1-08/SEC1-09: marks the purge pending before it starts, so a crash or a failed
    /// shred/delete leaves a trail `retryPending` can find and finish later, and only clears that
    /// marker once a read-back confirms both account directories are actually gone. `sharedRoot`
    /// is the App Group container holding the glance; `nil` (the default) when there is only the
    /// one directory (no split, or the App Group is unavailable) — then there is nothing extra to
    /// purge, same as before SEC1-09.
    public static func purge(accountKey: AccountKey, root: URL, sharedRoot: URL? = nil, keyring: VaultKeyring) throws {
        let layout = StoreLayout(root: root, accountKey: accountKey)
        let glanceLayout = StoreLayout(root: sharedRoot ?? root, accountKey: accountKey)
        try? FileManager.default.createDirectory(at: layout.accountsDirectory, withIntermediateDirectories: true)
        _ = FileManager.default.createFile(atPath: layout.purgePendingMarker.path, contents: nil)

        var directories = [layout.accountDirectory]
        if glanceLayout.accountDirectory != layout.accountDirectory { directories.append(glanceLayout.accountDirectory) }

        var purgeError: Error?
        do {
            try VaultPurger.purge(account: accountKey.rawValue, keyring: keyring, directories: directories)
        } catch {
            purgeError = error
        }

        let allGone = directories.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) }
        if allGone {
            try? FileManager.default.removeItem(at: layout.purgePendingMarker)
        }
        if let purgeError { throw purgeError }
    }

    /// The next foreground launch's retry (SEC1-08, called from `LaunchBootstrapper`): finishes
    /// any purge whose marker is still on disk. Best effort and silent either way — a marker with
    /// nothing left to shred or delete just gets cleared.
    public static func retryPending(root: URL, sharedRoot: URL? = nil, keyring: VaultKeyring) {
        for accountKey in StoreLayout.pendingPurges(root: root) {
            try? purge(accountKey: accountKey, root: root, sharedRoot: sharedRoot, keyring: keyring)
        }
    }
}
