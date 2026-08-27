import Foundation
import Security
import LocalAuthentication

// MARK: - Keychain Manager

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

// MARK: - Biometric Authentication Manager

/// Manages Face ID / Touch ID authentication for app unlock.
/// The user can enable biometric lock from Settings after initial Canvas authentication.
@MainActor
public final class BiometricAuthManager: ObservableObject {
    public static let shared = BiometricAuthManager()
    
    /// Whether the user has enabled biometric lock in Settings.
    @Published public var isBiometricEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isBiometricEnabled, forKey: biometricEnabledKey)
        }
    }
    
    /// Whether the app is currently locked and needs biometric unlock.
    @Published public var isLocked: Bool = false
    
    /// The type of biometric available on this device (faceID, touchID, or none).
    @Published public private(set) var biometricType: LABiometryType = .none
    
    /// Whether the device supports any biometric authentication.
    public var isBiometricAvailable: Bool {
        biometricType != .none
    }
    
    /// Human-readable name for the available biometric type.
    public var biometricName: String {
        switch biometricType {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .opticID:
            return "Optic ID"
        @unknown default:
            return "Biometrics"
        }
    }
    
    /// SF Symbol icon name for the available biometric type.
    public var biometricIconName: String {
        switch biometricType {
        case .faceID:
            return "faceid"
        case .touchID:
            return "touchid"
        case .opticID:
            return "opticid"
        @unknown default:
            return "lock.shield"
        }
    }
    
    private let biometricEnabledKey = "com.tally.biometricEnabled"
    
    private init() {
        self.isBiometricEnabled = UserDefaults.standard.bool(forKey: biometricEnabledKey)
        checkBiometricAvailability()
    }
    
    /// Checks what biometric hardware is available on this device.
    public func checkBiometricAvailability() {
        let context = LAContext()
        var error: NSError?
        
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            biometricType = context.biometryType
        } else {
            biometricType = .none
        }
    }
    
    /// Lock the app. Called when the app enters background (if biometric is enabled).
    public func lockIfEnabled() {
        if isBiometricEnabled {
            isLocked = true
        }
    }
    
    /// Attempt to authenticate the user with Face ID / Touch ID.
    /// Returns true if authentication succeeded, false otherwise.
    @discardableResult
    public func authenticate() async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Use Passcode"
        
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // Biometric not available — fall back to unlocked state
            isLocked = false
            return true
        }
        
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Unlock Tally to view your academic data"
            )
            if success {
                isLocked = false
            }
            return success
        } catch {
            // Authentication failed or cancelled — remain locked
            return false
        }
    }
    
    /// Toggle biometric on — requires a successful authentication first to confirm identity.
    /// Returns true if the toggle was successful.
    public func enableBiometric() async -> Bool {
        let authenticated = await authenticate()
        if authenticated {
            isBiometricEnabled = true
            isLocked = false
        }
        return authenticated
    }
    
    /// Disable biometric lock (no auth required to disable).
    public func disableBiometric() {
        isBiometricEnabled = false
        isLocked = false
    }
}
