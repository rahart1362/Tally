import Foundation
import TallyCanvasAPI
import os

/// Platform log events. No case carries free-form text or student content:
/// "Privacy enforced by types" (architecture.md §3.1) and implementation
/// brief rule 3 ("Never log student content"). This is E03b's "OSLogLogger"
/// (typed `LogEvent` fields only, marked `.public`; no free-form strings):
/// the shell team already landed this exact pattern
/// (`PlatformLogEvent`/`OSLogPlatformLogger`) in M2's app-shell batch, so
/// the M2 platform-adapters batch extends it with events for the new
/// adapters (transport, credential store, vault key store, notification
/// scheduler) rather than introducing a second, differently-named logger
/// type that would fragment logging. Every associated value is a plain
/// enum, `Int32` or `Bool` — never a `String` carrying anything Canvas- or
/// user-derived — so every field logged below is safe to mark `.public`.
public enum PlatformLogEvent: Sendable {
    case appLaunch
    /// The system invoked the registered `.appRefresh` background task.
    case backgroundRefreshInvoked

    /// `URLSessionTransport` (SEC-08): a request failed before a status
    /// code came back. `TransportError` is a closed, string-free enum.
    case transportFailed(TransportError)

    /// `KeychainCredentialStore` (SEC-04). `found` never carries the
    /// credential itself, only whether one was present.
    case credentialStoreRead(found: Bool)
    /// The device was locked (`errSecInteractionNotAllowed`) — never
    /// confuse this with "signed out" downstream (security.md SEC-06).
    case credentialStoreUnavailable
    case credentialStoreWriteFailed(status: Int32)
    /// The baseline app's hard-coded mock credential was found and removed.
    case legacyCredentialRemoved

    /// `KeychainVaultKeyStore` (ENC-03).
    case vaultKeyStoreUnavailable
    case vaultKeyStoreWriteFailed(status: Int32)

    /// `UNNotificationScheduler` (reminder port adapter).
    case notificationScheduleFailed
    case notificationCategoriesRegistered(count: Int)

    /// `ProtectionState` (`UIApplication.isProtectedDataAvailable` transitions).
    case protectedDataDidBecomeAvailable
    case protectedDataDidBecomeUnavailable
}

public protocol TallyPlatformLogger: Sendable {
    func log(_ event: PlatformLogEvent)
}

/// `os.Logger`-backed adapter. Construction performs no I/O — `Logger.init`
/// only stores the subsystem/category strings — so it is safe to build
/// inside `AppEnvironment.live()` (architecture.md §3.1: "pure construction,
/// no I/O").
public struct OSLogPlatformLogger: TallyPlatformLogger {
    private let logger: Logger

    public init(subsystem: String = Bundle.main.bundleIdentifier ?? "dev.tally-app.tally") {
        logger = Logger(subsystem: subsystem, category: "platform")
    }

    public func log(_ event: PlatformLogEvent) {
        switch event {
        case .appLaunch:
            logger.info("app_launch")
        case .backgroundRefreshInvoked:
            logger.info("background_refresh_invoked")
        case .transportFailed(let error):
            logger.error("transport_failed category=\(Self.category(of: error), privacy: .public)")
        case .credentialStoreRead(let found):
            logger.info("credential_store_read found=\(found, privacy: .public)")
        case .credentialStoreUnavailable:
            logger.notice("credential_store_unavailable")
        case .credentialStoreWriteFailed(let status):
            logger.error("credential_store_write_failed status=\(status, privacy: .public)")
        case .legacyCredentialRemoved:
            logger.notice("legacy_credential_removed")
        case .vaultKeyStoreUnavailable:
            logger.notice("vault_key_store_unavailable")
        case .vaultKeyStoreWriteFailed(let status):
            logger.error("vault_key_store_write_failed status=\(status, privacy: .public)")
        case .notificationScheduleFailed:
            logger.error("notification_schedule_failed")
        case .notificationCategoriesRegistered(let count):
            logger.info("notification_categories_registered count=\(count, privacy: .public)")
        case .protectedDataDidBecomeAvailable:
            logger.info("protected_data_available")
        case .protectedDataDidBecomeUnavailable:
            logger.info("protected_data_unavailable")
        }
    }

    /// Internal (not private) so it is directly verifiable in a hosted test
    /// (`@testable import TallyPlatform`) without needing to inspect actual
    /// `os.Logger` output, which Swift Testing has no first-class API for.
    static func category(of error: TransportError) -> String {
        switch error {
        case .offline: return "offline"
        case .timedOut: return "timedOut"
        case .cancelled: return "cancelled"
        case .other: return "other"
        }
    }
}
