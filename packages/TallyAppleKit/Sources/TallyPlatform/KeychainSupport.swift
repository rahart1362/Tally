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

    /// Neither of `JSONEncoder`'s two built-in numeric date strategies
    /// round-trips a `Date` exactly. `.iso8601`'s `ISO8601DateFormatter()`
    /// has no fractional-second option, so it truncates to the whole second
    /// (confirmed on CI run 36333352378). Less obviously, `.secondsSince1970`
    /// and `.millisecondsSince1970` are ALSO lossy: verified locally (a
    /// throwaway `swift:6.4` container run) that encoding
    /// `Date().addingTimeInterval(3600)` and decoding it back differs by
    /// ~1.19e-7 seconds — exactly `2^-23`, i.e. Float32 machine epsilon,
    /// meaning the JSON-number path rounds the Double through Float32
    /// somewhere. Confirmed again on the real CI simulator (run
    /// 36335209586) with `.secondsSince1970`: `save` then `load` still
    /// compared unequal. This is an internal Keychain blob format, never a
    /// Canvas wire format, so there is no reason to go through a JSON
    /// *number* at all: encode the date as the decimal string of its
    /// `Double` bit pattern, which round-trips exactly because JSON
    /// *strings* aren't subject to this numeric-formatting path (verified
    /// exact, `diff == 0.0`, in the same local check).
    static var credentialEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(String(date.timeIntervalSince1970.bitPattern))
        }
        return encoder
    }

    static var credentialDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let bits = UInt64(text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "not a bit-pattern integer")
            }
            return Date(timeIntervalSince1970: Double(bitPattern: bits))
        }
        return decoder
    }
}

/// Apple's documented technique for learning a real, usable Keychain access
/// group at runtime: `$(AppIdentifierPrefix)` only expands inside
/// `.entitlements` files at build/codesign time, never in compiled Swift.
/// Add a throwaway item with no access group, then read back the group
/// SecItem actually resolved it to (normally the app's own private group).
public enum KeychainAccessGroupResolver {
    /// `nil` only if Keychain access itself is unavailable (e.g. before
    /// first unlock) — callers should treat that the same as any other
    /// `.protectedDataUnavailable` case and retry later.
    public static func resolveDefaultAccessGroup(probeService: String = "dev.tally-app.tally.keychain-probe") -> String? {
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
              let accessGroup = attributes[kSecAttrAccessGroup as String] as? String
        else { return nil }
        return accessGroup
    }

    /// Derives the access-group string for a *different* suffix (e.g. an
    /// App Group id) from one already known to be real and usable (e.g.
    /// `resolveDefaultAccessGroup()`, which ends with this app's own bundle
    /// id), by swapping the trailing `knownSuffix` for `suffix` and
    /// preserving whatever precedes it — empty for local/ad-hoc signing (no
    /// Team ID at all), `"TEAMID."` for a real provisioning profile.
    ///
    /// Deliberately NOT "take the text before the first '.'": a reverse-DNS
    /// bundle id contains dots of its own, so with no real Team ID prefix
    /// (confirmed for this repo's ad-hoc CI signing identity, "Sign to Run
    /// Locally") the resolved default group is exactly the bundle id, e.g.
    /// `"dev.tally-app.tally"` — and "before the first dot" wrongly reads
    /// `"dev"` as a fake prefix. Confirmed wrong on CI run 36335209586:
    /// `SecItemAdd` failed with `errSecMissingEntitlement` (-34018) because
    /// the reconstructed group didn't match anything the process was
    /// actually entitled to.
    public static func accessGroup(_ knownGroup: String, replacingKnownSuffix knownSuffix: String, with suffix: String) -> String? {
        guard knownGroup.hasSuffix(knownSuffix) else { return nil }
        return String(knownGroup.dropLast(knownSuffix.count)) + suffix
    }
}
