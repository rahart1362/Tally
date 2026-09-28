import Foundation
import TallyDomain

/// PERF-01 (docs/pmo/05-perf-crash-charter.md "Data scales to test"): a synthetic "stress"
/// account, generated in-test — deliberately **not** a fixture file, since the charter is
/// explicit that this scale is manufactured, not captured from Canvas. Deterministic via
/// `SeededRandom`, so two calls with the same `Scale` produce byte-identical output (required
/// for the `ChangeDigest`/`GradeEngine` benchmarks below to be reproducible across CI runs).
///
/// Every assignment, submission, drop rule and grading period is built from the input index
/// alone (no wall-clock/system randomness anywhere), matching the implementation brief's
/// "never fabricate... test data is hand-built inside tests" rule: this is hand-built, just
/// parametrically rather than literally.
public enum StressSnapshotFixture {
    /// One scale point. `.stress` is the charter's mandated floor ("20 courses x 250
    /// assignments... a year of planner items"). `.scalingBaseline` has the exact same
    /// per-course shape at 1/10th the course count, so PERF-04's scaling gate compares two
    /// snapshots that differ only in size, not in kind.
    public struct Scale: Sendable, Equatable {
        public var courseCount: Int
        public var assignmentsPerCourse: Int
        public var groupsPerCourse: Int
        public var plannerItemCount: Int
        public var seed: UInt64

        public init(courseCount: Int, assignmentsPerCourse: Int, groupsPerCourse: Int = 5,
                    plannerItemCount: Int, seed: UInt64 = 0xC0FF_EE00) {
            self.courseCount = courseCount
            self.assignmentsPerCourse = assignmentsPerCourse
            self.groupsPerCourse = groupsPerCourse
            self.plannerItemCount = plannerItemCount
            self.seed = seed
        }

        public var totalAssignments: Int { courseCount * assignmentsPerCourse }

        /// The charter's floor: ">= 20 courses x 250 assignments, with submissions, drop
        /// rules, grading periods and a year of planner items."
        public static let stress = Scale(courseCount: 20, assignmentsPerCourse: 250, plannerItemCount: 1095)
        /// PERF-04 "10x the data costs no more than ~12x the time": identical shape to
        /// `.stress`, 1/10th the course count (and so ~1/10th the assignments and planner
        /// items), same seed.
        public static let scalingBaseline = Scale(courseCount: 2, assignmentsPerCourse: 250,
                                                  plannerItemCount: 110, seed: Scale.stress.seed)
    }

    /// Matches `TestClock`'s and the fixtures' own anchor instant, so stress-scale dates sit
    /// in the same neighbourhood as the flagship/large personas' recorded dates.
    public static let referenceDate = Date(timeIntervalSince1970: 1_790_600_400)

    public static func make(scale: Scale = .stress, now: Date = referenceDate) -> CanvasSnapshot {
        var rng = SeededRandom(seed: scale.seed)
        let courses = (0..<scale.courseCount).map { makeCourse($0, now: now, rng: &rng) }

        var groups: [CanvasID<Course>: [AssignmentGroup]] = [:]
        var gradingPeriods: [CanvasID<Course>: [GradingPeriod]] = [:]
        for (index, course) in courses.enumerated() {
            let periods = course.hasGradingPeriods ? makeGradingPeriods(courseIndex: index, now: now) : []
            gradingPeriods[course.id] = periods
            groups[course.id] = makeGroups(courseIndex: index, course: course, periods: periods, scale: scale, rng: &rng)
        }

        let planner = makePlanner(scale: scale, courses: courses, rng: &rng)
        let sections = Dictionary(uniqueKeysWithValues: SnapshotSection.allCases.map {
            ($0, SectionStatus(fetchedAt: now, carriedForward: false))
        })

        return CanvasSnapshot(
            generation: 1, accountKey: AccountKey("stress-account"), host: "canvas.stress.example", fetchedAt: now,
            profile: UserProfile(id: CanvasID("9000000"), name: "Stress Student", shortName: "Stress",
                                timeZone: "America/New_York", calendarFeedURL: nil),
            courses: courses, groups: groups, gradingPeriods: gradingPeriods, planner: planner,
            events: [], announcements: [],
            courseColors: Dictionary(uniqueKeysWithValues: courses.map { ($0.id, "#4B7BE5") }),
            sections: sections)
    }

    // MARK: - Courses

    private static func makeCourse(_ index: Int, now: Date, rng: inout SeededRandom) -> Course {
        let id = CanvasID<Course>("stress-course-\(index)")
        let appliesWeights = index.isMultiple(of: 2)
        let hasPeriods = index.isMultiple(of: 3)
        let weightedPeriods = hasPeriods && index.isMultiple(of: 6)
        let visibility: GradeVisibility = index.isMultiple(of: 17) ? .hiddenTotals
            : index.isMultiple(of: 11) ? .lettersOnly : .visible
        let score = 55.0 + Double(Int.random(in: 0...450, using: &rng)) / 10.0 // 55.0...100.0

        return Course(
            id: id, name: "Stress Course \(index)", courseCode: "STRESS \(100 + index)",
            term: Term(id: CanvasID("stress-term-\(index % 4)"), name: "Term \(index % 4)",
                      startAt: now.addingTimeInterval(-180 * 86400), endAt: now.addingTimeInterval(180 * 86400)),
            teachers: [Teacher(id: CanvasID("stress-teacher-\(index)"), displayName: "Instructor \(index)")],
            timeZone: "America/New_York", appliesGroupWeights: appliesWeights, hasGradingPeriods: hasPeriods,
            currentGradingPeriodID: nil, gradeVisibility: visibility,
            scores: ComputedScores(currentScore: score, finalScore: max(0, score - 2), currentGrade: nil, finalGrade: nil),
            currentPeriodScores: nil,
            htmlURL: URL(string: "https://canvas.stress.example/courses/\(id.rawValue)"),
            hasWeightedGradingPeriods: weightedPeriods, studentEnrollmentCompleted: false)
    }

    private static func makeGradingPeriods(courseIndex: Int, now: Date) -> [GradingPeriod] {
        let quarter = 91.0 * 86400.0
        let start = now.addingTimeInterval(-180 * 86400)
        return (0..<4).map { q in
            let periodStart = start.addingTimeInterval(Double(q) * quarter)
            let periodEnd = periodStart.addingTimeInterval(quarter)
            return GradingPeriod(id: CanvasID("stress-period-\(courseIndex)-\(q)"), title: "Q\(q + 1)",
                                 startDate: periodStart, endDate: periodEnd, closeDate: periodEnd,
                                 weight: 25.0, isClosed: periodEnd < now)
        }
    }

    // MARK: - Assignment groups + assignments

    private static func makeGroups(courseIndex: Int, course: Course, periods: [GradingPeriod],
                                   scale: Scale, rng: inout SeededRandom) -> [AssignmentGroup] {
        let groupCount = max(1, scale.groupsPerCourse)
        let perGroup = Int((Double(scale.assignmentsPerCourse) / Double(groupCount)).rounded(.up))
        let groupWeight = 100.0 / Double(groupCount)
        var remaining = scale.assignmentsPerCourse
        var globalIndex = 0
        var groups: [AssignmentGroup] = []

        for g in 0..<groupCount where remaining > 0 {
            let count = min(perGroup, remaining)
            remaining -= count
            let groupID = CanvasID<AssignmentGroup>("stress-group-\(courseIndex)-\(g)")
            // Vary drop rules across groups (F3.3 coverage: none / drop-lowest / drop-both),
            // always leaving at least one never-drop item so the kept set is never emptied.
            let dropLowest = g == 0 ? 1 : (g == 1 ? 2 : 0)
            let dropHighest = g == 1 ? 1 : 0

            var assignments: [Assignment] = []
            var neverDrop: [CanvasID<Assignment>] = []
            for i in 0..<count {
                let assignment = makeAssignment(courseIndex: courseIndex, groupID: groupID, index: globalIndex,
                                                course: course, periods: periods, rng: &rng)
                assignments.append(assignment)
                if i == 0, dropLowest + dropHighest > 0 { neverDrop.append(assignment.id) }
                globalIndex += 1
            }
            groups.append(AssignmentGroup(
                id: groupID, name: "Group \(g)", position: g,
                weight: course.appliesGroupWeights ? groupWeight : nil,
                rules: DropRules(dropLowest: dropLowest, dropHighest: dropHighest, neverDrop: neverDrop),
                assignments: assignments))
        }
        return groups
    }

    private static func makeAssignment(courseIndex: Int, groupID: CanvasID<AssignmentGroup>, index: Int,
                                       course: Course, periods: [GradingPeriod], rng: inout SeededRandom) -> Assignment {
        let id = CanvasID<Assignment>("stress-assign-\(courseIndex)-\(index)")
        let now = referenceDate
        let hasDueDate = !index.isMultiple(of: 23)
        let dayOffset = Int.random(in: -182...182, using: &rng)
        let secondOfDay = Int.random(in: 0..<86400, using: &rng)
        let dueAt: Date? = hasDueDate ? now.addingTimeInterval(Double(dayOffset) * 86400 + Double(secondOfDay)) : nil
        let lockAt = dueAt.map { $0.addingTimeInterval(Double(Int.random(in: 0...172_800, using: &rng))) }
        let possible: Double? = index.isMultiple(of: 31) ? nil : [10.0, 20.0, 25.0, 50.0, 100.0][index % 5]
        let submissionTypes: [String] = index.isMultiple(of: 13) ? ["not_graded"]
            : index.isMultiple(of: 29) ? ["none"] : ["online_upload"]
        let isPast = (dueAt ?? now.addingTimeInterval(86400)) < now
        let periodID = dueAt.flatMap { due in periods.first { $0.startDate < due && due <= $0.endDate }?.id }
        let hasSubmission = !index.isMultiple(of: 19)

        return Assignment(
            id: id, courseID: course.id, groupID: groupID, name: "Stress Assignment \(index)",
            dueAt: dueAt, lockAt: lockAt, pointsPossible: possible, gradingType: .points,
            omitFromFinalGrade: index.isMultiple(of: 41), htmlURL: nil,
            submission: hasSubmission ? makeSubmission(index: index, isPast: isPast, possible: possible,
                                                       periodID: periodID, now: now, rng: &rng) : nil,
            published: !index.isMultiple(of: 53), submissionTypes: submissionTypes)
    }

    private static func makeSubmission(index: Int, isPast: Bool, possible: Double?,
                                       periodID: CanvasID<GradingPeriod>?, now: Date, rng: inout SeededRandom) -> Submission {
        let excused = index.isMultiple(of: 37)
        let missing = isPast && !excused && index.isMultiple(of: 7)
        let late = isPast && !missing && !excused && index.isMultiple(of: 5)
        let graded = isPast && !missing && !excused && !index.isMultiple(of: 3)
        // Whether the student has turned this in yet. Past-due work that isn't `missing` has
        // been (the common case once a deadline has passed); future-due work is mostly *not*
        // submitted yet (~20% turned it in early, `index.isMultiple(of: 5)`) — this is what
        // benchmarks exercising AlertEngine's "due soon"/"overload cluster" paths need, since
        // both only ever look at *unsubmitted* future work. An earlier version of this
        // generator set `submittedAt` unconditionally (anchored to `now` regardless of the
        // assignment's own due date), so every future-due, non-missing item read as already
        // submitted and those paths silently saw zero items at every scale — found via a
        // temporary diagnostic print while investigating why a mutation check on
        // `AlertEngine.overloadClusters` showed no measurable difference (see PERF-03 in
        // docs/pmo/reviews/perf-core.md for the full story).
        let hasTurnedIn = missing ? false : (isPast || index.isMultiple(of: 5))
        let submittedAt: Date? = hasTurnedIn ? now.addingTimeInterval(-Double(Int.random(in: 0...5, using: &rng)) * 86400) : nil
        let score = graded ? (possible ?? 10) * Double.random(in: 0.55...1.0, using: &rng) : nil
        return Submission(
            score: score, grade: nil, submittedAt: submittedAt, gradedAt: graded ? submittedAt : nil,
            postedAt: graded ? submittedAt : nil, excused: excused, missing: missing, late: late,
            workflowState: missing ? "unsubmitted" : (graded ? "graded" : (hasTurnedIn ? "submitted" : "unsubmitted")),
            id: CanvasID("stress-sub-\(index)"), gradingPeriodID: periodID)
    }

    // MARK: - Planner (a year of items)

    private static func makePlanner(scale: Scale, courses: [Course], rng: inout SeededRandom) -> [PlannerItem] {
        guard !courses.isEmpty else { return [] }
        return (0..<scale.plannerItemCount).map { i in
            let course = courses[i % courses.count]
            let dayOffset = Int.random(in: -182...182, using: &rng)
            let due = referenceDate.addingTimeInterval(Double(dayOffset) * 86400)
            let missing = i.isMultiple(of: 11)
            let submitted = !missing && i.isMultiple(of: 2)
            return PlannerItem(
                id: "stress-planner:\(i)", courseID: course.id,
                title: "Stress planner item \(i), a title long enough to exercise glance truncation",
                plannableType: i.isMultiple(of: 4) ? "planner_note" : "assignment", dueAt: due,
                pointsPossible: 10, submitted: submitted, graded: false, missing: missing, late: false,
                excused: false, markedComplete: false, htmlURL: nil)
        }
    }
}
