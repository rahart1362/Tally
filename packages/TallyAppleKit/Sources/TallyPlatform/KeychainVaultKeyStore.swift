#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation
import Security
import TallyStore

/// `VaultKeyStore` over the Keychain (encryption.md §3.4 / WP-ENC-03). One
/// generic-password item per `(account, audience, keyID)`, service
/// `"<bundleID>.vault.<audience>"`, account `"<accountKey>.<keyID>"`,
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, never synchronizable,
/// with an **explicit** `kSecAttrAccessGroup` on every query.
///
/// Two access groups matter here (encryption.md §3.2/§3.4):
/// - `appAccessGroup`: the app-private group. Every `.app`-audience key
///   (snapshot, ledger, user-state) lives only here — the widget extension
///   has no entitlement for it, so it can never even query these items.
/// - `widgetAccessGroup`: the App Group group. The single `.glance`
///   (`.widget`-audience) key lives here so the widget extension — running
///   with only the App Group entitlement — can open `glance` and nothing
///   else (`StoreFile.audience` already routes `.glance` to `.widget`,
///   everything else to `.app`; this store just stores each audience under
///   the matching group).
///
/// Both group parameters are optional so a caller without a signed App
/// Group yet (local development, most hosted tests) can omit them and fall
/// back to the process's implicit default group.
public final class KeychainVaultKeyStore: VaultKeyStore, Sendable {
    private let bundleID: String
    private let appAccessGroup: String?
    private let widgetAccessGroup: String?

    public init(
        bundleID: String = Bundle.main.bundleIdentifier ?? "dev.tally-app.tally",
        appAccessGroup: String? = nil,
        widgetAccessGroup: String? = nil
    ) {
        self.bundleID = bundleID
        self.appAccessGroup = appAccessGroup
        self.widgetAccessGroup = widgetAccessGroup
    }

    // MARK: - VaultKeyStore

    public func keyIDs(for scope: KeyScope) throws -> [UInt32] {
        var query = baseQuery(audience: scope.audience)
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecReturnAttributes as String] = true

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw Self.mapFailure(status) }

        let prefix = accountPrefix(scope)
        let items = (result as? [[String: Any]]) ?? []
        return items.compactMap { item in
            (item[kSecAttrAccount as String] as? String)
                .flatMap { $0.hasPrefix(prefix) ? UInt32(String($0.dropFirst(prefix.count))) : nil }
        }
    }

    public func key(id: UInt32, for scope: KeyScope) throws -> SymmetricKey? {
        var query = baseQuery(audience: scope.audience)
        query[kSecAttrAccount as String] = account(scope, keyID: id)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw Self.mapFailure(status) }
        return SymmetricKey(data: data)
    }

    public func add(_ key: SymmetricKey, id: UInt32, for scope: KeyScope) throws {
        var attributes = baseQuery(audience: scope.audience)
        attributes[kSecAttrAccount as String] = account(scope, keyID: id)
        attributes[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        attributes[kSecAttrSynchronizable as String] = false
        attributes[kSecUseDataProtectionKeychain as String] = true

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw Self.mapFailure(status) }
    }

    /// Removes every key for this one `(account, audience)` scope — never
    /// another account sharing the same service+audience.
    public func deleteAll(for scope: KeyScope) throws {
        for id in try keyIDs(for: scope) {
            var query = baseQuery(audience: scope.audience)
            query[kSecAttrAccount as String] = account(scope, keyID: id)
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw Self.mapFailure(status) }
        }
    }

    /// Every Tally vault key this process's Keychain groups can see, both
    /// audiences, every account. Used only by `VaultBootstrap.reconcileInstall`
    /// (encryption.md §3.4) in the main app process — the widget extension's
    /// store (`isOwner: false` at the `VaultSealer` layer) never calls this.
    public func deleteEverything() throws {
        for audience in KeyAudience.allCases {
            let status = SecItemDelete(baseQuery(audience: audience) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw Self.mapFailure(status) }
        }
    }

    // MARK: - Private

    private func service(for audience: KeyAudience) -> String { "\(bundleID).vault.\(audience.rawValue)" }

    private func accessGroup(for audience: KeyAudience) -> String? {
        audience == .widget ? widgetAccessGroup : appAccessGroup
    }

    private func baseQuery(audience: KeyAudience) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service(for: audience),
        ]
        if let group = accessGroup(for: audience) { query[kSecAttrAccessGroup as String] = group }
        return query
    }

    private func account(_ scope: KeyScope, keyID: UInt32) -> String { "\(scope.account).\(keyID)" }
    private func accountPrefix(_ scope: KeyScope) -> String { "\(scope.account)." }

    private static func mapFailure(_ status: OSStatus) -> VaultError {
        status == KeychainSupport.interactionNotAllowed ? .protectedDataUnavailable : .storage(code: Int(status))
    }
}
