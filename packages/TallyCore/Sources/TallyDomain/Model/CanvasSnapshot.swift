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
    #if DEBUG
    /// DEBUG only: ties this value's lifetime to `CanvasSnapshotInstances` (not encoded, never
    /// part of equality). See that type.
    private let instanceToken: CanvasSnapshotInstanceToken
    #endif

    /// Exactly the stored fields above, in declaration order: the encoded form is unchanged by the
    /// DEBUG token, which is not a key.
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, generation, accountKey, host, fetchedAt, profile, courses, groups, gradingPeriods
        case planner, events, announcements, courseColors, sections
    }

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
        #if DEBUG
        instanceToken = CanvasSnapshotInstanceToken(account: accountKey.rawValue)
        #endif
    }

    /// The same field-by-field decoding the synthesized conformance performed (every field is
    /// required), written out only so a DEBUG build can mint the instance token.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        generation = try container.decode(UInt64.self, forKey: .generation)
        accountKey = try container.decode(AccountKey.self, forKey: .accountKey)
        host = try container.decode(String.self, forKey: .host)
        fetchedAt = try container.decode(Date.self, forKey: .fetchedAt)
        profile = try container.decode(UserProfile.self, forKey: .profile)
        courses = try container.decode([Course].self, forKey: .courses)
        groups = try container.decode([CanvasID<Course>: [AssignmentGroup]].self, forKey: .groups)
        gradingPeriods = try container.decode([CanvasID<Course>: [GradingPeriod]].self, forKey: .gradingPeriods)
        planner = try container.decode([PlannerItem].self, forKey: .planner)
        events = try container.decode([CalendarEvent].self, forKey: .events)
        announcements = try container.decode([Announcement].self, forKey: .announcements)
        courseColors = try container.decode([CanvasID<Course>: String].self, forKey: .courseColors)
        sections = try container.decode([SnapshotSection: SectionStatus].self, forKey: .sections)
        #if DEBUG
        instanceToken = CanvasSnapshotInstanceToken(account: accountKey.rawValue)
        #endif
    }
}
