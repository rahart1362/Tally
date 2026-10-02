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
    /// nil unless the user opted into showing grades in the glance/widget (D-E3, R10), and nil for
    /// a course whose grades Tally does not show as a band (plan 08 §4.4 row 15).
    public let currentGrade: GradeBand?
    /// Plan 08 §4.4 row 15 (schema 2): whether the course's grades are in Canvas and in the
    /// average, or why not (`CourseGradeStatus`). A state, never a grade value, so it is present
    /// whether or not the user opted into grades: the launch paint needs it to say what the full
    /// projection says. `nil` only in a glance written before schema 2.
    public let gradeStatus: CourseGradeStatus?

    public init(id: CanvasID<Course>, shortCode: String, currentGrade: GradeBand?, gradeStatus: CourseGradeStatus? = nil) {
        self.id = id; self.shortCode = shortCode; self.currentGrade = currentGrade; self.gradeStatus = gradeStatus
    }
}

/// Plan 08 §4.4 row 14 (schema 2): what the glance says about the overall grade, for the Standing
/// widget. `.notOptedIn` whenever the user has not chosen to show grades in widgets, whatever the
/// grades are; the other three only when they have.
public enum GlanceGradeSummary: Codable, Sendable, Equatable {
    /// The user has not chosen to show grades in widgets (PMO R10).
    case notOptedIn
    /// The band of the average over the averaged courses (the dashboard hero's rule).
    case band(GradeBand)
    /// No course can be averaged yet, and the school is not "none in Canvas".
    case noneYet
    /// No course can be averaged, and the school does not appear to keep grades in Canvas
    /// (`SchoolGradeSummary.noneInCanvas`).
    case notInCanvas

    /// Encoded as `{"state": "band", "band": "a"}`: the state names are a persisted contract.
    private enum CodingKeys: String, CodingKey { case state, band }
    private enum State: String, Codable { case notOptedIn, band, noneYet, notInCanvas }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(State.self, forKey: .state) {
        case .notOptedIn: self = .notOptedIn
        case .band: self = .band(try container.decode(GradeBand.self, forKey: .band))
        case .noneYet: self = .noneYet
        case .notInCanvas: self = .notInCanvas
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .notOptedIn: try container.encode(State.notOptedIn, forKey: .state)
        case .band(let band):
            try container.encode(State.band, forKey: .state)
            try container.encode(band, forKey: .band)
        case .noneYet: try container.encode(State.noneYet, forKey: .state)
        case .notInCanvas: try container.encode(State.notInCanvas, forKey: .state)
        }
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
/// Content allowlist (encryption.md §3.3, D-E3): `generation`, `asOf`, the grade summary (a band
/// only when the user opted in), per-course short code plus an optional grade band and its grade
/// status, and at most `TallyConfig.glanceDueItemLimit` due items. Grade values are absent unless
/// the caller opts in. Never included: instructor names or emails, comments, announcements,
/// submission content, the user's name, the institution host, or tokens.
/// `VaultBlobTests`/`GlanceProjectionTests` assert the exact Codable key set so a future field
/// can't be added to this type by accident.
///
/// Schema 2 (plan 08 §4.4 rows 14-15, XG-02): `gradeSummary` replaces `overallGradeBand`, and
/// each course gains `gradeStatus`. A schema-1 file still decodes (`init(from:)`): its band
/// becomes the summary, and its courses have no status. The store rebuilds it at the next load of
/// the snapshot (`SnapshotStore`), and the next commit rewrites it anyway.
///
/// `entitledUntil` (PAY-04, M3-B1) is additive within schema 2: optional, absent from a glance
/// written before it, which reads as "no verified entitlement".
public struct GlanceProjection: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let generation: UInt64
    public let asOf: Date
    /// What the Standing widget says (`.notOptedIn` unless the user opted into grades).
    public let gradeSummary: GlanceGradeSummary
    public let courses: [GlanceCourse]
    public let dueSoon: [GlanceDueItem]
    /// PAY-04 (M3-B1): the expiry of this account's last verified trial or subscription
    /// (`EntitlementPolicy`'s `.entitled(until:)`, the Keychain record's), mirrored here so the
    /// widgets and the intents decide without StoreKit: `coversSubscription(at:)`. An expiry date
    /// only, never a receipt, a transaction ID or a price (encryption.md §3.3). `nil`: no verified
    /// entitlement (never subscribed, lapsed, refunded), or a glance written before this field.
    public let entitledUntil: Date?

    /// PAY-04, PAY-07: whether the subscription covers the widgets' and intents' content at
    /// `moment` (`EntitlementAccess.covers`, with the glance's `asOf` as a time this device has
    /// reached). Fails closed `SubscriptionConfig.offlineGracePeriod` after `entitledUntil`;
    /// always true while gating is not enforced.
    public func coversSubscription(at moment: Date, isEnforced: Bool = SubscriptionConfig.isGatingEnforced) -> Bool {
        EntitlementAccess.covers(entitledUntil: entitledUntil, at: moment, notBefore: asOf, isEnforced: isEnforced)
    }

    /// The overall band, when the summary has one.
    public var overallGradeBand: GradeBand? {
        if case .band(let band) = gradeSummary { return band }
        return nil
    }

    /// Plan 08 §4.4 row 2 (XG-02): the dashboard hero the launch paint shows before the snapshot is
    /// decoded (`HomeGlance`), from the per-course statuses `DashboardBuilder.hero`'s rule wrote:
    /// the same course count, averaged count, exclusions and school summary as the full projection.
    /// The percentage is nil (the glance carries none, D-P1); the band is present only when the
    /// student opted in. A course is counted once (CS-07). A glance written before schema 2 has no
    /// statuses: its hero counts every course, as that version's launch paint did, until the store
    /// rebuilds it.
    public var hero: DashboardProjection.Hero {
        var seen = Set<CanvasID<Course>>()
        let distinct = courses.filter { seen.insert($0.id).inserted }
        let statuses = distinct.compactMap(\.gradeStatus)
        guard statuses.count == distinct.count else {
            return DashboardProjection.Hero(courseCount: distinct.count, averagedCount: distinct.count, overallPercent: nil,
                                            overallBand: overallGradeBand, exclusions: [:], school: .undetermined)
        }
        var exclusions: [CourseGradeStatus: Int] = [:]
        for status in statuses where status != .averaged { exclusions[status, default: 0] += 1 }
        return DashboardProjection.Hero(courseCount: distinct.count, averagedCount: statuses.count - exclusions.values.reduce(0, +),
                                        overallPercent: nil, overallBand: overallGradeBand, exclusions: exclusions,
                                        school: SchoolGradeSummary(statuses: statuses))
    }

    public init(generation: UInt64, asOf: Date, gradeSummary: GlanceGradeSummary, courses: [GlanceCourse],
                dueSoon: [GlanceDueItem], entitledUntil: Date? = nil) {
        schemaVersion = Self.currentSchemaVersion
        self.generation = generation; self.asOf = asOf; self.gradeSummary = gradeSummary
        self.courses = courses; self.dueSoon = dueSoon; self.entitledUntil = entitledUntil
    }

    /// Schema 1's shape, for tests and tools: a band, or no grades shown.
    public init(generation: UInt64, asOf: Date, overallGradeBand: GradeBand?, courses: [GlanceCourse],
                dueSoon: [GlanceDueItem]) {
        self.init(generation: generation, asOf: asOf, gradeSummary: overallGradeBand.map(GlanceGradeSummary.band) ?? .notOptedIn,
                  courses: courses, dueSoon: dueSoon)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, generation, asOf, gradeSummary, courses, dueSoon, entitledUntil
    }

    /// Schema 1's grade field.
    private enum SchemaOneKeys: String, CodingKey { case overallGradeBand }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        generation = try container.decode(UInt64.self, forKey: .generation)
        asOf = try container.decode(Date.self, forKey: .asOf)
        courses = try container.decode([GlanceCourse].self, forKey: .courses)
        dueSoon = try container.decode([GlanceDueItem].self, forKey: .dueSoon)
        entitledUntil = try container.decodeIfPresent(Date.self, forKey: .entitledUntil)
        if schemaVersion >= 2 {
            gradeSummary = try container.decode(GlanceGradeSummary.self, forKey: .gradeSummary)
        } else {
            // Schema 1 wrote an overall band, or a band per course, only when the user had opted
            // in (the same reading `SnapshotStore`'s self-heal used): no band anywhere is "not
            // opted in"; a course band without an overall one is "no average yet".
            let legacy = try decoder.container(keyedBy: SchemaOneKeys.self)
            if let band = try legacy.decodeIfPresent(GradeBand.self, forKey: .overallGradeBand) {
                gradeSummary = .band(band)
            } else {
                gradeSummary = courses.contains { $0.currentGrade != nil } ? .noneYet : .notOptedIn
            }
        }
    }
}

public enum GlanceProjectionBuilder {
    /// `includeGrades` is the caller's resolved opt-in flag (from `UserState.showGradesInGlance`);
    /// this builder never defaults it to true.
    ///
    /// `gradeAvailability` is the snapshot's `GradeAvailabilityIndex` (plan 08 §4.3: at commit the
    /// coordinator builds it once, with the student's overrides, at the snapshot's `fetchedAt`).
    /// `nil` builds it the same way with no override (the store's self-heal, tests).
    ///
    /// `entitledUntil` (PAY-04) is the expiry the entitlement gate mirrors (the coordinator's
    /// `EntitlementGating.glanceEntitledUntil()`); the store's self-heal carries the old glance's
    /// forward. Never derived from the snapshot.
    public static func build(from snapshot: CanvasSnapshot, includeGrades: Bool,
                             gradeAvailability: GradeAvailabilityIndex? = nil,
                             entitledUntil: Date? = nil) -> GlanceProjection {
        let availability = gradeAvailability
            ?? GradeAvailabilityIndex(snapshot: snapshot, overrides: [:], now: snapshot.fetchedAt)
        // CS-07: `courses` can repeat an ID (a course listed once per enrollment, or pages that
        // overlap). `Dictionary(uniqueKeysWithValues:)` trapped on that, at every commit and on
        // every self-heal load. The first occurrence wins, as in `PriorityScore.WeightContext`.
        let courseByID = Dictionary(snapshot.courses.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let courses = snapshot.courses.map { listed in
            // A repeated ID describes the course by its first occurrence, as the index does.
            let course = courseByID[listed.id] ?? listed
            let status = CourseGradeStatus(course: course, availability: availability[course.id])
            return GlanceCourse(id: course.id, shortCode: listed.courseCode,
                                currentGrade: includeGrades ? gradeBand(for: course, status: status) : nil,
                                gradeStatus: status)
        }
        return GlanceProjection(generation: snapshot.generation, asOf: snapshot.fetchedAt,
                                gradeSummary: gradeSummary(of: snapshot.courses, availability: availability,
                                                           includeGrades: includeGrades),
                                courses: courses,
                                dueSoon: dueSoon(from: snapshot.planner, asOf: snapshot.fetchedAt, courseByID: courseByID),
                                entitledUntil: entitledUntil)
    }

    /// Plan 08 §4.4 row 15: a band only for a course whose grades are in Canvas and not hidden by
    /// the instructor (Tally never shows a band it wasn't given, even if the user opted in:
    /// Course.swift, "Tally never shows '0%' for a hidden grade"), and never for a course whose
    /// grades are not in Canvas.
    private static func gradeBand(for course: Course, status: CourseGradeStatus) -> GradeBand? {
        switch status {
        case .averaged, .noPercentage, .lettersOnly:
            guard let scores = course.scores else { return nil }
            if let percent = scores.currentScore { return .fromPercent(percent) }
            if let letter = scores.currentGrade { return .from(letterOrPassFail: letter) }
            return nil
        case .hiddenByInstructor, .notYetPosted, .notGradedInCanvas, .keptOutsideCanvas:
            return nil
        }
    }

    /// Plan 08 §4.4 rows 14-15: the dashboard hero's rule (`DashboardBuilder.hero`), so the
    /// widget's band is the band of the hero's average and both leave out the same courses.
    private static func gradeSummary(of courses: [Course], availability: GradeAvailabilityIndex,
                                     includeGrades: Bool) -> GlanceGradeSummary {
        guard includeGrades else { return .notOptedIn }
        let hero = DashboardBuilder.hero(courses: courses, gradeAvailability: availability)
        if let band = hero.overallBand { return .band(band) }
        return hero.school == .noneInCanvas ? .notInCanvas : .noneYet
    }

    /// The glance's due items, chosen for what its two readers show: the launch paint's "Due soon"
    /// (`HomeGlance`, the dashboard's rule: items due from now on) and the widget's "Next up" (open
    /// items, and how many are overdue). Past items that were submitted or excused, and undated
    /// items, serve neither, so they no longer take slots: before, six past submitted items could
    /// fill the slots and leave the glance with no upcoming item (m2-widget-compliance-report OI3).
    /// Upcoming items come first; up to `glanceOverdueItemReserve` slots stay for open overdue
    /// items (the most recent ones); slots one group leaves unused go to the other, then to undated
    /// items. The result is earliest first, undated last, as before.
    private static func dueSoon(from planner: [PlannerItem], asOf: Date,
                                courseByID: [CanvasID<Course>: Course]) -> [GlanceDueItem] {
        let limit = TallyConfig.glanceDueItemLimit
        let candidates = planner.filter { !($0.markedComplete && $0.submitted) }
        let upcoming = candidates.filter { item in item.dueAt.map { $0 >= asOf } ?? false }.sorted(by: dueBefore)
        let overdue = candidates.filter { item in
            guard let dueAt = item.dueAt, dueAt < asOf else { return false }
            return !item.submitted && !item.excused
        }.sorted(by: dueBefore)
        let undated = candidates.filter { $0.dueAt == nil }

        let upcomingTaken = min(upcoming.count, max(0, limit - min(overdue.count, TallyConfig.glanceOverdueItemReserve)))
        let overdueTaken = min(overdue.count, limit - upcomingTaken)
        let chosen = overdue.suffix(overdueTaken) + upcoming.prefix(upcomingTaken)
            + undated.prefix(limit - upcomingTaken - overdueTaken)
        return chosen
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
