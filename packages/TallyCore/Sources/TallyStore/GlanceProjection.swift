import Foundation
import TallyDomain

// `GradeBand` moved to `TallyDomain/Grades/GradeBand.swift` (PERF-02): `DashboardProjection`'s
// output types need it and live below `TallyStore` in the dependency graph. Nothing here
// changes behaviourally; `GradeBand` is used exactly as before via the `import TallyDomain`
// already above.

/// One course line in the glance. Never the course name, term or teacher — only the short code,
/// which by convention (e.g. "BIO 101") does not identify the student.
public struct GlanceCourse: Codable, Sendable, Equatable, Identifiable {
    public let id: CanvasID<Course>
    public let shortCode: String
    /// nil unless the user opted into showing grades in the glance/widget (D-E3, R10).
    public let currentGrade: GradeBand?

    public init(id: CanvasID<Course>, shortCode: String, currentGrade: GradeBand?) {
        self.id = id; self.shortCode = shortCode; self.currentGrade = currentGrade
    }
}

/// One planner item, reduced to what a glance may show: an opaque ID, a course code, a title
/// truncated to `TallyConfig.glanceTitleMaxLength`, a due date and status flags. Never the
/// assignment's HTML URL, submission body, or any instructor-authored text beyond the title.
public struct GlanceDueItem: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let courseShortCode: String?
    public let title: String
    public let dueAt: Date?
    public let missing: Bool
    public let late: Bool
    public let excused: Bool
    public let submitted: Bool

    public init(id: String, courseShortCode: String?, title: String, dueAt: Date?,
                missing: Bool, late: Bool, excused: Bool, submitted: Bool) {
        self.id = id; self.courseShortCode = courseShortCode; self.title = title; self.dueAt = dueAt
        self.missing = missing; self.late = late; self.excused = excused; self.submitted = submitted
    }
}

/// The small first-paint / widget projection (architecture.md §3.2, §3.4; encryption.md §3.3).
/// Built only from the snapshot already on disk — never a fresh Canvas call — so it can be
/// rebuilt at any time, including by `SnapshotStore`'s self-heal path.
///
/// Content allowlist (encryption.md §3.3, D-E3): `generation`, `asOf`, an optional overall grade
/// band, per-course short code plus an optional grade band, and at most
/// `TallyConfig.glanceDueItemLimit` due items. Grade fields are nil unless the caller opts in.
/// Never included: instructor names or emails, comments, announcements, submission content, the
/// user's name, the institution host, or tokens. `VaultBlobTests`/`GlanceProjectionTests` assert
/// the exact Codable key set so a future field can't be added to this type by accident.
public struct GlanceProjection: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let generation: UInt64
    public let asOf: Date
    public let overallGradeBand: GradeBand?
    public let courses: [GlanceCourse]
    public let dueSoon: [GlanceDueItem]

    public init(generation: UInt64, asOf: Date, overallGradeBand: GradeBand?, courses: [GlanceCourse], dueSoon: [GlanceDueItem]) {
        schemaVersion = Self.currentSchemaVersion
        self.generation = generation; self.asOf = asOf; self.overallGradeBand = overallGradeBand
        self.courses = courses; self.dueSoon = dueSoon
    }
}

public enum GlanceProjectionBuilder {
    /// `includeGrades` is the caller's resolved opt-in flag (from `UserState.showGradesInGlance`);
    /// this builder never defaults it to true.
    public static func build(from snapshot: CanvasSnapshot, includeGrades: Bool) -> GlanceProjection {
        let courseByID = Dictionary(uniqueKeysWithValues: snapshot.courses.map { ($0.id, $0) })
        let courses = snapshot.courses.map { course in
            GlanceCourse(id: course.id, shortCode: course.courseCode, currentGrade: gradeBand(for: course, includeGrades: includeGrades))
        }
        let overall = includeGrades ? overallBand(of: snapshot.courses) : nil
        return GlanceProjection(generation: snapshot.generation, asOf: snapshot.fetchedAt,
                                overallGradeBand: overall, courses: courses,
                                dueSoon: dueSoon(from: snapshot.planner, courseByID: courseByID))
    }

    private static func gradeBand(for course: Course, includeGrades: Bool) -> GradeBand? {
        // hiddenTotals: the teacher withheld the total. Tally never shows a band it wasn't given,
        // even if the user opted in (Course.swift: "Tally never shows '0%' for a hidden grade").
        guard includeGrades, course.gradeVisibility != .hiddenTotals, let scores = course.scores else { return nil }
        if let percent = scores.currentScore { return .fromPercent(percent) }
        if let letter = scores.currentGrade { return .from(letterOrPassFail: letter) }
        return nil
    }

    private static func overallBand(of courses: [Course]) -> GradeBand? {
        let visiblePercents = courses.compactMap { course -> Double? in
            guard course.gradeVisibility != .hiddenTotals else { return nil }
            return course.scores?.currentScore
        }
        guard !visiblePercents.isEmpty else { return nil }
        return .fromPercent(visiblePercents.reduce(0, +) / Double(visiblePercents.count))
    }

    private static func dueSoon(from planner: [PlannerItem], courseByID: [CanvasID<Course>: Course]) -> [GlanceDueItem] {
        planner
            .filter { !($0.markedComplete && $0.submitted) }
            .sorted(by: dueBefore)
            .prefix(TallyConfig.glanceDueItemLimit)
            .map { item in
                GlanceDueItem(
                    id: item.id,
                    courseShortCode: item.courseID.flatMap { courseByID[$0]?.courseCode },
                    title: String(item.title.prefix(TallyConfig.glanceTitleMaxLength)),
                    dueAt: item.dueAt, missing: item.missing, late: item.late,
                    excused: item.excused, submitted: item.submitted)
            }
    }

    /// Items with a due date sort first (earliest first); undated items sort after all dated ones.
    private static func dueBefore(_ lhs: PlannerItem, _ rhs: PlannerItem) -> Bool {
        switch (lhs.dueAt, rhs.dueAt) {
        case let (l?, r?): return l < r
        case (nil, nil): return false
        case (nil, _?): return false
        case (_?, nil): return true
        }
    }
}
