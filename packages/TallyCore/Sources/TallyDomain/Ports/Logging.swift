import Foundation

/// The privacy-safe logging port `TallyDomainModule`'s doc comment names (architecture.md §3.1:
/// "LogEvent + TallyLogger protocol" in `TallyDomain`, an OSLog adapter in the platform layer).
///
/// Privacy is enforced by the types: every `LogEvent` case carries only closed enums and counts,
/// never a `String`, so no name, title, grade or Canvas ID can be logged by accident. The app's
/// platform layer bridges this to its `os.Logger` adapter.
///
/// CS-07 (crash-safety-2.md) introduced this port with the one event it needed. Add a case for
/// each new event rather than a free-form overload.
public protocol TallyLogger: Sendable {
    func log(_ event: LogEvent)
}

/// A snapshot collection that `LiveCanvasGateway` de-duplicates by ID.
public enum SnapshotCollection: String, Sendable, Equatable, Hashable, CaseIterable {
    case courses, assignmentGroups, assignments, gradingPeriods, plannerItems, events, announcements
}

public enum LogEvent: Sendable, Equatable, Hashable {
    /// The gateway kept the first occurrence of each ID in `collection` and dropped `count`
    /// repeats (CS-07). A count only: never which IDs, names or titles repeated.
    case duplicateIDsDropped(SnapshotCollection, count: Int)
}

/// The default logger: discards every event.
public struct NoOpLogger: TallyLogger {
    public init() {}
    public func log(_ event: LogEvent) {}
}
