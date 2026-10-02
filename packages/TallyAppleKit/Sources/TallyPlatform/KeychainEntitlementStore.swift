import Foundation
import Security
import TallyDomain
import TallyFeatures

/// PAY-04: the last verified entitlement in the Keychain (`EntitlementRecord`: an expiry per role
/// and the device time it was verified; never a receipt, a transaction ID or a price). One
/// generic-password item, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (readable at launch
/// and in the background, never migrated to another device), never synchronizable, updated in
/// place (never delete-then-add). The same item class as the Canvas credential and the app-lock
/// setting (`KeychainAppLockPreferenceStore`).
///
/// Dates are stored as their exact bit pattern (`KeychainSupport`'s coders): JSON numbers lose
/// precision, and the record's expiry must round-trip exactly.
///
/// Every method is `@concurrent`: Keychain calls are IPC, so none runs on the main actor.
public final class KeychainEntitlementStore: EntitlementRecordStoring, Sendable {
    private let service: String
    private static let account = "record"

    /// - Parameter service: `"<bundle id>.entitlement"`; tests pass a unique one.
    public init(service: String = (Bundle.main.bundleIdentifier ?? "dev.tally-app.tally") + ".entitlement") {
        self.service = service
    }

    @concurrent
    public func load() async -> EntitlementRecordRead {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess:
            // An undecodable item is unreadable, not absent: access fails closed until StoreKit answers.
            guard let data = result as? Data,
                  let record = try? KeychainSupport.credentialDecoder.decode(EntitlementRecord.self, from: data) else {
                return .unavailable
            }
            return .found(record)
        case errSecItemNotFound:
            return .notFound
        default:
            return .unavailable
        }
    }

    @concurrent
    public func save(_ record: EntitlementRecord) async throws {
        let data = try KeychainSupport.credentialEncoder.encode(record)
        var attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updated = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw KeychainEntitlementStoreError.failed(status: updated) }
        attributes[kSecClass as String] = kSecClassGenericPassword
        attributes[kSecAttrService as String] = service
        attributes[kSecAttrAccount as String] = Self.account
        attributes[kSecAttrSynchronizable as String] = false
        attributes[kSecUseDataProtectionKeychain as String] = true
        let added = SecItemAdd(attributes as CFDictionary, nil)
        guard added == errSecSuccess else { throw KeychainEntitlementStoreError.failed(status: added) }
    }

    @concurrent
    public func reset() async {
        _ = SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: Self.account]
    }
}

public enum KeychainEntitlementStoreError: Error, Sendable, Equatable {
    case failed(status: OSStatus)
}
