import Foundation
import TallyDomain
import TallyStore

/// What the widget can say about the glance right now.
public enum GlanceReadResult: Equatable, Sendable {
    case loaded(GlanceProjection)
    /// No account directory: never signed in, or signed out (sign-out removes the directory).
    case noAccount
    /// An account directory with no glance the widget can open: the first sync has not committed
    /// yet, or the account was purged (its keys are shredded first, so what is left is `keyMissing`).
    case noGlance
    /// Protected data is unavailable: before the first unlock after a restart. Nothing is deleted.
    case locked
    /// The App Group container or the Keychain could not be used, for example
    /// `errSecMissingEntitlement` (-34018) without a Team ID (GO-LIVE GL-02). The widget shows its
    /// placeholder; nothing is deleted.
    case unavailable
}

/// Reads the glance, and only the glance (plan 06 step 11; perf-app-runtime.md §2.4 W1-W3).
///
/// For each account directory it builds `SnapshotStore(root:accountKey:sealer:isOwner: false)`
/// over a `VaultSealer(…, mayCreateKeys: false)` and calls `loadGlance()`: it reads at most
/// `glance.v1.sealed` (≤ 16 KB, `TallyConfig.glanceSizeBudgetBytes`), with keys from a store that
/// answers only for the widget audience, so it cannot open the snapshot even by mistake (the
/// snapshot's key is app-audience: `keyMissing`). It never decodes the snapshot, never writes or
/// deletes a file (`isOwner: false`), never creates a key, and has no network or credential access:
/// this module links neither TallyCanvasAPI nor TallySync (CI's widget link gate).
public struct GlanceReader: Sendable {
    /// `<App Group container>/Library/Application Support/Tally` (`GlanceStoreLocation`), or `nil`
    /// when the container is unavailable.
    public let storeRoot: URL?
    public let keyStore: any VaultKeyStore

    public init(storeRoot: URL?, keyStore: any VaultKeyStore) {
        self.storeRoot = storeRoot
        self.keyStore = keyStore
    }

    public func read() async -> GlanceReadResult {
        guard let storeRoot else { return .unavailable }
        let accounts = Self.accountKeys(in: storeRoot)
        guard !accounts.isEmpty else { return .noAccount }
        // v1 has one active account (PMO R8). A second directory can exist only while a sign-out's
        // purge is under way, and its keys are shredded first, so its glance no longer opens. If
        // two do open, the newer glance wins.
        let keyring = VaultKeyring(store: keyStore)
        var newest: GlanceProjection?
        var sawLocked = false
        var sawUnavailable = false
        for account in accounts {
            let sealer = VaultSealer(account: account.rawValue, keyring: keyring, mayCreateKeys: false)
            let store = SnapshotStore(root: storeRoot, accountKey: account, sealer: sealer, isOwner: false)
            switch await store.loadGlance() {
            case .loaded(let glance):
                if let current = newest, current.asOf >= glance.asOf { continue }
                newest = glance
            case .absent:
                continue
            case .unavailable(.retryAfterUnlock):
                sawLocked = true
            case .unavailable(.keepAndReport):
                sawUnavailable = true
            case .unavailable(.discardAndRebuild), .unavailable(.resetUserStateAndTell):
                continue // unopenable (a purged account's key is gone): the app rebuilds or removes it
            }
        }
        if let newest { return .loaded(newest) }
        if sawLocked { return .locked }
        if sawUnavailable { return .unavailable }
        return .noGlance
    }

    /// The account directories under `<storeRoot>/accounts` (`StoreLayout`), sorted. A plain
    /// directory listing: no file timestamps (a required-reason API). Hidden entries and files are
    /// skipped.
    static func accountKeys(in storeRoot: URL) -> [AccountKey] {
        let accounts = storeRoot.appendingPathComponent("accounts", isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: accounts.path)) ?? []
        return names.sorted().compactMap { name in
            guard !name.hasPrefix(".") else { return nil }
            var isDirectory: ObjCBool = false
            let path = accounts.appendingPathComponent(name, isDirectory: true).path
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
            return AccountKey(name)
        }
    }
}
