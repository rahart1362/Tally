import Foundation
import Security

/// Shared helpers for the Keychain-backed adapters in this file group
/// (`KeychainCredentialStore`, `KeychainVaultKeyStore`). Kept tiny and
/// dependency-free so each adapter's own file stays readable.
enum KeychainSupport {
    /// `errSecInteractionNotAllowed` (-25308): the device is locked, or the
    /// query ran before first unlock. NEVER "no item" (security.md SEC-06 /
    /// encryption.md ENC-02: exactly the bug being fixed here).
    static let interactionNotAllowed: OSStatus = errSecInteractionNotAllowed

    /// `.secondsSince1970`, not `.iso8601`: this JSON is an internal Keychain
    /// blob format, never a Canvas wire format, so there is no reason to
    /// prefer a human-readable string over an exact round trip. The default
    /// `.iso8601` strategy's `ISO8601DateFormatter()` has no fractional-second
    /// option, so it silently truncates `accessTokenExpiresAt` to the whole
    /// second — confirmed on CI (run 36333352378): `save` then `load`
    /// produced a credential that compared unequal to the one saved.
    static var credentialEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    static var credentialDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}

/// Apple's documented technique for learning this app's real Team ID
/// ("bundle seed ID") at runtime: `$(AppIdentifierPrefix)` only expands
/// inside `.entitlements` files at build/codesign time, never in compiled
/// Swift, so a `kSecAttrAccessGroup` value that must match across the app
/// and an extension has to be assembled from a prefix read back from the
/// Keychain itself. Add a throwaway item with no access group, then read
/// back the group SecItem resolved it to; its text before the first "."
/// is the prefix.
public enum KeychainAccessGroupResolver {
    /// `nil` only if Keychain access itself is unavailable (e.g. before
    /// first unlock) — callers should treat that the same as any other
    /// `.protectedDataUnavailable` case and retry later.
    public static func resolveTeamIDPrefix(probeService: String = "dev.tally-app.tally.keychain-probe") -> String? {
        let account = "probe"
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: probeService,
            kSecAttrAccount as String: account,
        ]

        var addQuery = base
        addQuery[kSecValueData as String] = Data(account.utf8)
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        addQuery[kSecReturnAttributes as String] = true
        var result: CFTypeRef?
        var status = SecItemAdd(addQuery as CFDictionary, &result)

        if status == errSecDuplicateItem {
            var copyQuery = base
            copyQuery[kSecReturnAttributes as String] = true
            status = SecItemCopyMatching(copyQuery as CFDictionary, &result)
        }

        guard status == errSecSuccess,
              let attributes = result as? [String: Any],
              let accessGroup = attributes[kSecAttrAccessGroup as String] as? String,
              let dotIndex = accessGroup.firstIndex(of: ".")
        else { return nil }
        return String(accessGroup[..<dotIndex])
    }
}
