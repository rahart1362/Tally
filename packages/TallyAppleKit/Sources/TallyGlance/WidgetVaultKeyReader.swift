import CryptoKit
import Foundation
import Security
import TallyStore

/// The widget's read-only view of the vault keys (encryption.md §3.4; ENC-05): an account's
/// **widget-audience** key, from one explicit Keychain access group (the App Group's), and nothing
/// else.
///
/// - It answers only for `KeyAudience.widget`. Asked for an app-audience key (the snapshot's, the
///   ledger's, user state's) it finds none, so `VaultSealer.open` of any of those files throws
///   `keyMissing`: the widget cannot decode the snapshot even by mistake.
/// - It never adds or deletes a key: those throw `VaultError.readOnlyProcess`.
/// - It reads no credential. Its one Keychain service is `<appBundleID>.vault.widget`, the name
///   `KeychainVaultKeyStore` (TallyPlatform) stores that key under; the Canvas credential lives
///   under another service, in the app-private access group the widget is not entitled to.
///
/// It duplicates `KeychainVaultKeyStore`'s read queries because that type lives in TallyPlatform,
/// which links TallyFeatures, and the widget must not (plan 06 step 11). A hosted test proves the
/// two agree on the item names: a key the app's store writes is the key this reader returns.
public struct WidgetVaultKeyReader: VaultKeyStore {
    private let service: String
    private let accessGroup: String?

    /// - Parameters:
    ///   - appBundleID: the **app's** bundle ID (`GlanceConfiguration.appBundleID`).
    ///   - accessGroup: the explicit access group (`GlanceConfiguration.keychainAccessGroup`);
    ///     `nil` only in tests, which search the process's default group instead.
    public init(appBundleID: String, accessGroup: String?) {
        service = "\(appBundleID).vault.\(KeyAudience.widget.rawValue)"
        self.accessGroup = accessGroup
    }

    public func keyIDs(for scope: KeyScope) throws -> [UInt32] {
        var query = baseQuery() // MUTATION MW4: no audience guard, and the service follows the scope
        query[kSecAttrService as String] = service.replacingOccurrences(of: ".vault.widget", with: ".vault.\(scope.audience.rawValue)")
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecReturnAttributes as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw Self.failure(status) }
        let prefix = "\(scope.account)."
        let items = (result as? [[String: Any]]) ?? []
        return items.compactMap { item in
            (item[kSecAttrAccount as String] as? String)
                .flatMap { $0.hasPrefix(prefix) ? UInt32(String($0.dropFirst(prefix.count))) : nil }
        }
    }

    public func key(id: UInt32, for scope: KeyScope) throws -> SymmetricKey? {
        var query = baseQuery() // MUTATION MW4
        query[kSecAttrService as String] = service.replacingOccurrences(of: ".vault.widget", with: ".vault.\(scope.audience.rawValue)")
        query[kSecAttrAccount as String] = "\(scope.account).\(id)"
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw Self.failure(status) }
        return SymmetricKey(data: data)
    }

    public func add(_ key: SymmetricKey, id: UInt32, for scope: KeyScope) throws { throw VaultError.readOnlyProcess }
    public func deleteAll(for scope: KeyScope) throws { throw VaultError.readOnlyProcess }
    public func deleteEverything() throws { throw VaultError.readOnlyProcess }

    private func baseQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }

    /// `errSecInteractionNotAllowed` is "locked" (retry after unlock, delete nothing), never "no
    /// item" (encryption.md ENC-02); anything else, such as -34018 without a Team ID, is a storage
    /// error the widget reports as unavailable.
    static func failure(_ status: OSStatus) -> VaultError {
        status == errSecInteractionNotAllowed ? .protectedDataUnavailable : .storage(code: Int(status))
    }
}
