import Foundation
import TallyCanvasAPI
import TallyDomain
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
    /// A reminder was not scheduled because notifications are denied or not yet determined
    /// (plan 06 A4: iOS 27 rejects `add` from an unauthorised app).
    case notificationsNotAuthorized

    /// `ProtectionState` (`UIApplication.isProtectedDataAvailable` transitions).
    case protectedDataDidBecomeAvailable
    case protectedDataDidBecomeUnavailable

    /// TallyCore's logging port (CS-07 D1, plan 06 A8): `LiveCanvasGateway` kept the first of each
    /// repeated ID in `collection` and dropped `count` repeats. A closed enum and a count only.
    case duplicateIDsDropped(collection: SnapshotCollection, count: Int)
}

extension PlatformLogEvent {
    /// The platform event for each of TallyCore's `LogEvent`s (plan 06 A8). Exhaustive: a new
    /// `LogEvent` case fails to compile here until it has a platform event.
    public init(_ event: LogEvent) {
        switch event {
        case .duplicateIDsDropped(let collection, let count):
            self = .duplicateIDsDropped(collection: collection, count: count)
        }
    }
}

public protocol TallyPlatformLogger: Sendable {
    func log(_ event: PlatformLogEvent)
}

/// `os.Logger`-backed adapter. Construction performs no I/O — `Logger.init`
/// only stores the subsystem/category strings — so it is safe to build
/// inside `AppEnvironment.live()` (architecture.md §3.1: "pure construction,
/// no I/O").
/// Also TallyCore's `TallyLogger` (plan 06 A8): the one `os.Logger` adapter the composition root
/// passes to the Canvas gateways, so CS-07's duplicate-ID counts reach the unified log.
public struct OSLogPlatformLogger: TallyPlatformLogger, TallyLogger {
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
        case .notificationsNotAuthorized:
            logger.notice("notifications_not_authorized")
        case .protectedDataDidBecomeAvailable:
            logger.info("protected_data_available")
        case .protectedDataDidBecomeUnavailable:
            logger.info("protected_data_unavailable")
        case .duplicateIDsDropped(let collection, let count):
            logger.notice("duplicate_ids_dropped collection=\(collection.rawValue, privacy: .public) count=\(count, privacy: .public)")
        }
    }

    /// `TallyLogger`: TallyCore's events, through the same adapter.
    public func log(_ event: LogEvent) {
        log(PlatformLogEvent(event))
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
