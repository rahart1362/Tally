#if canImport(Security)
import Foundation
import Security
#if canImport(CryptoKit)
import CryptoKit
#endif

/// NOT compiled in the Linux harness (no Security.framework): verify in macOS CI (simulator) and on device.
/// Item layout: service "<bundleID>.vault.<audience>", account "<accountKey>.<keyID>",
/// accessible AfterFirstUnlockThisDeviceOnly, never synchronizable, explicit access group per audience.
public struct KeychainVaultKeyStore: VaultKeyStore {
    public let bundleID: String
    public let accessGroups: [KeyAudience: String]   // .app: "<TEAMID>.<bundleID>", .widget: "group.<prefix>.tally"

    public init(bundleID: String, accessGroups: [KeyAudience: String]) {
        self.bundleID = bundleID; self.accessGroups = accessGroups
    }

    private func base(_ audience: KeyAudience) throws -> [String: Any] {
        guard let group = accessGroups[audience] else { throw VaultError.keyMissing } // e.g. widget asking for .app
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "\(bundleID).vault.\(audience.rawValue)",
                kSecAttrAccessGroup as String: group,             // explicit: an unscoped query matches ANY group
                kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
                kSecUseDataProtectionKeychain as String: true]    // only matters for the iOS-app-on-Mac case
    }

    private func fail(_ status: OSStatus) -> VaultError {
        status == errSecInteractionNotAllowed ? .protectedDataUnavailable : .storage(code: Int(status))
    }

    private func accounts(_ audience: KeyAudience) throws -> [String] {
        var q = try base(audience)
        q[kSecMatchLimit as String] = kSecMatchLimitAll
        q[kSecReturnAttributes as String] = true
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        switch status {
        case errSecSuccess: return ((out as? [[String: Any]]) ?? []).compactMap { $0[kSecAttrAccount as String] as? String }
        case errSecItemNotFound: return []
        default: throw fail(status)
        }
    }

    public func keyIDs(for scope: KeyScope) throws -> [UInt32] {
        let prefix = scope.account + "."
        return try accounts(scope.audience).filter { $0.hasPrefix(prefix) }.compactMap { UInt32($0.dropFirst(prefix.count)) }
    }

    public func key(id: UInt32, for scope: KeyScope) throws -> SymmetricKey? {
        var q = try base(scope.audience)
        q[kSecAttrAccount as String] = "\(scope.account).\(id)"
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        q[kSecReturnData as String] = true
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        switch status {
        case errSecSuccess:
            guard let data = out as? Data, data.count == 32 else { throw VaultError.malformed }
            return SymmetricKey(data: data)
        case errSecItemNotFound: return nil
        default: throw fail(status)
        }
    }

    public func add(_ key: SymmetricKey, id: UInt32, for scope: KeyScope) throws {
        var a = try base(scope.audience)
        a[kSecAttrAccount as String] = "\(scope.account).\(id)"
        a[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        a[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        let status = SecItemAdd(a as CFDictionary, nil)
        guard status == errSecSuccess else { throw fail(status) }
    }

    public func deleteAll(for scope: KeyScope) throws {
        for id in try keyIDs(for: scope) {
            var q = try base(scope.audience)
            q[kSecAttrAccount as String] = "\(scope.account).\(id)"
            let status = SecItemDelete(q as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw fail(status) }
        }
    }

    public func deleteEverything() throws {
        for audience in KeyAudience.allCases where accessGroups[audience] != nil {
            let status = SecItemDelete(try base(audience) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw fail(status) }
        }
    }
}
#endif
