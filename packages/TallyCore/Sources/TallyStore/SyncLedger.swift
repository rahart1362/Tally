import Foundation

/// One reconciled calendar event: the stable Tally key maps to Foundation's `eventIdentifier`
/// (opaque, EventKit-assigned) plus a content hash, so the reconciler can tell "unchanged" from
/// "needs an update" without re-deriving the whole event (architecture.md §3.4).
public struct CalendarLedgerEntry: Codable, Sendable, Equatable {
    public let eventIdentifier: String
    public let contentHash: String
    public init(eventIdentifier: String, contentHash: String) {
        self.eventIdentifier = eventIdentifier; self.contentHash = contentHash
    }
}

/// The side-effect ledger (`sync-ledger.sealed`): what Tally has already told the outside world,
/// so notifications and calendar events can be reconciled idempotently (architecture.md §3.2/§3.4).
/// Entirely rederivable from the snapshot plus the current OS state, so a decode failure is
/// `discardAndRebuild`, not `resetUserStateAndTell`.
public struct SyncLedger: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    /// Deterministic notification ID -> a hash of its content, so "desired vs already scheduled"
    /// is a set diff (`NotificationReconciler`, out of this worktree's scope).
    public var notifications: [String: String]
    /// Stable `tally://<accountKey>/<type>/<canvasID>` key -> its EventKit identifier and hash.
    public var calendarEvents: [String: CalendarLedgerEntry]

    public init(notifications: [String: String] = [:], calendarEvents: [String: CalendarLedgerEntry] = [:]) {
        schemaVersion = Self.currentSchemaVersion
        self.notifications = notifications
        self.calendarEvents = calendarEvents
    }
}

enum SyncLedgerMigration {
    static func decode(_ data: Data) throws -> SyncLedger {
        switch try peekSchemaVersion(data) {
        case SyncLedger.currentSchemaVersion:
            return try JSONDecoder().decode(SyncLedger.self, from: data)
        case let other:
            throw SchemaVersionProbeError.unsupportedFutureVersion(other)
        }
    }
}
