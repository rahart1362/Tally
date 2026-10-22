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
    /// v3 adds `digestThresholds` (owner decision 2026-09-27), defaulted to 0.5 pt everywhere;
    /// v4 adds the screens' local state, `courseOrder` and `doneAssignments` (M3-A O3), and
    /// `reminderTipDismissedUntil` (M3-C O1), empty or nil on migration; v5 adds
    /// `gradesOutsideCanvasOverride` (plan 08 G-3, XG-04), empty (every course Automatic) on migration;
    /// v6 (FEAT-3) adds `quietHoursOverride` (idea 5: a per-student Quiet Hours window, nil on
    /// migration — "defaults stay as today when unset") and `adHocReminders` (idea 4: the To-Do
    /// "Remind me" action's pending ad-hoc requests, empty on migration).
    /// Owner decision D-E4 (2026-09-27): user state is NOT backed up; a new install or data wipe
    /// starts from these defaults while Canvas data is fetched fresh.
    public static let currentSchemaVersion = 6

    public let schemaVersion: Int
    public var showGradesInGlance: Bool
    public var hideCourseNamesInNotifications: Bool
    public var manualClassTimes: [ManualClassTime]
    /// "What changed" course-grade threshold: "All" or points, globally or per course.
    public var digestThresholds: DigestThresholds
    /// The student's course order (Courses → Edit, UX-WP-14). Opaque IDs only; empty means
    /// Canvas's order.
    public var courseOrder: [CanvasID<Course>]
    /// To-Do items marked done in Tally (UX-WP-18; PMO R16: local only, never written to Canvas).
    public var doneAssignments: Set<CanvasID<Assignment>>
    /// The Dashboard's reminders tip stays hidden until this time (UX-WP-12); nil shows it.
    public var reminderTipDismissedUntil: Date?
    /// The student's answer to "This course's grades are kept outside Canvas" per course (plan 08
    /// G-3, XG-04): `GradeAvailabilityOverride`'s raw values, which are a persisted contract
    /// (`"keptOutsideCanvas"` is Yes, `"inCanvas"` is No). Automatic is absent. Stored by raw value
    /// rather than as the enum so that a value this build does not know reads as Automatic instead
    /// of failing the whole decode, which would reset every other setting
    /// (`UserStateStore`'s `resetUserStateAndTell`). Read and write it through
    /// `gradeAvailabilityOverrides`.
    public var gradesOutsideCanvasOverride: [CanvasID<Course>: String]
    /// Idea 5 (FEAT-3): the student's own Quiet Hours window, overriding `QuietHours()`'s
    /// hardcoded 23:00-07:00 default; `nil` (absent) means "defaults stay as today" — the
    /// `ReminderPlanner`/`shiftOutOfQuietHours` default, unchanged.
    public var quietHoursOverride: QuietHours?
    /// Idea 4 (FEAT-3): the To-Do "Remind me" action's pending ad-hoc reminders — one requested
    /// fire date per assignment. `ReminderPlanner.plan` drops an entry once its assignment is
    /// marked done, submitted or graded (no explicit removal needed here); the UI still clears
    /// an entry itself once "Done" is tapped, so the map does not grow without bound.
    public var adHocReminders: [CanvasID<Assignment>: Date]

    public init(showGradesInGlance: Bool = false, hideCourseNamesInNotifications: Bool = false,
                manualClassTimes: [ManualClassTime] = [], digestThresholds: DigestThresholds = .default,
                courseOrder: [CanvasID<Course>] = [], doneAssignments: Set<CanvasID<Assignment>> = [],
                reminderTipDismissedUntil: Date? = nil,
                gradeAvailabilityOverrides: [CanvasID<Course>: GradeAvailabilityOverride] = [:],
                quietHoursOverride: QuietHours? = nil, adHocReminders: [CanvasID<Assignment>: Date] = [:]) {
        schemaVersion = Self.currentSchemaVersion
        self.showGradesInGlance = showGradesInGlance
        self.hideCourseNamesInNotifications = hideCourseNamesInNotifications
        self.manualClassTimes = manualClassTimes
        self.digestThresholds = digestThresholds
        self.courseOrder = courseOrder
        self.doneAssignments = doneAssignments
        self.reminderTipDismissedUntil = reminderTipDismissedUntil
        gradesOutsideCanvasOverride = gradeAvailabilityOverrides.mapValues(\.rawValue)
        self.quietHoursOverride = quietHoursOverride
        self.adHocReminders = adHocReminders
    }

    /// `gradesOutsideCanvasOverride` as the classifier takes it (`GradeAvailabilityIndex`'s
    /// `overrides`). A raw value this build does not know is left out, so that course is
    /// Automatic; setting the map writes only known values.
    public var gradeAvailabilityOverrides: [CanvasID<Course>: GradeAvailabilityOverride] {
        get { gradesOutsideCanvasOverride.compactMapValues(GradeAvailabilityOverride.init(rawValue:)) }
        set { gradesOutsideCanvasOverride = newValue.mapValues(\.rawValue) }
    }
}

enum UserStateMigration {
    /// The pre-v2 shape, kept only so a v1 payload already on a device can be upgraded in place.
    private struct V1: Decodable {
        let schemaVersion: Int
        let showGradesInGlance: Bool
        let manualClassTimes: [ManualClassTime]
    }

    /// The v5 shape: everything before the Quiet Hours override and the ad-hoc reminders (FEAT-3).
    private struct V5: Decodable {
        let schemaVersion: Int
        let showGradesInGlance: Bool
        let hideCourseNamesInNotifications: Bool
        let manualClassTimes: [ManualClassTime]
        let digestThresholds: DigestThresholds
        let courseOrder: [CanvasID<Course>]
        let doneAssignments: Set<CanvasID<Assignment>>
        let reminderTipDismissedUntil: Date?
        let gradesOutsideCanvasOverride: [CanvasID<Course>: String]
    }

    /// The v4 shape: everything before the grades-outside-Canvas overrides (XG-04).
    private struct V4: Decodable {
        let schemaVersion: Int
        let showGradesInGlance: Bool
        let hideCourseNamesInNotifications: Bool
        let manualClassTimes: [ManualClassTime]
        let digestThresholds: DigestThresholds
        let courseOrder: [CanvasID<Course>]
        let doneAssignments: Set<CanvasID<Assignment>>
        let reminderTipDismissedUntil: Date?
    }

    /// The v3 shape: everything before the screens' local state.
    private struct V3: Decodable {
        let schemaVersion: Int
        let showGradesInGlance: Bool
        let hideCourseNamesInNotifications: Bool
        let manualClassTimes: [ManualClassTime]
        let digestThresholds: DigestThresholds
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
        case 5:
            // Every v5 field kept; no Quiet Hours override yet ("defaults stay as today when
            // unset") and no ad-hoc reminders pending yet.
            let v5 = try JSONDecoder().decode(V5.self, from: data)
            var state = UserState(showGradesInGlance: v5.showGradesInGlance,
                                  hideCourseNamesInNotifications: v5.hideCourseNamesInNotifications,
                                  manualClassTimes: v5.manualClassTimes, digestThresholds: v5.digestThresholds,
                                  courseOrder: v5.courseOrder, doneAssignments: v5.doneAssignments,
                                  reminderTipDismissedUntil: v5.reminderTipDismissedUntil)
            state.gradesOutsideCanvasOverride = v5.gradesOutsideCanvasOverride
            return state
        case 4:
            // Every v4 field kept; every course starts Automatic (plan 08 XG-04).
            let v4 = try JSONDecoder().decode(V4.self, from: data)
            return UserState(showGradesInGlance: v4.showGradesInGlance,
                              hideCourseNamesInNotifications: v4.hideCourseNamesInNotifications,
                              manualClassTimes: v4.manualClassTimes, digestThresholds: v4.digestThresholds,
                              courseOrder: v4.courseOrder, doneAssignments: v4.doneAssignments,
                              reminderTipDismissedUntil: v4.reminderTipDismissedUntil)
        case 3:
            let v3 = try JSONDecoder().decode(V3.self, from: data)
            return UserState(showGradesInGlance: v3.showGradesInGlance,
                              hideCourseNamesInNotifications: v3.hideCourseNamesInNotifications,
                              manualClassTimes: v3.manualClassTimes, digestThresholds: v3.digestThresholds)
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
