import Foundation
import TallyDomain

/// A student-entered weekly meeting time (D5b: "let students enter class times"), because Canvas
/// rarely publishes recurring meeting schedules. Purely user-authored: never derived from Canvas.
public struct ManualClassTime: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let courseID: CanvasID<Course>
    /// 1 = Sunday … 7 = Saturday (`Foundation.Calendar`'s convention), so no day-name string needs
    /// localisation or storage.
    public let weekday: Int
    public let startMinutesFromMidnight: Int
    public let endMinutesFromMidnight: Int

    public init(id: String = UUID().uuidString, courseID: CanvasID<Course>, weekday: Int,
                startMinutesFromMidnight: Int, endMinutesFromMidnight: Int) {
        self.id = id; self.courseID = courseID; self.weekday = weekday
        self.startMinutesFromMidnight = startMinutesFromMidnight; self.endMinutesFromMidnight = endMinutesFromMidnight
    }
}

/// User-authored settings and content: the store side of `user-state.sealed` (architecture.md
/// §3.2). Cannot be re-fetched from Canvas, unlike every other store file, so `UserStateStore`
/// treats a decode failure as `resetUserStateAndTell` rather than `discardAndRebuild`.
///
/// `showGradesInGlance` is the opt-in switch WP-C03's `GlanceProjectionBuilder` reads
/// (encryption.md D-E3, PMO R10): grade values are never shown by default.
public struct UserState: Codable, Sendable, Equatable {
    /// Schema history: v1 shipped `showGradesInGlance` + `manualClassTimes` only; v2 adds
    /// `hideCourseNamesInNotifications`, defaulted `false` on migration (`UserStateMigration`);
    /// v3 adds `digestThresholds` (owner decision 2026-09-27), defaulted to 0.5 pt everywhere.
    /// Owner decision D-E4 (2026-09-27): user state is NOT backed up; a new install or data wipe
    /// starts from these defaults while Canvas data is fetched fresh.
    public static let currentSchemaVersion = 3

    public let schemaVersion: Int
    public var showGradesInGlance: Bool
    public var hideCourseNamesInNotifications: Bool
    public var manualClassTimes: [ManualClassTime]
    /// "What changed" course-grade threshold: "All" or points, globally or per course.
    public var digestThresholds: DigestThresholds

    public init(showGradesInGlance: Bool = false, hideCourseNamesInNotifications: Bool = false,
                manualClassTimes: [ManualClassTime] = [], digestThresholds: DigestThresholds = .default) {
        schemaVersion = Self.currentSchemaVersion
        self.showGradesInGlance = showGradesInGlance
        self.hideCourseNamesInNotifications = hideCourseNamesInNotifications
        self.manualClassTimes = manualClassTimes
        self.digestThresholds = digestThresholds
    }
}

enum UserStateMigration {
    /// The pre-v2 shape, kept only so a v1 payload already on a device can be upgraded in place.
    private struct V1: Decodable {
        let schemaVersion: Int
        let showGradesInGlance: Bool
        let manualClassTimes: [ManualClassTime]
    }

    /// The v2 shape: everything except `digestThresholds`.
    private struct V2: Decodable {
        let schemaVersion: Int
        let showGradesInGlance: Bool
        let hideCourseNamesInNotifications: Bool
        let manualClassTimes: [ManualClassTime]
    }

    static func decode(_ data: Data) throws -> UserState {
        switch try peekSchemaVersion(data) {
        case UserState.currentSchemaVersion:
            return try JSONDecoder().decode(UserState.self, from: data)
        case 2:
            let v2 = try JSONDecoder().decode(V2.self, from: data)
            return UserState(showGradesInGlance: v2.showGradesInGlance,
                              hideCourseNamesInNotifications: v2.hideCourseNamesInNotifications,
                              manualClassTimes: v2.manualClassTimes)
        case 1:
            let v1 = try JSONDecoder().decode(V1.self, from: data)
            return UserState(showGradesInGlance: v1.showGradesInGlance,
                              hideCourseNamesInNotifications: false,
                              manualClassTimes: v1.manualClassTimes)
        case let other:
            throw SchemaVersionProbeError.unsupportedFutureVersion(other)
        }
    }
}
