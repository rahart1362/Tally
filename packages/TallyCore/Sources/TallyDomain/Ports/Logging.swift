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

/// Item 2 (LIVE-FIX-2, live2-security's "enrollment_or_course" finding): why one course's
/// per-course fetch was skipped rather than failing the whole refresh. A reason only, never
/// which course.
public enum CourseFetchSkipReason: String, Error, Sendable, Equatable, Hashable {
    /// 403: a concluded enrollment still exists but no longer grants access (`CanvasClient.swift`
    /// doc: "a concluded enrollment keeps read access to the course's own historical data" does
    /// NOT extend to a `deleted` enrollment -- Canvas returns 403 for that one).
    case forbidden
    /// 404: the course itself was deleted (`courses_controller.rb#destroy`).
    case notFound
}

public enum LogEvent: Sendable, Equatable, Hashable {
    /// The gateway kept the first occurrence of each ID in `collection` and dropped `count`
    /// repeats (CS-07). A count only: never which IDs, names or titles repeated.
    case duplicateIDsDropped(SnapshotCollection, count: Int)
    /// SEC1-02: sign-out's revoke call, after refreshing first if the access token had already
    /// expired, reached Canvas or not. Never blocks sign-out either way.
    case signOutRevoked(ok: Bool)
    /// Item 2 (LIVE-FIX-2): one course's assignment-groups fetch came back forbidden or not
    /// found (a deleted or forbidden course) and was skipped so the rest of the refresh could
    /// still complete. A reason only, never the course's ID, name or any other content.
    case courseSkipped(CourseFetchSkipReason)
}

/// The default logger: discards every event.
public struct NoOpLogger: TallyLogger {
    public init() {}
    public func log(_ event: LogEvent) {}
}
