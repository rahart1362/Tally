import Foundation
import TallyDomain

/// The file-storage side of sign-out / erase (WP-C02). Crypto-shreds both of the account's vault
/// keys, then deletes the account's own directory — never a sibling account's, and never the
/// shared `accounts` directory itself. The caller (Security's `SignOutUseCase`/`EraseService`,
/// out of this worktree's scope) also revokes the Canvas token, removes notifications and
/// calendar events, and reloads widgets (encryption.md §3.7).
public enum AccountPurger {
    public static func purge(accountKey: AccountKey, root: URL, keyring: VaultKeyring) throws {
        let layout = StoreLayout(root: root, accountKey: accountKey)
        try VaultPurger.purge(account: accountKey.rawValue, keyring: keyring, directories: [layout.accountDirectory])
    }
}
