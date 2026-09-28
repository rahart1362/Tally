#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation
import Synchronization
import TallyStore

/// Linux/simulator stand-in for the Keychain (`TallyStore.VaultKeyStore`): fault injection plus
/// per-audience visibility, so a test can model "the widget's key store only holds the App Group
/// access group" without Security.framework.
public final class InMemoryVaultKeyStore: VaultKeyStore, Sendable {
    private struct State {
        var items: [KeyScope: [UInt32: Data]] = [:]
        var failure: VaultError?
    }
    /// A class (not the `Mutex` itself) so a "view" can share the same backing storage by
    /// reference: `Mutex` is non-copyable, so it cannot be duplicated onto a second instance.
    private final class Storage: Sendable {
        let state = Mutex(State())
    }

    private let storage: Storage
    public let visibleAudiences: Set<KeyAudience>

    public init(visible: Set<KeyAudience> = Set(KeyAudience.allCases)) {
        storage = Storage()
        visibleAudiences = visible
    }

    private init(storage: Storage, visible: Set<KeyAudience>) {
        self.storage = storage
        visibleAudiences = visible
    }

    /// A second process' view onto the same backing store (e.g. the widget, with only the App
    /// Group audience visible).
    public func view(visible: Set<KeyAudience>) -> InMemoryVaultKeyStore {
        InMemoryVaultKeyStore(storage: storage, visible: visible)
    }

    public var failure: VaultError? {
        get { storage.state.withLock { $0.failure } }
        set { storage.state.withLock { $0.failure = newValue } }
    }

    public func count(_ scope: KeyScope) -> Int { storage.state.withLock { $0.items[scope]?.count ?? 0 } }

    private func guarded<T>(_ scope: KeyScope?, _ body: (inout [KeyScope: [UInt32: Data]]) throws -> T) throws -> T {
        if let scope, !visibleAudiences.contains(scope.audience) { throw VaultError.keyMissing }
        return try storage.state.withLock {
            if let failure = $0.failure { throw failure }
            return try body(&$0.items)
        }
    }

    public func keyIDs(for scope: KeyScope) throws -> [UInt32] {
        try guarded(scope) { Array(($0[scope] ?? [:]).keys) }
    }

    public func key(id: UInt32, for scope: KeyScope) throws -> SymmetricKey? {
        try guarded(scope) { $0[scope]?[id].map { SymmetricKey(data: $0) } }
    }

    public func add(_ key: SymmetricKey, id: UInt32, for scope: KeyScope) throws {
        try guarded(scope) { $0[scope, default: [:]][id] = key.withUnsafeBytes { Data($0) } }
    }

    public func deleteAll(for scope: KeyScope) throws {
        try guarded(scope) { $0[scope] = [:] }
    }

    public func deleteEverything() throws {
        try guarded(nil) { $0.removeAll() }
    }
}
