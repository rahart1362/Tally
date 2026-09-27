import Foundation

/// Opaque per-account key (hex SHA-256 of `host|userID`, derived in TallyStore);
/// used in file paths and notification IDs so no names appear there.
public struct AccountKey: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
}

/// Per-section fetch status: optional sections may be carried forward from the
/// previous snapshot when their refresh fails (architecture §3.2).
public struct SectionStatus: Codable, Sendable, Equatable {
    public let fetchedAt: Date
    public let carriedForward: Bool
    public init(fetchedAt: Date, carriedForward: Bool) { self.fetchedAt = fetchedAt; self.carriedForward = carriedForward }
}

public enum SnapshotSection: String, Codable, CodingKeyRepresentable, Sendable, CaseIterable {
    case profile, courses, assignmentGroups, planner          // required: all-or-nothing
    case gradingPeriods, events, announcements, colors         // optional: may carry forward
    public var isRequired: Bool { [.profile, .courses, .assignmentGroups, .planner].contains(self) }
}

/// Everything Tally knows about one account after one successful refresh.
/// The whole value is sealed and atomically replaces the previous one.
public struct CanvasSnapshot: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let generation: UInt64
    public let accountKey: AccountKey
    public let host: String
    public let fetchedAt: Date
    public let profile: UserProfile
    public let courses: [Course]
    public let groups: [CanvasID<Course>: [AssignmentGroup]]
    public let gradingPeriods: [CanvasID<Course>: [GradingPeriod]]
    public let planner: [PlannerItem]
    public let events: [CalendarEvent]
    public let announcements: [Announcement]
    public let courseColors: [CanvasID<Course>: String]
    public let sections: [SnapshotSection: SectionStatus]

    public init(generation: UInt64, accountKey: AccountKey, host: String, fetchedAt: Date, profile: UserProfile,
                courses: [Course], groups: [CanvasID<Course>: [AssignmentGroup]],
                gradingPeriods: [CanvasID<Course>: [GradingPeriod]], planner: [PlannerItem],
                events: [CalendarEvent], announcements: [Announcement],
                courseColors: [CanvasID<Course>: String], sections: [SnapshotSection: SectionStatus]) {
        schemaVersion = Self.currentSchemaVersion
        self.generation = generation; self.accountKey = accountKey; self.host = host; self.fetchedAt = fetchedAt
        self.profile = profile; self.courses = courses; self.groups = groups; self.gradingPeriods = gradingPeriods
        self.planner = planner; self.events = events; self.announcements = announcements
        self.courseColors = courseColors; self.sections = sections
    }
}
