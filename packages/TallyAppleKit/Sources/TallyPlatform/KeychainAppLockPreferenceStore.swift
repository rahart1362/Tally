import Foundation
import Security
import TallyFeatures

/// SEC-07's setting in the Keychain (ADR 0001: "The preference lives in the Keychain, not
/// `UserDefaults`"; security.md §3.3's "Lock flag edited or restored from backup" row). One
/// generic-password item, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (the same class as the
/// credential: readable at launch and in the background, never migrated to another device), never
/// synchronizable, updated in place (never delete-then-add).
///
/// Every method is `@concurrent`: Keychain calls are IPC, so none runs on the main actor.
public final class KeychainAppLockPreferenceStore: AppLockPreferenceStoring, Sendable {
    private let service: String
    private static let account = "preference"

    /// - Parameter service: `"<bundle id>.app-lock"`; tests pass a unique one.
    public init(service: String = (Bundle.main.bundleIdentifier ?? "dev.tally-app.tally") + ".app-lock") {
        self.service = service
    }

    @concurrent
    public func load() async -> AppLockPreferenceRead {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess:
            // An undecodable item is unreadable, not absent: the lock fails closed.
            guard let data = result as? Data,
                  let preference = try? JSONDecoder().decode(AppLockPreference.self, from: data) else { return .unavailable }
            return .found(preference)
        case errSecItemNotFound:
            return .notFound
        default:
            return .unavailable
        }
    }

    @concurrent
    public func save(_ preference: AppLockPreference) async throws {
        let data = try JSONEncoder().encode(preference)
        var attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updated = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw KeychainAppLockPreferenceError.failed(status: updated) }
        attributes[kSecClass as String] = kSecClassGenericPassword
        attributes[kSecAttrService as String] = service
        attributes[kSecAttrAccount as String] = Self.account
        attributes[kSecAttrSynchronizable as String] = false
        attributes[kSecUseDataProtectionKeychain as String] = true
        let added = SecItemAdd(attributes as CFDictionary, nil)
        guard added == errSecSuccess else { throw KeychainAppLockPreferenceError.failed(status: added) }
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

public enum KeychainAppLockPreferenceError: Error, Sendable, Equatable {
    case failed(status: OSStatus)
}
