import Foundation

/// Plan 08 §4.2/§4.3 (work package XG-01): whether a course's grades can be shown from Canvas, and
/// if not, why. Some schools track assignments in Canvas but keep grades in a separate student
/// information system; for those courses Tally shows "—" and an explanation instead of a grade that
/// Canvas will never send. Derived from each snapshot plus `now`; nothing is persisted, so the state
/// recovers as soon as Canvas posts a grade (§4.2 "Recovery").
///
/// TallyCore emits no user-facing text (plan 08 §3.2): these are structured values, and the app
/// layer phrases them.
public nonisolated enum GradeAvailability: Hashable, Sendable {
    /// Canvas reports a course score or grade, and the course shows percentages.
    case available
    /// Canvas reports a course grade, and the course shows letters only (`restrict_quantitative_data`).
    case lettersOnly
    /// The instructor hides course totals (`hide_final_grades`) while grading in Canvas.
    case hiddenByInstructor
    /// No grade yet: early term, a slow grader, or grades posted later (today's "No grade yet").
    case notYetPosted
    /// The course has no graded work in Canvas at all (typical of advisory or homeroom courses).
    case notGradedInCanvas
    /// The course's grades do not appear to be kept in Canvas (§4.2 rule 5, or the student's override).
    case keptOutsideCanvas(Evidence)

    /// What Canvas showed when a course was classified `.keptOutsideCanvas`: counts only, never
    /// titles or scores.
    public nonisolated struct Evidence: Hashable, Sendable {
        /// Eligible items (§4.2 rule 4) due at least `InsightsConfig.externalGradesGraceWindow` ago.
        public let pastDueItems: Int
        /// How many of `pastDueItems` were submitted or are offline (`on_paper`/`none`).
        public let submittedOrOfflineItems: Int

        public init(pastDueItems: Int, submittedOrOfflineItems: Int) {
            self.pastDueItems = pastDueItems
            self.submittedOrOfflineItems = submittedOrOfflineItems
        }
    }

    /// The course's grades are in Canvas: `.available`, `.lettersOnly` or `.hiddenByInstructor`.
    /// Plan 08 §4.4 calls every other state "excluded" from grade analytics.
    public var isInCanvas: Bool {
        switch self {
        case .available, .lettersOnly, .hiddenByInstructor: true
        case .notYetPosted, .notGradedInCanvas, .keptOutsideCanvas: false
        }
    }
}

/// The student's per-course answer to "This course's grades are kept outside Canvas" (plan 08 G-3,
/// decided yes). `nil` means Automatic. The classifier only reads it; storing it is XG-04's
/// (`UserState` v5).
public nonisolated enum GradeAvailabilityOverride: String, Codable, Hashable, Sendable, CaseIterable {
    /// "Yes": always `.keptOutsideCanvas`.
    case keptOutsideCanvas
    /// "No": never `.keptOutsideCanvas`; the other rules still apply.
    case inCanvas
}

/// Plan 08 §4.2 "Per course versus per school": a summary over the courses whose state is
/// determinate. `.notYetPosted` and `.notGradedInCanvas` courses are ignored.
public nonisolated enum SchoolGradeSummary: Hashable, Sendable {
    /// At least one course is graded in Canvas, and none is kept outside it.
    case allInCanvas
    /// Some courses are graded in Canvas and `outside` courses are kept outside it.
    case mixed(outside: Int)
    /// At least one course is kept outside Canvas, and none is graded in it.
    case noneInCanvas
    /// No course has a determinate state yet.
    case undetermined

    public init(states: some Sequence<GradeAvailability>) {
        var inCanvas = 0, outside = 0
        for state in states {
            switch state {
            case .available, .lettersOnly, .hiddenByInstructor: inCanvas += 1
            case .keptOutsideCanvas: outside += 1
            case .notYetPosted, .notGradedInCanvas: continue
            }
        }
        switch (inCanvas > 0, outside > 0) {
        case (true, true): self = .mixed(outside: outside)
        case (false, true): self = .noneInCanvas
        case (true, false): self = .allInCanvas
        case (false, false): self = .undetermined
        }
    }
}

/// Every course's `GradeAvailability` plus the school summary, built once per (snapshot, overrides,
/// now) off the main actor and handed to each consumer (plan 08 §4.3), the same way
/// `PriorityScore.WeightContext` is precomputed once per course.
public nonisolated struct GradeAvailabilityIndex: Equatable, Sendable {
    public let byCourse: [CanvasID<Course>: GradeAvailability]
    public let school: SchoolGradeSummary

    public init(snapshot: CanvasSnapshot, overrides: [CanvasID<Course>: GradeAvailabilityOverride], now: Date) {
        self.init(courses: snapshot.courses, groups: snapshot.groups, overrides: overrides, now: now)
    }

    public init(courses: [Course], groups: [CanvasID<Course>: [AssignmentGroup]],
                overrides: [CanvasID<Course>: GradeAvailabilityOverride], now: Date) {
        var byCourse: [CanvasID<Course>: GradeAvailability] = [:]
        byCourse.reserveCapacity(courses.count)
        for course in courses where byCourse[course.id] == nil {
            // CS-07: a repeated course ID keeps its first occurrence instead of trapping or counting twice.
            byCourse[course.id] = GradeAvailabilityRules.classify(
                course: course, groups: groups[course.id] ?? [], now: now, override: overrides[course.id])
        }
        self.byCourse = byCourse
        self.school = SchoolGradeSummary(states: byCourse.values)
    }

    /// The course's state, or nil for a course this index was not built from.
    public subscript(courseID: CanvasID<Course>) -> GradeAvailability? { byCourse[courseID] }
}

/// Plan 08 §4.2's classifier: pure, nonisolated, one pass over a course's assignments. The first
/// matching rule wins:
/// 1. the student's override, if set;
/// 2. Canvas has a course score or grade → `.available`, `.lettersOnly` or `.hiddenByInstructor`;
/// 3. any graded signal on any assignment → `.hiddenByInstructor` (hidden totals) or `.notYetPosted`;
/// 4. no eligible item → `.notGradedInCanvas` when every item is ungraded by design, else `.notYetPosted`;
/// 5. the strict evidence threshold (G-2) → `.keptOutsideCanvas`, ahead of hidden totals and letters only;
/// 6. otherwise `.notYetPosted`.
public nonisolated enum GradeAvailabilityRules {
    /// Canvas's `workflow_state` for a graded submission.
    static let gradedWorkflowState = "graded"
    /// `submission_types` values meaning nothing is handed in through Canvas: the convention
    /// `AlertEngine.missingAlert` and `PriorityScore.isExcluded` already use.
    static let offlineSubmissionTypes: Set<String> = ["on_paper", "none"]

    public static func classify(course: Course, groups: [AssignmentGroup], now: Date,
                                override: GradeAvailabilityOverride?) -> GradeAvailability {
        // Rule 2 needs no assignment scan, so it goes first unless the override (rule 1) says
        // "kept outside", which needs the evidence counts and wins over everything.
        if override != .keptOutsideCanvas, hasCanvasCourseGrade(course) {
            switch course.gradeVisibility {
            case .visible: return .available
            case .lettersOnly: return .lettersOnly
            case .hiddenTotals: return .hiddenByInstructor
            }
        }
        let cutoff = now.addingTimeInterval(-InsightsConfig.externalGradesGraceWindow.timeInterval)
        let scan = Scan(groups: groups, cutoff: cutoff)
        let evidence = GradeAvailability.Evidence(pastDueItems: scan.pastDueItems,
                                                  submittedOrOfflineItems: scan.pastDueSubmittedOrOffline)
        // Rule 1.
        if override == .keptOutsideCanvas { return .keptOutsideCanvas(evidence) }
        // Rule 3: a teacher who grades in Canvas but posts later (manual posting policy).
        if scan.hasGradedSignal { return course.gradeVisibility == .hiddenTotals ? .hiddenByInstructor : .notYetPosted }
        // Rule 4.
        if scan.eligibleItems == 0 {
            return scan.publishedItems > 0 && scan.everyPublishedItemUngradedByDesign ? .notGradedInCanvas : .notYetPosted
        }
        // Rule 5, unless the student said the grades are in Canvas.
        if override != .inCanvas,
           evidence.pastDueItems >= InsightsConfig.externalGradesMinPastDueItems,
           evidence.submittedOrOfflineItems >= InsightsConfig.externalGradesMinSubmittedOrOffline {
            return .keptOutsideCanvas(evidence)
        }
        // Rule 6.
        return .notYetPosted
    }

    /// Rule 2: a current (graded-work-only) score or grade, for the course or its current grading
    /// period. Two deliberate readings of plan 08 §4.2 ("`scores` or `currentPeriodScores` non-nil"):
    /// - `scores` itself is non-nil for every course with a student enrollment row, even when every
    ///   field inside it is nil (`CourseMapper`, `CourseDTO.swift:64-65`), so the fields are tested.
    /// - The final score and grade are ignored: they count ungraded work as zero (`ComputedScores`),
    ///   so Canvas sends `computed_final_score: 0.0` (and, with a grading scheme, `"F"`) for a course
    ///   with nothing graded at all (`fixtures/canvas/personas/external-grades`, ENG-10).
    static func hasCanvasCourseGrade(_ course: Course) -> Bool {
        func has(_ scores: ComputedScores?) -> Bool { scores?.currentScore != nil || scores?.currentGrade != nil }
        return has(course.scores) || has(course.currentPeriodScores)
    }

    /// Rule 3: a posted score or grade, a `gradedAt` date, or `workflowState == "graded"`. Canvas
    /// withholds `score`/`grade` from a student until the grade is posted
    /// (`Submission#filter_attributes_for_user`, mirrored by tools/canvas-synth `submission_json`),
    /// so a non-nil one is a posted one. Whether Canvas exposes `graded_at`/`workflow_state` to a
    /// student for an unposted grade is UNVERIFIED (plan 08 §4.2); if not, rule 5's thresholds and
    /// the override are the only guards.
    static func isGradedSignal(_ submission: Submission) -> Bool {
        submission.score != nil || submission.grade != nil || submission.gradedAt != nil
            || submission.workflowState == gradedWorkflowState
    }

    /// Rule 4, for a published item (`Scan` skips unpublished ones first): in Canvas's gradeable
    /// scope, graded, counted toward the final grade, and worth points (or letter- or
    /// pass/fail-graded, which can carry a grade at zero points).
    static func isEligible(_ assignment: Assignment) -> Bool {
        guard assignment.isGradeable, assignment.gradingType != .notGraded,
              !assignment.omitFromFinalGrade else { return false }
        return (assignment.pointsPossible ?? 0) > 0
            || assignment.gradingType == .letterGrade || assignment.gradingType == .passFail
    }

    /// Rule 4's "not_graded or zero-point" item.
    static func isUngradedByDesign(_ assignment: Assignment) -> Bool {
        assignment.gradingType == .notGraded || !assignment.isGradeable || (assignment.pointsPossible ?? 0) <= 0
    }

    /// Rule 5's "offline" item: every `submission_types` value is `on_paper` or `none`.
    static func isOffline(_ assignment: Assignment) -> Bool {
        !assignment.submissionTypes.isEmpty && assignment.submissionTypes.allSatisfy(offlineSubmissionTypes.contains)
    }

    /// Everything rules 3–5 need, in one pass over the course's assignments.
    private struct Scan {
        var hasGradedSignal = false
        var publishedItems = 0
        var everyPublishedItemUngradedByDesign = true
        var eligibleItems = 0
        var pastDueItems = 0
        var pastDueSubmittedOrOffline = 0

        init(groups: [AssignmentGroup], cutoff: Date) {
            for group in groups {
                for assignment in group.assignments {
                    if let submission = assignment.submission, GradeAvailabilityRules.isGradedSignal(submission) {
                        hasGradedSignal = true
                    }
                    // Unpublished items never reach a student (`Assignment.published`), so they are not
                    // "assignments yet" for rule 4.
                    guard assignment.published else { continue }
                    publishedItems += 1
                    if !GradeAvailabilityRules.isUngradedByDesign(assignment) { everyPublishedItemUngradedByDesign = false }
                    guard GradeAvailabilityRules.isEligible(assignment) else { continue }
                    eligibleItems += 1
                    // "Due 14 or more days ago": an item due exactly at the cutoff counts.
                    guard let due = assignment.dueAt, due <= cutoff else { continue }
                    pastDueItems += 1
                    if assignment.submission?.isSubmitted == true || GradeAvailabilityRules.isOffline(assignment) {
                        pastDueSubmittedOrOffline += 1
                    }
                }
            }
        }
    }
}
