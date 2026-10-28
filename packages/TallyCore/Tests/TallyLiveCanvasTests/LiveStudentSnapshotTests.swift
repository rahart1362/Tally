import Foundation
import Testing
import TallyCanvasAPI
import TallyDomain
import TallyTestSupport

/// One real student refresh (`LiveCanvasGateway.fetchSnapshot`), fetched exactly once and
/// shared by every test below -- so "the requests per full refresh" (brief assertion 5) means
/// one full refresh, not one per `@Test`, and so the three assertions below (counts, grade
/// math, reminders/dashboard) all see the same live data.
actor LiveStudentFixture {
    static let shared = LiveStudentFixture()

    struct Result {
        let snapshot: CanvasSnapshot
        let logger: RecordingLogger
        let requests: Int
        let bytes: Int
        let milliseconds: Int
    }

    private var task: Task<Result, any Error>?

    /// `nil` config (not live) is a programmer error in this target -- every caller already
    /// gated on `LiveCanvasEnvironment.isLive` via `.enabled(if:)`.
    func result() async throws -> Result {
        if let task { return try await task.value }
        let newTask = Task { try await Self.fetch() }
        task = newTask
        return try await newTask.value
    }

    private static func fetch() async throws -> Result {
        let config = LiveCanvasEnvironment.config! // swiftlint:disable:this force_unwrapping -- gated by .enabled(if:)
        let session = LiveCanvasHarness.makeSession(config, accessToken: config.studentToken, userID: "live-student")
        let accountKey = AccountKey("live-student")
        let gateway = LiveCanvasGateway(host: config.host, accountKey: accountKey, client: session.client, logger: session.logger)

        let start = Date()
        let snapshot = try await gateway.fetchSnapshot(previous: nil, now: start)
        let elapsedMS = Int(Date().timeIntervalSince(start) * 1000)
        let requests = await session.meter.requestCount
        let bytes = await session.meter.byteCount
        // Brief assertion 5, exact format, student persona.
        print("LIVE-PERF | requests=\(requests) bytes=\(bytes) ms=\(elapsedMS) persona=student")
        return Result(snapshot: snapshot, logger: session.logger, requests: requests, bytes: bytes, milliseconds: elapsedMS)
    }
}

/// Seed counts (RUNBOOK.md "Tests" table / ~/canvas-e2e/tools/seed.py's own docstring): "5
/// courses, 19 weighted groups, 98 assignments ..., 10 events, 7 announcements". The brief's
/// assertion 1 is exactly these counts, read back through Tally's own real decode/mapping path
/// rather than Canvas's raw JSON -- a short count is exactly what a silently dropped (undecodable)
/// item would produce (`Mapped.dropped`, read by every mapper `LiveCanvasGateway` calls), so
/// "counts match the seed" doubles as "0 decode or mapping errors" without needing a second,
/// separate raw-JSON fetch against the same live server.
///
/// **`assignmentGroups` is 24, not the docstring's 19 -- finding F4 (live1-report.md), verified
/// read-only against the live server**: the fixture seed.py's own numbers describe
/// (`fixtures/canvas/personas/flagship/assignment_groups/*.json`: 3+4+4+4+4 = 19 *content*
/// groups) matches this live run's 98-assignment total exactly, but Canvas auto-creates one
/// empty, 0%-weight "Assignments" group per new course that seed.py never suppresses or
/// reuses, adding 5 more (one per course) that hold zero assignments. Confirmed by a direct
/// read-only `GET .../assignment_groups` per course (see the report): every course has exactly
/// one extra group named plain "Assignments", `group_weight: 0`, 0 assignments. This is a seed-
/// environment artifact, not a Tally defect -- the zero weight means it cannot skew
/// `GradeEngine`'s percent-weighted total (confirmed: assertion 2 matches Canvas's own
/// `computed_current_score` exactly for all 5 courses despite it), and Tally decodes/maps every
/// one of the 24 with 0 drops.
///
/// **`events` has no exact count asserted**: seed.py's "10 events" are 10 *series*, each created
/// with `calendar_event[rrule]` (seed.py:522-548's own comment: "rrule IS accepted and expands
/// the series"). `GET /api/v1/calendar_events` returns one row per *occurrence*, not per series,
/// so Tally's planner-window fetch (`TallyConfig.plannerWindowDays`, -14...+60 days from `now`)
/// legitimately returns far more than 10 rows (99, the day this was verified) -- and that number
/// drifts by design as `now` moves the 74-day window across each series' recurrence, so pinning
/// an exact figure here would make this test flaky on any day but the one it was written on.
/// The lower bound (at least one occurrence per series) is the one part of "10" that is actually
/// stable, and is asserted below.
private enum SeedCounts {
    static let courses = 5
    static let assignmentGroups = 24 // 19 content groups (seed.py) + 5 Canvas-default empty ones (F4)
    static let assignments = 98
    static let eventSeries = 10 // a lower bound on occurrences, not an exact count -- see doc comment above
    static let announcements = 7
}

@Suite("LIVE-1 assertion 1: full student snapshot vs. the seed", .enabled(if: LiveCanvasEnvironment.isLive))
struct LiveStudentSnapshotCountsTests {
    @Test("0 decode/mapping errors: every count matches the seed exactly")
    func snapshotCountsMatchSeed() async throws {
        let result = try await LiveStudentFixture.shared.result()
        let snapshot = result.snapshot

        #expect(snapshot.courses.count == SeedCounts.courses,
               "courses: got \(snapshot.courses.count), seed has \(SeedCounts.courses)")
        let groups = snapshot.groups.values.flatMap { $0 }
        #expect(groups.count == SeedCounts.assignmentGroups,
               "assignment groups: got \(groups.count), seed has \(SeedCounts.assignmentGroups)")
        let assignments = groups.flatMap(\.assignments)
        #expect(assignments.count == SeedCounts.assignments,
               "assignments: got \(assignments.count), seed has \(SeedCounts.assignments)")
        #expect(snapshot.events.count >= SeedCounts.eventSeries,
               "calendar events: got \(snapshot.events.count) occurrences, expected at least \(SeedCounts.eventSeries) (one per recurring series)")
        print("LIVE-EVENTS | occurrences=\(snapshot.events.count) seriesLowerBound=\(SeedCounts.eventSeries)")
        #expect(snapshot.announcements.count == SeedCounts.announcements,
               "announcements: got \(snapshot.announcements.count), seed has \(SeedCounts.announcements)")

        // CS-07's de-duplication path (SnapshotDeduplication) only has anything to drop when a
        // collection repeated an ID; a repeat here would mean the seed or the mapping produced
        // one, so this must stay empty against a seed built to be unique per CS-07's own design.
        let duplicateDrops = result.logger.events.filter {
            if case .duplicateIDsDropped = $0 { return true }; return false
        }
        #expect(duplicateDrops.isEmpty, "unexpected duplicate IDs dropped: \(duplicateDrops)")

        // Every optional section fetched cleanly this run (a live, reachable Canvas with a
        // scoped token should never need to carry one forward from a nonexistent `previous`).
        for section in SnapshotSection.allCases {
            #expect(snapshot.sections[section]?.carriedForward == false, "\(section) was carried forward, not freshly fetched")
        }
    }
}

@Suite("LIVE-1 assertion 2: grade math vs. Canvas's own computed scores", .enabled(if: LiveCanvasEnvironment.isLive))
struct LiveGradeMathTests {
    @Test("GradeEngine.currentScore matches Canvas's computed_current_score within 0.01, per course")
    func gradeMathMatchesCanvas() async throws {
        let snapshot = try await LiveStudentFixture.shared.result().snapshot
        var mismatches: [String] = []
        var table: [String] = []

        for course in snapshot.courses {
            let groups = snapshot.groups[course.id] ?? []
            let periods = snapshot.gradingPeriods[course.id] ?? []
            let tally = GradeEngine.scores(course: course, groups: groups, gradingPeriods: periods).currentScore
            let canvas = course.scores?.currentScore

            let tallyText: String = tally.map { "\($0)" } ?? "nil"
            let canvasText: String = canvas.map { "\($0)" } ?? "nil"
            var line = "LIVE-GRADE | course="
            line += course.courseCode
            line += " tally="
            line += tallyText
            line += " canvas="
            line += canvasText
            line += " weighted="
            line += String(course.appliesGroupWeights)
            table.append(line)

            switch (tally, canvas) {
            case (nil, nil):
                continue
            case (let t?, let c?):
                if abs(t - c) > 0.01 {
                    var mismatch = course.courseCode
                    mismatch += ": tally="
                    mismatch += String(t)
                    mismatch += " canvas="
                    mismatch += String(c)
                    mismatch += " diff="
                    mismatch += String(abs(t - c))
                    mismatches.append(mismatch)
                }
            default:
                var mismatch = course.courseCode
                mismatch += ": tally="
                mismatch += tallyText
                mismatch += " canvas="
                mismatch += canvasText
                mismatch += " (one nil, one not)"
                mismatches.append(mismatch)
            }
        }

        for line in table { print(line) }
        let mismatchReport = mismatches.joined(separator: "\n")
        #expect(mismatches.isEmpty, "grade mismatches:\n\(mismatchReport)")
    }
}

@Suite("LIVE-1 assertion 3: reminders + dashboard run cleanly on the live snapshot", .enabled(if: LiveCanvasEnvironment.isLive))
struct LiveRemindersAndDashboardTests {
    @Test("ReminderPlanner.plan: non-empty when due work exists, no past fire dates, cap respected")
    func reminderPlanIsSane() async throws {
        let snapshot = try await LiveStudentFixture.shared.result().snapshot
        let now = Date()
        let candidates = LiveCanvasHarness.candidates(from: snapshot)
        let plan = ReminderPlanner.plan(accountKey: AccountKey("live-student"), candidates: candidates,
                                        settings: ReminderSettings(), now: now, timeZone: .current, refresh: RefreshRecord())

        #expect(plan.allSatisfy { $0.fireDate > now }, "a reminder fired in the past")
        #expect(plan.count <= TallyConfig.pendingNotificationCap, "plan exceeded the pending-notification cap")
        let openDueSoon = candidates.contains {
            guard let due = $0.assignment.dueAt else { return false }
            return due > now && due <= now.addingTimeInterval(InsightsConfig.reminderHorizon.timeInterval)
        }
        if openDueSoon { #expect(!plan.isEmpty, "open work exists inside the reminder horizon but the plan is empty") }
        print("LIVE-REMINDERS | candidates=\(candidates.count) planned=\(plan.count)")
    }

    @Test("DashboardBuilder.build runs without throwing and produces a sane hero/next-up/due-soon")
    func dashboardProjectionIsSane() async throws {
        let snapshot = try await LiveStudentFixture.shared.result().snapshot
        let now = Date()
        let projection = DashboardBuilder.build(from: snapshot, digest: nil, digestAsOf: nil, now: now)

        let uniqueCourses = Set(snapshot.courses.map(\.id)).count
        #expect(projection.hero.courseCount == uniqueCourses, "hero course count disagrees with the snapshot")
        #expect(projection.nextUp.count <= 3, "next up exceeded its 3-item cap")
        #expect(projection.needsAttention.count <= 3, "needs attention exceeded its 3-item cap")
        #expect(projection.dueSoon.allSatisfy { ($0.dueAt ?? .distantFuture) > now }, "a due-soon item is already past due")
        #expect(projection.weekAhead.count == 7, "week-ahead strip was not 7 days")
        print("LIVE-DASHBOARD | courses=\(projection.hero.courseCount) nextUp=\(projection.nextUp.count) " +
             "attention=\(projection.needsAttention.count) dueSoon=\(projection.dueSoon.count)")
    }
}
