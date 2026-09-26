#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation
@testable import TallyVault

extension Data {
    init(hex: String) { self.init(stride(from: 0, to: hex.count, by: 2).map { i -> UInt8 in
        let s = hex.index(hex.startIndex, offsetBy: i); return UInt8(hex[s..<hex.index(s, offsetBy: 2)], radix: 16)! }) }
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}

/// Linux stand-in for the Keychain: fault injection + per-audience visibility (models access groups).
final class InMemoryKeyStore: VaultKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [KeyScope: [UInt32: Data]] = [:]
    private var _failure: VaultError?
    let visibleAudiences: Set<KeyAudience>
    init(visible: Set<KeyAudience> = Set(KeyAudience.allCases)) { visibleAudiences = visible }
    /// A second process view onto the same backing store (e.g. the widget with only the App Group).
    func view(visible: Set<KeyAudience>) -> InMemoryKeyStore { let v = InMemoryKeyStore(visible: visible); v.backing = self; return v }
    private var backing: InMemoryKeyStore?
    private var root: InMemoryKeyStore { backing ?? self }

    var failure: VaultError? { get { root.lock.withLock { root._failure } } set { root.lock.withLock { root._failure = newValue } } }
    func count(_ s: KeyScope) -> Int { root.lock.withLock { root.items[s]?.count ?? 0 } }

    private func guarded<T>(_ scope: KeyScope?, _ body: (inout [KeyScope: [UInt32: Data]]) throws -> T) throws -> T {
        if let scope, !visibleAudiences.contains(scope.audience) { throw VaultError.keyMissing }
        return try root.lock.withLock { if let f = root._failure { throw f }; return try body(&root.items) }
    }
    func keyIDs(for s: KeyScope) throws -> [UInt32] { try guarded(s) { Array(($0[s] ?? [:]).keys) } }
    func key(id: UInt32, for s: KeyScope) throws -> SymmetricKey? { try guarded(s) { $0[s]?[id].map { SymmetricKey(data: $0) } } }
    func add(_ k: SymmetricKey, id: UInt32, for s: KeyScope) throws { try guarded(s) { $0[s, default: [:]][id] = k.withUnsafeBytes { Data($0) } } }
    func deleteAll(for s: KeyScope) throws { try guarded(s) { $0[s] = [:] } }
    func deleteEverything() throws { try guarded(nil) { $0.removeAll() } }
}

/// Test double for SnapshotSealer that injects a failure on open (used to exercise dispositions).
struct FailingSealer: SnapshotSealer {
    let error: VaultError
    func seal(_ plaintext: Data, file: StoreFile) throws -> Data { plaintext }
    func open(_ sealed: Data, file: StoreFile) throws -> Data { throw error }
}

func tempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("vault-\(UUID().uuidString)")
    try ProtectedFile.prepareDirectory(url, excludeFromBackup: true)
    return url
}
