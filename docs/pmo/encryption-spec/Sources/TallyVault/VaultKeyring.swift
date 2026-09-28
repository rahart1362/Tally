#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation

/// Darwin: `KeychainVaultKeyStore`. Linux tests: in-memory fake. Implementations MUST map
/// errSecInteractionNotAllowed -> `.protectedDataUnavailable` and errSecItemNotFound -> nil / [].
public protocol VaultKeyStore: Sendable {
    func keyIDs(for scope: KeyScope) throws -> [UInt32]
    func key(id: UInt32, for scope: KeyScope) throws -> SymmetricKey?
    func add(_ key: SymmetricKey, id: UInt32, for scope: KeyScope) throws
    func deleteAll(for scope: KeyScope) throws
    /// Every Tally vault key on the device (all accounts, both audiences). Used by install reconcile.
    func deleteEverything() throws
}

/// Synchronous (SnapshotSealer is synchronous) and lock-serialised, so two stores in one process
/// can never mint two keys for one scope. One instance per process, built at the composition root.
public final class VaultKeyring: @unchecked Sendable {
    private let store: VaultKeyStore
    private let lock = NSLock()
    public init(store: VaultKeyStore) { self.store = store }

    public func key(id: UInt32, for scope: KeyScope) throws -> SymmetricKey? {
        try lock.withLock { try store.key(id: id, for: scope) }
    }

    public func currentKey(for scope: KeyScope, createIfMissing: Bool) throws -> (id: UInt32, key: SymmetricKey)? {
        try lock.withLock {
            let ids = try store.keyIDs(for: scope)
            if ids.count == 1, let key = try store.key(id: ids[0], for: scope) { return (ids[0], key) }
            guard createIfMissing else { return nil }
            if !ids.isEmpty { try store.deleteAll(for: scope) }  // invariant: exactly one key per scope
            let id = UInt32.random(in: 1...UInt32.max)          // random: a pre-purge blob can never match
            let key = SymmetricKey(size: .bits256)
            try store.add(key, id: id, for: scope)
            return (id, key)
        }
    }

    /// Crypto-shred one account: afterwards its blobs (and any backup copies) are undecryptable.
    public func shred(account: String) throws {
        try lock.withLock { for a in KeyAudience.allCases { try store.deleteAll(for: KeyScope(account: account, audience: a)) } }
    }

    public func shredEverything() throws { try lock.withLock { try store.deleteEverything() } }
}

/// Conforms to Architecture's `SnapshotSealer`. One instance per account.
/// The widget extension constructs it with `mayCreateKeys: false` and a key store that only
/// holds the App Group access group, so it can open `glance` and nothing else.
public struct VaultSealer: SnapshotSealer {
    public let account: String
    public let keyring: VaultKeyring
    public let mayCreateKeys: Bool

    public init(account: String, keyring: VaultKeyring, mayCreateKeys: Bool) {
        self.account = account; self.keyring = keyring; self.mayCreateKeys = mayCreateKeys
    }

    public func seal(_ plaintext: Data, file: StoreFile) throws -> Data {
        guard mayCreateKeys else { throw VaultError.readOnlyProcess }
        let scope = KeyScope(account: account, audience: file.audience)
        guard let current = try keyring.currentKey(for: scope, createIfMissing: true) else { throw VaultError.keyMissing }
        return try SealedBlob.seal(plaintext, header: SealedBlobHeader(file: file, keyID: current.id), key: current.key)
    }

    public func open(_ sealed: Data, file: StoreFile) throws -> Data {
        let header = try SealedBlobHeader.decode(from: sealed)
        guard header.file == file else { throw VaultError.fileMismatch }
        guard let key = try keyring.key(id: header.keyID, for: KeyScope(account: account, audience: file.audience)) else {
            throw VaultError.keyMissing
        }
        return try SealedBlob.open(sealed, key: key).plaintext
    }
}
