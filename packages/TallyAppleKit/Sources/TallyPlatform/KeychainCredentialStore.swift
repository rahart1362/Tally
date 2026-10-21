import Foundation
import Security
import TallyCanvasAPI

/// `CredentialStore` over the Keychain (security.md SEC-04 / §3.2 item 7,
/// ADR 0001). One generic-password item, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
/// so background refresh can read it while the device is locked (encryption.md
/// D-E2/ENC-02), never synchronizable, and with **no** access group — the
/// review is explicit that extensions must never read Canvas tokens.
///
/// `CredentialStore`'s protocol shape (`TallyCanvasAPI`, read-only from this
/// package) is `load() -> CanvasCredential?` / `save(_:) throws` / `delete()`:
/// no account parameter, matching D5 (v1 ships a single active account).
/// Update-or-add therefore matches on **service alone**: `SecItemUpdate`
/// against the one item this service can ever hold, replacing both its
/// secret data and its `kSecAttrAccount` (rewritten from the credential being
/// saved) in a single atomic call — never delete-then-add, so a crash between
/// the two can never lose a just-rotated refresh token (security.md SEC-06).
/// If no item exists yet, `SecItemUpdate` fails with `errSecItemNotFound` and
/// the code falls back to `SecItemAdd`.
public final class KeychainCredentialStore: CredentialStore, Sendable {
    private let service: String
    private let logger: (any TallyPlatformLogger)?

    /// Richer than `load()`'s bare `Optional`: distinguishes "signed out"
    /// from "can't tell right now, the device is locked" (security.md SEC-06 /
    /// encryption.md ENC-02 — "Only `.notFound` means signed out"). The fixed
    /// `CredentialStore` protocol has no way to carry this distinction through
    /// `load()` itself; call `readStatus()` directly wherever that matters
    /// (flagged for the PMO — see the platform-adapters report).
    public enum ReadStatus: Sendable, Equatable {
        case found(CanvasCredential)
        case notFound
        /// `errSecInteractionNotAllowed`: before first unlock, or the device
        /// is locked. Never treat this as "no credential".
        case unavailable
    }

    public enum StoreError: Error, Sendable, Equatable {
        case unavailable
        case failed(status: OSStatus)
    }

    /// - Parameters:
    ///   - service: defaults to `"<bundle id>.canvas.credential"` (security.md
    ///     §3.2 item 7's exact naming).
    ///   - removeLegacyMockItemOnInit: best-effort cleanup of the baseline
    ///     app's hard-coded mock credential (`service: "com.tally.app"`,
    ///     `account: "canvas"` — security.md SEC-03/SEC-06). Disabled in the
    ///     hosted tests that don't want this side effect.
    ///   - logger: SEC1-01, `.credentialDeleteFailed` only — never the
    ///     credential itself. `nil` in the hosted tests that don't want it.
    public init(
        service: String = (Bundle.main.bundleIdentifier ?? "dev.tally-app.tally") + ".canvas.credential",
        removeLegacyMockItemOnInit: Bool = true,
        logger: (any TallyPlatformLogger)? = nil
    ) {
        self.service = service
        self.logger = logger
        if removeLegacyMockItemOnInit { Self.removeLegacyMockItem() }
    }

    // MARK: - CredentialStore

    public func load() async -> CanvasCredential? {
        switch readStatus() {
        case .found(let credential): return credential
        case .notFound, .unavailable: return nil
        }
    }

    public func save(_ credential: CanvasCredential) async throws {
        let data = try KeychainSupport.credentialEncoder.encode(credential)
        let account = Self.account(for: credential)

        var updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw Self.mapWriteFailure(updateStatus) }

        updateAttributes[kSecClass as String] = kSecClassGenericPassword
        updateAttributes[kSecAttrService as String] = service
        updateAttributes[kSecAttrSynchronizable as String] = false
        updateAttributes[kSecUseDataProtectionKeychain as String] = true
        let addStatus = SecItemAdd(updateAttributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw Self.mapWriteFailure(addStatus) }
    }

    /// `CredentialStore.delete()` has no `throws` in its fixed signature (a
    /// deliberate "sign-out never fails" shape). SEC1-01: an unexpected status
    /// now gets one retry, then a direct read-back, before it is treated as a
    /// real failure (and logged, category-only — never the credential) rather
    /// than silently discarded. `readStatus()` stays available afterwards for
    /// a caller that wants to confirm itself.
    public func delete() async {
        if Self.deleteOutcome(deleteOnce: { SecItemDelete(baseQuery as CFDictionary) }, readStatus: readStatus) == .failed {
            logger?.log(.credentialDeleteFailed)
        }
    }

    enum DeleteOutcome: Equatable { case success, failed }

    /// Pure decision logic (SEC1-01), so a test can abstract the Keychain away with fake
    /// closures instead of exercising real Keychain state: `errSecItemNotFound` already counts
    /// as success (nothing left to delete), one retry absorbs a transient status, and only a
    /// read-back that still disagrees counts as a genuine failure.
    static func deleteOutcome(deleteOnce: () -> OSStatus, readStatus: () -> ReadStatus) -> DeleteOutcome {
        for _ in 0..<2 {
            let status = deleteOnce()
            if status == errSecSuccess || status == errSecItemNotFound { return .success }
        }
        return readStatus() == .notFound ? .success : .failed
    }

    // MARK: - Typed read

    public func readStatus() -> ReadStatus {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return Self.readStatus(forNonSuccess: status) }
        guard let data = result as? Data,
              let credential = try? KeychainSupport.credentialDecoder.decode(CanvasCredential.self, from: data)
        else { return .notFound } // malformed payload: treat like absent, never crash the caller
        return .found(credential)
    }

    /// SEC1-04: only `errSecItemNotFound` means "signed out" (security.md §3.2 item 7 — "Only
    /// `.notFound` means signed out"). Every other non-success status, including one this code
    /// doesn't recognize yet, must never be read as "no credential": map it to `.unavailable`
    /// ("can't tell right now") instead of silently falling through to `.notFound`. Pure, so a
    /// test can drive it with any `OSStatus` without touching the real Keychain.
    static func readStatus(forNonSuccess status: OSStatus) -> ReadStatus {
        status == errSecItemNotFound ? .notFound : .unavailable
    }

    // MARK: - Private

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
    }

    private static func account(for credential: CanvasCredential) -> String {
        "\(credential.host)#\(credential.userID)"
    }

    private static func mapWriteFailure(_ status: OSStatus) -> StoreError {
        status == KeychainSupport.interactionNotAllowed ? .unavailable : .failed(status: status)
    }

    /// Best-effort; a failure here must never block constructing the store.
    private static func removeLegacyMockItem() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.tally.app",
            kSecAttrAccount as String: "canvas",
        ]
        _ = SecItemDelete(query as CFDictionary)
    }
}
