#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation
import TallyDomain

extension AccountKey {
    /// Architecture's derivation (architecture.md §3.2): a truncated hex SHA-256 of `host|userID`,
    /// so no name, email or institution host ever appears in a file path or notification ID.
    public static func derive(host: String, userID: String) -> AccountKey {
        let digest = SHA256.hash(data: Data("\(host)|\(userID)".utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return AccountKey(String(hex.prefix(TallyConfig.accountKeyHexLength)))
    }
}

/// Where one account's store files live: `<root>/accounts/<accountKey>/<file>`
/// (architecture.md §3.2's layout table). `root` is the app container or App Group directory
/// chosen by the composition root; this type only knows path arithmetic, never how to reach it.
public struct StoreLayout: Sendable, Equatable {
    public let root: URL
    public let accountKey: AccountKey

    public init(root: URL, accountKey: AccountKey) { self.root = root; self.accountKey = accountKey }

    public var accountsDirectory: URL { root.appendingPathComponent("accounts") }
    public var accountDirectory: URL { accountsDirectory.appendingPathComponent(accountKey.rawValue) }
    public var installSentinel: URL { root.appendingPathComponent(".installed") }
    /// SEC1-08: written by `AccountPurger.purge` before it starts, removed only once a read-back
    /// confirms `accountDirectory` is gone. Lives beside the account directories, never inside
    /// one (that is what gets deleted), so `AccountPurger.retryPending` can still find it after a
    /// purge that did not finish.
    public var purgePendingMarker: URL { accountsDirectory.appendingPathComponent(Self.purgePendingName(accountKey)) }

    static func purgePendingName(_ accountKey: AccountKey) -> String { ".purge-pending-\(accountKey.rawValue)" }

    /// Every account with a pending-purge marker still on disk, read directly off the file system
    /// (never from `accounts.json`, whose entry a finished sign-out may have already removed).
    public static func pendingPurges(root: URL) -> [AccountKey] {
        let accountsDirectory = root.appendingPathComponent("accounts")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: accountsDirectory.path)) ?? []
        let prefix = ".purge-pending-"
        return names.filter { $0.hasPrefix(prefix) }.map { AccountKey(String($0.dropFirst(prefix.count))) }
    }

    public func url(for file: StoreFile) -> URL { accountDirectory.appendingPathComponent(Self.fileName(file)) }

    /// Exact names from architecture.md §3.2's layout table.
    public static func fileName(_ file: StoreFile) -> String {
        switch file {
        case .snapshot: return "snapshot.v1.sealed"
        case .glance: return "glance.v1.sealed"
        case .userState: return "user-state.sealed"
        case .ledger: return "sync-ledger.sealed"
        // Per account and sealed (the PERF-L brief), where §3.2 has one unsealed refresh-state.json.
        case .refreshState: return "refresh-state.sealed"
        // Item 3 (LIVE-FIX-2/LIVE-3): per-account, sealed, same tier as refreshState.
        case .etagCache: return "etag-cache.sealed"
        }
    }

    /// Every real file name this account directory should contain; anything else is orphaned
    /// (a crash-mid-write temp file) and is safe to sweep.
    public static let allFileNames = Set(StoreFile.allCases.map(fileName))
}
