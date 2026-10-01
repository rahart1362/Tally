import Foundation
import Testing
@testable import TallyDomain

/// PERF-02's "parity test that runs the same inputs through both" (docs/pmo/05-perf-crash-charter.md,
/// implementation brief).
///
/// The charter's own root-cause section is explicit about why "both" cannot mean "the ported
/// `TallyDomain.DashboardBuilder` and the original `TallyFeatures.DashboardBuilder`, executed
/// side by side in one test run": *"`DashboardBuilder` lives in iOS-only TallyFeatures, so it
/// cannot be tested or benchmarked on Linux."* That target requires SwiftUI and declares
/// `platforms: [.iOS(.v26)]` in its own `Package.swift`; it does not build in this Linux
/// container (or in CI's `core-linux` job) at all — which is the entire reason this port
/// exists. `DashboardProjectionTests.swift` already re-runs the *original test suite's*
/// assertions (ported from `apps/TallyiOS/TallyAppTests/DashboardBuilderTests.swift` @ 6a98f4a)
/// against this port, over the real `flagship` fixture.
///
/// This file is the second, independent leg: a hand-built snapshot small enough that every
/// number below is derived from the published formulas (`PriorityScore.score`'s §5.1 formula,
/// `AlertEngine`'s A1/A3/A7 rules) in this comment, in the same spirit as `PriorityScoreTests`'s
/// own hand-computed "golden fixtures" — i.e. **both** means the pipeline's actual output vs. an
/// independently hand-derived expectation from the same published rules, not two executables.
/// If `DashboardBuilder`'s wiring (which course/groups a lookup uses, a sort direction, which
/// modifier feeds which factor) drifts from the algorithm as documented, this is the test that
/// catches it — unit tests for the individual engines (`PriorityScoreTests`, `AlertEngineTests`)
/// already cover each formula in isolation and would not.
@Suite("DashboardProjection parity: hand-derived expected values")
struct DashboardProjectionParityTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Fixture (every number is referenced by the hand-derivation below)

    /// - MATH 82.0%: A1 (10 pts, due +24h, no submission), A2 (190 pts, due +48h, already
    ///   graded+submitted — excluded from "Next up", but still counts toward MATH's weight
    ///   denominator, matching `PriorityScore.weight`'s `counted()` — it does not look at
    ///   submission state).
    /// - ART 100.0%: A3 (50 pts, due -1h, `lockAt` nil so still open, no submission).
    /// - SCI 72.0%: A4 (30 pts, due -2h, open, submission flagged `missing`), A5 (20 pts, due
    ///   +2h, open, submission present but not submitted/excused/missing).
    /// Every course's percent is deliberately kept >1.5pts from every `standardLetterBoundaries`
    /// entry (82.0 vs 80, 100.0 vs 97, 72.0 vs 70 — all >1.5 away) so `PriorityScore.courseModifiers`
    /// is `(false, false)` everywhere and `goal` stays irrelevant, keeping the arithmetic tractable.
    private static func snapshot() -> CanvasSnapshot {
        func course(_ id: String, code: String, score: Double) -> Course {
            Course(id: CanvasID(id), name: code, courseCode: code, term: nil, teachers: [], timeZone: nil,
                  appliesGroupWeights: false, hasGradingPeriods: false, currentGradingPeriodID: nil,
                  gradeVisibility: .visible,
                  scores: ComputedScores(currentScore: score, finalScore: score, currentGrade: nil, finalGrade: nil),
                  currentPeriodScores: nil, htmlURL: nil)
        }
        func assignment(_ id: String, course: CanvasID<Course>, group: CanvasID<AssignmentGroup>, points: Double,
                        dueOffsetHours: Double, submission: Submission?) -> Assignment {
            Assignment(id: CanvasID(id), courseID: course, groupID: group, name: "Assignment \(id)",
                      dueAt: now.addingTimeInterval(dueOffsetHours * 3600), lockAt: nil, pointsPossible: points,
                      gradingType: .points, omitFromFinalGrade: false, htmlURL: nil, submission: submission,
                      published: true, submissionTypes: ["online_upload"])
        }

        let math = course("math", code: "MATH", score: 82.0)
        let art = course("art", code: "ART", score: 100.0)
        let sci = course("sci", code: "SCI", score: 72.0)

        let a1 = assignment("a1", course: math.id, group: "g1", points: 10, dueOffsetHours: 24, submission: nil)
        let a2 = assignment("a2", course: math.id, group: "g1", points: 190, dueOffsetHours: 48,
                            submission: Submission(score: 180, grade: nil, submittedAt: now.addingTimeInterval(-3600),
                                                  gradedAt: now.addingTimeInterval(-1800), postedAt: now.addingTimeInterval(-1800),
                                                  excused: false, missing: false, late: false, workflowState: "graded"))
        let a3 = assignment("a3", course: art.id, group: "g2", points: 50, dueOffsetHours: -1, submission: nil)
        let a4 = assignment("a4", course: sci.id, group: "g3", points: 30, dueOffsetHours: -2,
                            submission: Submission(score: nil, grade: nil, submittedAt: nil, gradedAt: nil, postedAt: nil,
                                                  excused: false, missing: true, late: false, workflowState: "unsubmitted"))
        let a5 = assignment("a5", course: sci.id, group: "g3", points: 20, dueOffsetHours: 2,
                            submission: Submission(score: nil, grade: nil, submittedAt: nil, gradedAt: nil, postedAt: nil,
                                                  excused: false, missing: false, late: false, workflowState: "unsubmitted"))

        let groups: [CanvasID<Course>: [AssignmentGroup]] = [
            math.id: [AssignmentGroup(id: "g1", name: "G1", position: 0, weight: nil, rules: DropRules(), assignments: [a1, a2])],
            art.id: [AssignmentGroup(id: "g2", name: "G2", position: 0, weight: nil, rules: DropRules(), assignments: [a3])],
            sci.id: [AssignmentGroup(id: "g3", name: "G3", position: 0, weight: nil, rules: DropRules(), assignments: [a4, a5])],
        ]
        let sections = Dictionary(uniqueKeysWithValues: SnapshotSection.allCases.map { ($0, SectionStatus(fetchedAt: now, carriedForward: false)) })
        return CanvasSnapshot(generation: 1, accountKey: AccountKey("parity"), host: "canvas.parity.example", fetchedAt: now,
                              profile: UserProfile(id: "1", name: "Parity Student", shortName: nil, timeZone: nil, calendarFeedURL: nil),
                              courses: [math, art, sci], groups: groups, gradingPeriods: [:], planner: [],
                              events: [], announcements: [], courseColors: [:], sections: sections)
    }

    // MARK: - Hero: mean of 82.0, 100.0, 72.0 = 84.6667, in [80, 90) -> .bRange

    @Test func heroIsTheMeanOfAllThreeVisibleCourses() {
        let state = DashboardBuilder.build(from: Self.snapshot(), digest: nil, digestAsOf: nil, now: Self.now)
        #expect(state.hero.courseCount == 3)
        #expect(abs(state.hero.overallPercent! - 84.6667) < 0.001)
        #expect(state.hero.overallBand == .bRange)
    }

    // MARK: - Next up: A2 excluded (graded+submitted). Of {A1, A3, A4, A5}, scores are
    // A4 = A3 = 100.0 (both `min(100, ...)`-capped — see file header), A5 ~= 97.5543, A1 ~= 64.6761
    // (worked from `PriorityScore.score`'s formula with tau=48, wRef=0.10, alpha=0.6). A4 and A3
    // tie exactly at the cap, so `PriorityScore.sorted`'s due-date tie-break decides: A4 (-2h) is
    // due earlier than A3 (-1h), so A4 sorts first. A1 (~64.68) is 4th and is cut by the top-3 cap.

    @Test func nextUpIsScoreRankedTieBrokenByDueDateAndCappedAtThree() {
        let state = DashboardBuilder.build(from: Self.snapshot(), digest: nil, digestAsOf: nil, now: Self.now)
        #expect(state.nextUp.map(\.id.rawValue) == ["a4", "a3", "a5"]) // a1 cut by the top-3 cap
        #expect(state.nextUp.map(\.band) == [.high, .high, .high])
    }

    /// The reason, worked from `PriorityScore.reasonFactors`: the due-date clause always leads,
    /// then up to two of {below-goal/near-boundary, still-accepted, course-weight (only when
    /// weight >= `priorityReasonWeightFloor` = 0.05)}, in that priority order. Plan 08 L10N-02:
    /// the projection carries the factors; the app phrases them (before, this test compared the
    /// English "Overdue · Still accepted · ~60% of SCI" and so on, which the hosted renderer
    /// goldens now pin).
    @Test func nextUpReasonFactorsMatchTheFormula() {
        let state = DashboardBuilder.build(from: Self.snapshot(), digest: nil, digestAsOf: nil, now: Self.now)
        let byID = Dictionary(uniqueKeysWithValues: state.nextUp.map { ($0.id.rawValue, $0.reasonFactors) })
        let parts = byID.mapValues { $0.map(PriorityScore.reasonPart) }
        // A4: overdue (h=-2h) + still-accepted (open, overdue) + weight 30/50=0.6 of SCI.
        #expect(byID["a4"] == [.overdue, .stillAccepted, .courseWeight(0.6)])
        #expect(parts["a4"] == [.overdue, .stillAccepted, .courseWeightPercent(60)])
        // A3: overdue (h=-1h) + still-accepted + weight 50/50=1.0 (only counted item) of ART.
        #expect(byID["a3"] == [.overdue, .stillAccepted, .courseWeight(1.0)])
        #expect(parts["a3"] == [.overdue, .stillAccepted, .courseWeightPercent(100)])
        // A5: due in +2h (not overdue, so no still-accepted) + weight 20/50=0.4 of SCI.
        #expect(parts["a5"] == [.dueInHours(2), .courseWeightPercent(40)])
        #expect(state.nextUp.map(\.courseCode) == ["SCI", "ART", "SCI"])
    }

    // MARK: - Needs attention: A1/A3 raise nothing (no submission -> `AlertEngine`'s guards all
    // require one). A2 has a submission but is already submitted, so every `AlertEngine` guard
    // in `needsAttention` short-circuits on `!submission.isSubmitted`. That leaves:
    // - A4: `missingAlert` fires (`submission.missing == true`, open) -> `.missingOpen`, severity
    //   .high (300), rank 300.
    // - A5: not missing, due soon (+2h < 3h critical window); its own `PriorityScore.score` with
    //   weight 20/50=0.4 comes out ~97.55 (>= the 60-point critical floor) -> `.dueSoon` fires
    //   at `.critical` (400), rank 400 + Int(97.55) = 497.
    // - The one `AlertEngine.LoadItem` in the next 10 days is A5 alone (A4's due date is in the
    //   past, so `needsAttention`'s own `due >= now` guard excludes it from `loadItems`), and its
    //   course-weight share alone (0.4) already clears `overloadMinCourseWeight` (0.15) — Canvas's
    //   rule fires on a single heavy item, not only a crowd — so `overloadClusters` still reports
    //   one `.overloadCluster` alert, severity .high (300, since 2h <= the 48h "high" window), rank 300.
    // Sorted by rank descending, ties broken by insertion order (Swift's sort is stable; the
    // per-assignment loop appends A4 before the overload pass runs): dueSoon(497), missingOpen(300),
    // overloadCluster(300) — all three fit the top-3 cap exactly.
    @Test func needsAttentionOrdersByRankThenStableInsertionOrder() {
        let state = DashboardBuilder.build(from: Self.snapshot(), digest: nil, digestAsOf: nil, now: Self.now)
        #expect(state.needsAttention.count == 3)
        #expect(state.needsAttention.map(\.id) == ["due:a5", "missing:a4", "overload:\(Int(Self.now.addingTimeInterval(2 * 3600).timeIntervalSince1970))"])
        #expect(state.needsAttention.map(\.severity) == [.critical, .high, .high])
        // Plan 08 L10N-02: every row is a value now, its dates exact (the port used to format them
        // as a fixed `HH:mm` and an ISO date, which varied with the run's time zone).
        #expect(state.needsAttention.map(\.content) == [
            .dueSoon(title: "Assignment a5", dueAt: Self.now.addingTimeInterval(2 * 3600), courseCode: "SCI"),
            .missingOpen(title: "Assignment a4", courseCode: "SCI"),
            .overload(start: Self.now.addingTimeInterval(2 * 3600)),
        ])
    }

    // MARK: - Due soon / Week ahead: no planner items in this fixture, so both are trivially empty/zero.

    @Test func dueSoonAndWeekAheadAreEmptyWithNoPlannerItems() {
        let state = DashboardBuilder.build(from: Self.snapshot(), digest: nil, digestAsOf: nil, now: Self.now)
        #expect(state.dueSoon.isEmpty)
        #expect(state.weekAhead.count == 7)
        #expect(state.weekAhead.allSatisfy { $0.dueCount == 0 && !$0.isBusy })
    }

    // MARK: - Digest chip: the count and the time, as values.

    @Test func digestChipReportsTheExactChangeCount() {
        let digest = ChangeDigest(
            gradeChanges: [], newAssignments: [ChangeDigest.NewAssignment(courseID: "math", assignmentID: "a99", dueAt: nil)],
            dueDateChanges: [], newAnnouncements: [], courseScoreChanges: [])
        let state = DashboardBuilder.build(from: Self.snapshot(), digest: digest, digestAsOf: Self.now, now: Self.now)
        #expect(state.changeDigestSummary == DashboardProjection.ChangeSummary(count: 1, asOf: Self.now))
    }
}
