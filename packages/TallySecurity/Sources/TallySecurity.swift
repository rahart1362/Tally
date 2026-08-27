import Foundation
import Security

/// Securely stores and retrieves OAuth tokens using the iOS Keychain.
/// Uses kSecAttrAccessibleWhenUnlockedThisDeviceOnly to prevent backup extraction.
public final class KeychainManager {
    public static let shared = KeychainManager()
    private let service = "com.tally.app"
    
    private init() {}
    
    /// Save a token string to the Keychain under the given account key.
    public func save(token: String, forAccount account: String) throws {
        guard let data = token.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        
        // Delete any existing item first to avoid errSecDuplicateItem
        delete(account: account)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status: status)
        }
    }
    
    /// Retrieve a token string from the Keychain for the given account key.
    public func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return token
    }
    
    /// Delete a token from the Keychain for the given account key.
    @discardableResult
    public func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    /// Check whether a token exists for the given account.
    public func hasToken(forAccount account: String) -> Bool {
        return load(account: account) != nil
    }
}

public enum KeychainError: Error, LocalizedError {
    case encodingFailed
    case saveFailed(status: OSStatus)
    
    public var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode token data."
        case .saveFailed(let status):
            return "Keychain save failed with status: \(status)"
        }
    }
}
