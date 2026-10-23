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

    /// EB-26 ("Erase Saved Data", SEC2-07's owner ruling): unlike `purge` above (sign-out, and
    /// account deletion), this keeps `user-state.sealed` — Hide Course Names and the other
    /// privacy toggles — fully readable. It still removes every Canvas-derived file: the
    /// snapshot, the sync ledger, the refresh record and the glance.
    ///
    /// `userState` shares the account's `.app`-audience vault key with `snapshot`, `ledger` and
    /// `refreshState` (`StoreFile.audience`) — there is no per-file key, only one per (account,
    /// audience) pair — so shredding `.app` here, even to help delete the other three, would
    /// leave the one file this call must keep permanently undecryptable. Only `.widget` (the
    /// glance) is shredded.
    ///
    /// Deliberately simpler than `purge`: no pending-purge marker, because this call is never
    /// meant to finish with the account directory empty (`userState` stays on purpose), so a
    /// later `retryPending` must never mistake it for an interrupted full purge and wipe that
    /// file too. Best effort, like every other step in this flow: a failed delete here is picked
    /// up the next time Erase Saved Data or a full sign-out runs, never automatically.
    public static func eraseCanvasData(accountKey: AccountKey, root: URL, sharedRoot: URL? = nil, keyring: VaultKeyring) throws {
        let layout = StoreLayout(root: root, accountKey: accountKey)
        let glanceLayout = StoreLayout(root: sharedRoot ?? root, accountKey: accountKey)

        var shredError: Error?
        do { try keyring.shred(account: accountKey.rawValue, audiences: [.widget]) } catch { shredError = error }

        for file in StoreFile.allCases where file != .userState && file != .glance {
            ProtectedFile.remove(layout.url(for: file))
        }
        ProtectedFile.remove(glanceLayout.url(for: .glance))

        if let shredError { throw shredError }
    }
}
