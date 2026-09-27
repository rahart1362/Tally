// PERF-01 (docs/pmo/05-perf-crash-charter.md): the core benchmark harness. Everything in this
// file is compiled out under a debug build (`#if !DEBUG`), so `make core-test` (plain `swift
// test`) neither runs nor pays the setup cost of these benchmarks — only `make core-perf`
// (`swift test -c release --filter TallyPerfTests`) does. Release-mode timings are what the
// charter's budgets are stated against ("Linux x86 release builds are faster than the oldest
// iPhone... each perf gate must state its device-to-CI factor").
//
// Every measurement runs at three scales (charter "Data scales to test"): `flagship` (5
// courses), `large` (12 courses, 153 assignments) and `stress` (>= 20 courses x 250
// assignments, synthetic, generated in-test — `StressSnapshotFixture`). Numbers are printed as
// grep-able `PERF | ...` / `PERF-MEM | ...` lines (`BenchmarkSupport.swift`); the PMO report
// transcribes real `make core-perf` output rather than restating them here, so this file never
// goes stale relative to what actually ran.
#if !DEBUG
import Foundation
import Testing
import TallyCanvasAPI
import TallyDomain
import TallyStore
import TallyTestSupport

enum BenchScale: String, CaseIterable, Sendable, CustomStringConvertible {
    case flagship, large, stress
    var description: String { rawValue }
}

/// A local error type: `TallyTestSupport.FixtureError`'s initializer is `internal` to that
/// module, so this file (a different target) cannot construct one.
struct PerfCheckError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

/// Never actually invoked: every credential below is minted with a far-future expiry and no
/// benchmark injects a 401, so `TokenCoordinator` never needs to refresh. A loud crash (rather
/// than a silently-wrong token) if that assumption is ever broken by a future edit here.
private struct NeverRefresher: TokenRefreshing {
    func refresh(_ credential: CanvasCredential) async throws -> CanvasCredential {
        fatalError("PerfFixtures: a refresh was requested; the fixed-expiry credential assumption broke")
    }
}

/// One scale's fully-built inputs, shared by every measurement category below. Built fresh per
/// `@Test` (Swift Testing gives each `@Test(arguments:)` case its own call): flagship/large are
/// small fixture-backed personas (a handful of ms), and `stress`'s generator is pure, in-memory
/// computation (tens of ms) — cheap enough not to need cross-test caching.
struct PerfContext {
    let name: String
    let host: String
    let snapshot: CanvasSnapshot
    /// The "old" side of `ChangeDigest.diff`. Real for `flagship` (the `flagship-previous`
    /// fixture pair); for `large`/`stress`, no captured "previous" exists, so this is `snapshot`
    /// itself (a self-diff). `diff` does not short-circuit on equality — it still builds both
    /// ID-keyed maps and walks every assignment/course/announcement — so the CPU cost is
    /// representative even though the resulting digest is empty.
    let digestOld: CanvasSnapshot
    let gateway: LiveCanvasGateway
    /// Reusable across repeated `fetchSnapshot` calls: flagship/large routes are matched fresh
    /// every request (never consumed), and the stress transport's injections are registered
    /// with enough `times` headroom for warmup + every timed iteration.
    let transport: ReplayTransport
}

enum PerfFixtures {
    static let anchor = StressSnapshotFixture.referenceDate

    private static func client(transport: any HTTPTransport, host: String) -> CanvasClient {
        let credential = CanvasCredential(host: host, userID: "perf-user", accessToken: "perf-token",
                                          refreshToken: "perf-refresh",
                                          accessTokenExpiresAt: anchor.addingTimeInterval(365 * 86400))
        let coordinator = TokenCoordinator(initial: credential, store: InMemoryCredentialStore(credential),
                                           refresher: NeverRefresher(), clock: TestClock(anchor))
        return CanvasClient(host: host, transport: transport, tokens: coordinator)
    }

    static func context(for scale: BenchScale) async throws -> PerfContext {
        switch scale {
        case .flagship, .large:
            let routes = try CanvasManifest.personaRoutes(scale.rawValue)
            guard let host = routes.first?.host else { throw PerfCheckError(message: "\(scale.rawValue): no routes") }
            let transport = try ReplayTransport.persona(scale.rawValue)
            let gateway = LiveCanvasGateway(host: host, accountKey: AccountKey("perf-\(scale.rawValue)"),
                                           client: client(transport: transport, host: host))
            let snapshot = try await gateway.fetchSnapshot(previous: nil, now: anchor)

            let digestOld: CanvasSnapshot
            if scale == .flagship {
                let oldTransport = try ReplayTransport.persona("flagship-previous")
                let oldGateway = LiveCanvasGateway(host: host, accountKey: AccountKey("perf-flagship-previous"),
                                                   client: client(transport: oldTransport, host: host))
                digestOld = try await oldGateway.fetchSnapshot(previous: nil, now: anchor.addingTimeInterval(-7 * 86400))
            } else {
                digestOld = snapshot
            }
            return PerfContext(name: scale.rawValue, host: host, snapshot: snapshot, digestOld: digestOld,
                               gateway: gateway, transport: transport)

        case .stress:
            let host = "canvas.stress.example"
            let snapshot = StressSnapshotFixture.make(scale: .stress, now: anchor)
            let transport = await StressCanvasTransport.prepare(from: snapshot)
            let gateway = LiveCanvasGateway(host: host, accountKey: AccountKey("perf-stress"),
                                           client: client(transport: transport, host: host))
            return PerfContext(name: "stress", host: host, snapshot: snapshot, digestOld: snapshot,
                               gateway: gateway, transport: transport)
        }
    }
}

/// One course's fixture-response JSON pair, pre-loaded (never inside a timed region): the raw
/// `courses.json` body plus every course's `assignment_groups` body, so "mapper decode" measures
/// decode cost alone, not disk I/O or (for stress) JSON generation.
struct MapperBodies {
    let coursesBody: Data
    let perCourse: [(courseID: CanvasID<Course>, body: Data)]
    let host: String
}

func loadMapperBodies(for scale: BenchScale, context: PerfContext) throws -> MapperBodies {
    switch scale {
    case .flagship, .large:
        let coursesBody = try Fixtures.data("personas/\(scale.rawValue)/courses.json")
        let courses = try CourseMapper.map(coursesBody, host: context.host).items
        let perCourse = try courses.map { course in
            (course.id, try Fixtures.data("personas/\(scale.rawValue)/assignment_groups/\(course.id.rawValue).json"))
        }
        return MapperBodies(coursesBody: coursesBody, perCourse: perCourse, host: context.host)
    case .stress:
        let coursesBody = StressCanvasJSON.courses(context.snapshot.courses)
        let perCourse = context.snapshot.courses.map { course in
            (course.id, StressCanvasJSON.assignmentGroups(context.snapshot.groups[course.id] ?? [], courseID: course.id))
        }
        return MapperBodies(coursesBody: coursesBody, perCourse: perCourse, host: context.host)
    }
}

/// Every open assignment paired with its course and that course's groups (both needed for
/// `PriorityScore.weight`) — the same shape `DashboardBuilder.openAssignments` (app-core,
/// pre-PERF-02) builds. Duplicated here rather than imported: at PERF-01 time `DashboardBuilder`
/// is still iOS-only (`TallyFeatures`) and unreachable from this Linux-testable target: this is
/// exactly the gap PERF-02 closes.
func openAssignments(in snapshot: CanvasSnapshot) -> [(course: Course, groups: [AssignmentGroup], assignment: Assignment)] {
    let coursesByID = Dictionary(uniqueKeysWithValues: snapshot.courses.map { ($0.id, $0) })
    return snapshot.groups.flatMap { courseID, groups -> [(Course, [AssignmentGroup], Assignment)] in
        guard let course = coursesByID[courseID] else { return [] }
        return groups.flatMap(\.assignments).map { (course, groups, $0) }
    }
}

/// Mirrors `DashboardBuilder.priorityModifiers` exactly (course goals are not modelled before
/// PERF-02 threads real settings through, so `goal` is `nil` here too, matching the source).
func priorityModifiers(assignment: Assignment, course: Course, now: Date) -> PriorityScore.Modifiers {
    let overdueStillOpen: Bool = {
        guard let due = assignment.dueAt, due < now else { return false }
        return assignment.lockAt == nil || assignment.lockAt! > now
    }()
    let (belowGoal, nearBoundary) = PriorityScore.courseModifiers(currentScore: course.scores?.currentScore, goal: nil)
    return PriorityScore.Modifiers(overdueStillOpen: overdueStillOpen, courseBelowGoal: belowGoal, nearBoundary: nearBoundary)
}

// `.serialized`: Swift Testing parallelizes `@Test` cases by default, and several benchmarks
// running concurrently on shared cores is exactly the kind of noise a wall-clock timing harness
// cannot tolerate (observed directly: some samples 2-5x their suite's own median before this was
// added). Every benchmark in this suite runs one at a time instead.
@Suite("PERF-01: core benchmark harness", .serialized)
struct CoreBenchmarks {
    // MARK: - Mapper decode

    @Test("mapper decode of the fixture responses", arguments: BenchScale.allCases)
    func mapperDecode(_ scale: BenchScale) async throws {
        let context = try await PerfFixtures.context(for: scale)
        let bodies = try loadMapperBodies(for: scale, context: context)
        try Bench.time("mapperDecode/\(scale)") {
            _ = try CourseMapper.map(bodies.coursesBody, host: bodies.host)
            for (courseID, body) in bodies.perCourse {
                _ = try AssignmentGroupMapper.map(body, courseID: courseID)
            }
        }
    }

    // MARK: - Full refresh (LiveCanvasGateway.fetchSnapshot over ReplayTransport)

    @Test("LiveCanvasGateway.fetchSnapshot over ReplayTransport", arguments: BenchScale.allCases)
    func fullRefresh(_ scale: BenchScale) async throws {
        let context = try await PerfFixtures.context(for: scale)
        try await Bench.timeAsync("fullRefresh/\(scale)") {
            _ = try await context.gateway.fetchSnapshot(previous: nil, now: PerfFixtures.anchor)
        }
    }

    // MARK: - CanvasSnapshot JSON encode/decode + encoded size

    @Test("CanvasSnapshot JSON encode/decode", arguments: BenchScale.allCases)
    func snapshotEncodeDecode(_ scale: BenchScale) async throws {
        let context = try await PerfFixtures.context(for: scale)
        let encoded = try JSONEncoder().encode(context.snapshot)
        print("PERF-SIZE | \(scale) | encodedSnapshotBytes=\(encoded.count)")

        try Bench.time("snapshotEncode/\(scale)") { _ = try JSONEncoder().encode(context.snapshot) }
        try Bench.time("snapshotDecode/\(scale)") { _ = try JSONDecoder().decode(CanvasSnapshot.self, from: encoded) }
    }

    // MARK: - VaultSealer seal/open

    @Test("VaultSealer seal/open", arguments: BenchScale.allCases)
    func vaultSealerSealOpen(_ scale: BenchScale) async throws {
        let context = try await PerfFixtures.context(for: scale)
        let plaintext = try JSONEncoder().encode(context.snapshot)
        let sealer = VaultSealer(account: "perf-\(scale.rawValue)", keyring: VaultKeyring(store: InMemoryVaultKeyStore()), mayCreateKeys: true)

        try Bench.time("vaultSeal/\(scale)") { _ = try sealer.seal(plaintext, file: .snapshot) }
        let sample = try sealer.seal(plaintext, file: .snapshot)
        try Bench.time("vaultOpen/\(scale)") { _ = try sealer.open(sample, file: .snapshot) }
    }

    // MARK: - SnapshotStore commit and load (temp dir)

    @Test("SnapshotStore commit and load", arguments: BenchScale.allCases)
    func snapshotStoreCommitAndLoad(_ scale: BenchScale) async throws {
        let context = try await PerfFixtures.context(for: scale)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tally-perf-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let sealer = VaultSealer(account: "perf-\(scale.rawValue)", keyring: VaultKeyring(store: InMemoryVaultKeyStore()), mayCreateKeys: true)
        let store = SnapshotStore(root: dir, accountKey: AccountKey("perf-\(scale.rawValue)"), sealer: sealer)
        try await store.prepare()

        var generation: UInt64 = 1
        try await Bench.timeAsync("snapshotStoreCommit/\(scale)") {
            try await store.commit(withGeneration(context.snapshot, generation), includeGrades: true)
            generation += 1
        }
        try await Bench.timeAsync("snapshotStoreLoad/\(scale)") {
            guard case .loaded = await store.loadSnapshot() else { throw PerfCheckError(message: "expected a committed snapshot") }
        }
    }

    private func withGeneration(_ snapshot: CanvasSnapshot, _ generation: UInt64) -> CanvasSnapshot {
        CanvasSnapshot(generation: generation, accountKey: snapshot.accountKey, host: snapshot.host, fetchedAt: snapshot.fetchedAt,
                      profile: snapshot.profile, courses: snapshot.courses, groups: snapshot.groups,
                      gradingPeriods: snapshot.gradingPeriods, planner: snapshot.planner, events: snapshot.events,
                      announcements: snapshot.announcements, courseColors: snapshot.courseColors, sections: snapshot.sections)
    }

    // MARK: - GlanceProjection build

    @Test("GlanceProjection build", arguments: BenchScale.allCases)
    func glanceProjectionBuild(_ scale: BenchScale) async throws {
        let context = try await PerfFixtures.context(for: scale)
        Bench.time("glanceProjectionBuild/\(scale)") {
            _ = GlanceProjectionBuilder.build(from: context.snapshot, includeGrades: true)
        }
    }

    // MARK: - GradeEngine over all courses

    @Test("GradeEngine over all courses", arguments: BenchScale.allCases)
    func gradeEngineAllCourses(_ scale: BenchScale) async throws {
        let context = try await PerfFixtures.context(for: scale)
        Bench.time("gradeEngineAllCourses/\(scale)") {
            for course in context.snapshot.courses {
                _ = GradeEngine.scores(course: course, groups: context.snapshot.groups[course.id] ?? [],
                                       gradingPeriods: context.snapshot.gradingPeriods[course.id] ?? [])
            }
        }
    }

    // MARK: - ChangeDigest.diff

    @Test("ChangeDigest.diff", arguments: BenchScale.allCases)
    func changeDigestDiff(_ scale: BenchScale) async throws {
        let context = try await PerfFixtures.context(for: scale)
        Bench.time("changeDigestDiff/\(scale)") {
            _ = ChangeDigest.diff(old: context.digestOld, new: context.snapshot)
        }
    }

    // MARK: - PriorityScore + AlertEngine + ReminderPlanner over all items

    @Test("PriorityScore over all items", arguments: BenchScale.allCases)
    func priorityScoreAllItems(_ scale: BenchScale) async throws {
        let context = try await PerfFixtures.context(for: scale)
        let items = openAssignments(in: context.snapshot)
        Bench.time("priorityScoreAllItems/\(scale)") {
            for (course, groups, assignment) in items {
                guard !PriorityScore.isExcluded(assignment: assignment, markedDone: false, now: PerfFixtures.anchor) else { continue }
                let hours = assignment.dueAt.map { $0.timeIntervalSince(PerfFixtures.anchor) / 3600 }
                let weight = PriorityScore.weight(assignment: assignment, course: course, groups: groups,
                                                  gradingPeriods: context.snapshot.gradingPeriods[course.id] ?? [])
                let modifiers = priorityModifiers(assignment: assignment, course: course, now: PerfFixtures.anchor)
                let score = PriorityScore.score(hoursUntilDue: hours, courseWeight: weight, modifiers: modifiers)
                _ = PriorityScore.reasonText(hoursUntilDue: hours, weight: weight, modifiers: modifiers, courseCode: course.courseCode)
                _ = PriorityScore.band(score)
            }
        }
    }

    @Test("AlertEngine over all items", arguments: BenchScale.allCases)
    func alertEngineAllItems(_ scale: BenchScale) async throws {
        let context = try await PerfFixtures.context(for: scale)
        let items = openAssignments(in: context.snapshot)
        Bench.time("alertEngineAllItems/\(scale)") {
            var loadItems: [AlertEngine.LoadItem] = []
            for (course, groups, assignment) in items {
                if let missing = AlertEngine.missingAlert(assignment: assignment, now: PerfFixtures.anchor) {
                    _ = missing
                } else if let submission = assignment.submission, !submission.isSubmitted, !submission.excused,
                          let due = assignment.dueAt, due >= PerfFixtures.anchor {
                    let weight = PriorityScore.weight(assignment: assignment, course: course, groups: groups,
                                                      gradingPeriods: context.snapshot.gradingPeriods[course.id] ?? [])
                    let hours = due.timeIntervalSince(PerfFixtures.anchor) / 3600
                    let modifiers = priorityModifiers(assignment: assignment, course: course, now: PerfFixtures.anchor)
                    let score = PriorityScore.score(hoursUntilDue: hours, courseWeight: weight, modifiers: modifiers)
                    _ = AlertEngine.dueSoonAlert(assignment: assignment, priorityScore: score, weight: weight, now: PerfFixtures.anchor)
                }
                if let due = assignment.dueAt, due >= PerfFixtures.anchor, let submission = assignment.submission,
                   !submission.isSubmitted, !submission.excused {
                    let weight = PriorityScore.weight(assignment: assignment, course: course, groups: groups,
                                                      gradingPeriods: context.snapshot.gradingPeriods[course.id] ?? [])
                    loadItems.append(AlertEngine.LoadItem(dueAt: due, weight: weight, courseID: course.id))
                }
            }
            _ = AlertEngine.overloadClusters(loadItems, now: PerfFixtures.anchor)
        }
    }

    @Test("ReminderPlanner.plan over all items", arguments: BenchScale.allCases)
    func reminderPlannerAllItems(_ scale: BenchScale) async throws {
        let context = try await PerfFixtures.context(for: scale)
        let items = openAssignments(in: context.snapshot)
        let candidates = items.map { course, groups, assignment -> ReminderCandidate in
            let hours = assignment.dueAt.map { $0.timeIntervalSince(PerfFixtures.anchor) / 3600 }
            let weight = PriorityScore.weight(assignment: assignment, course: course, groups: groups,
                                              gradingPeriods: context.snapshot.gradingPeriods[course.id] ?? [])
            let score = PriorityScore.score(hoursUntilDue: hours, courseWeight: weight,
                                            modifiers: priorityModifiers(assignment: assignment, course: course, now: PerfFixtures.anchor))
            return ReminderCandidate(assignment: assignment, isExam: false, priority: score, markedDone: false)
        }
        var refresh = RefreshRecord()
        refresh.began(.launch, at: PerfFixtures.anchor.addingTimeInterval(-3600))
        refresh.succeeded(dataFetchedAt: PerfFixtures.anchor.addingTimeInterval(-3600))
        let timeZone = TimeZone(identifier: "America/New_York") ?? .current

        Bench.time("reminderPlannerAllItems/\(scale)") {
            _ = ReminderPlanner.plan(accountKey: AccountKey("perf-\(scale.rawValue)"), candidates: candidates,
                                     settings: ReminderSettings(), now: PerfFixtures.anchor, timeZone: timeZone, refresh: refresh)
        }
    }

    // MARK: - Memory: peak RSS for decode + processing of the stress snapshot

    @Test("Memory: peak RSS, stress decode + processing")
    func stressDecodeAndProcessPeakRSS() async throws {
        let context = try await PerfFixtures.context(for: .stress)
        let encoded = try JSONEncoder().encode(context.snapshot)

        try MemoryProbe.measurePeak("stressDecodeAndProcess") {
            let decoded = try JSONDecoder().decode(CanvasSnapshot.self, from: encoded)
            for course in decoded.courses {
                _ = GradeEngine.scores(course: course, groups: decoded.groups[course.id] ?? [],
                                       gradingPeriods: decoded.gradingPeriods[course.id] ?? [])
            }
            let items = openAssignments(in: decoded)
            for (course, groups, assignment) in items {
                let hours = assignment.dueAt.map { $0.timeIntervalSince(PerfFixtures.anchor) / 3600 }
                let weight = PriorityScore.weight(assignment: assignment, course: course, groups: groups,
                                                  gradingPeriods: decoded.gradingPeriods[course.id] ?? [])
                _ = PriorityScore.score(hoursUntilDue: hours, courseWeight: weight,
                                        modifiers: priorityModifiers(assignment: assignment, course: course, now: PerfFixtures.anchor))
            }
        }
    }
}
#endif
