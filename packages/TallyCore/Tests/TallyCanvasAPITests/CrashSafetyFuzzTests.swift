import Foundation
import Testing
import TallyDomain
import TallyTestSupport
@testable import TallyCanvasAPI

/// CS-03 (crash-safety.md): adversarial/fuzz coverage. Mutates real fixture JSON — dropped
/// required fields, wrong types, nulls, negative/huge `points_possible`, NaN-like strings,
/// 10k-character strings, empty arrays, duplicate IDs, extreme dates, deeply nested junk — and
/// runs it through every mapper, `LiveCanvasGateway` over `ReplayTransport`, and the domain
/// engines (`GradeEngine`/`DropRuleSelection`, `GoalSeek`, `PriorityScore`, `AlertEngine`,
/// `ReminderPlanner`, `ChangeDigest`).
///
/// Requirement (per the crash-safety charter): never crash; return an error or drop and count;
/// finish in bounded time. A mapper or engine *throwing*, or returning a degraded/empty result,
/// is success here — the only failure mode this suite checks for is the test process crashing
/// (a trap/signal, which `swift test` reports as the whole run aborting) or exceeding the time
/// budget. `SeededRandom` makes every run reproducible.
@Suite("Adversarial/fuzz: mappers, gateway and domain engines never crash (CS-03)")
struct CrashSafetyFuzzTests {
    // MARK: - JSON mutation primitives

    /// `[Any]` erases the fact every element here is an immutable value type; this array is
    /// only ever read (never mutated) after initialization, so sharing it across concurrently
    /// running `@Test` cases is safe — the same reasoning as `CanvasJSON.CanvasDate.pattern`.
    nonisolated(unsafe) private static let poisonScalars: [Any] = [
        NSNull(),
        "NaN", "Infinity", "-Infinity", "-0",
        String(repeating: "x", count: 10_000),
        "",
        1e308, -1e308, -1, 0,
        Double.infinity, -Double.infinity, Double.nan, // JSONSerialization tolerates these in a Swift `Any` tree even though real JSON text can't
        [String: Any](), [Any](),
    ]

    /// One mutation applied to a JSON object: drop a field, null it, replace with a poison
    /// scalar, empty a nested array/object, duplicate the first element of an array field, or
    /// wrap a scalar several objects deep ("deeply nested junk").
    private static func mutateOnce(_ node: Any, rng: inout SeededRandom) -> Any {
        switch node {
        case let dict as [String: Any]:
            guard !dict.isEmpty else { return node }
            var mutated = dict
            let keys = Array(dict.keys)
            let key = keys[Int(rng.next() % UInt64(keys.count))]
            switch rng.next() % 8 {
            case 0: mutated.removeValue(forKey: key) // drop a required field
            case 1: mutated[key] = NSNull() // null
            case 2: mutated[key] = poisonScalars[Int(rng.next() % UInt64(poisonScalars.count))] // wrong type / huge / NaN-like
            case 3: mutated[key] = [] as [Any] // empty array where content expected
            case 4: mutated[key] = [String: Any]() // empty object
            case 5:
                // Deeply nested junk: wrap whatever was there several objects deep.
                var wrapped: Any = mutated[key] ?? NSNull()
                for _ in 0..<6 { wrapped = ["nested": wrapped] }
                mutated[key] = wrapped
            case 6:
                if let arr = mutated[key] as? [Any], let first = arr.first { mutated[key] = arr + [first, first] } // duplicate IDs
            default:
                mutated[key] = mutateOnce(mutated[key] ?? NSNull(), rng: &rng) // recurse
            }
            return mutated
        case let arr as [Any]:
            guard !arr.isEmpty else { return node }
            switch rng.next() % 3 {
            case 0: return [] as [Any]
            case 1: return arr + [arr[0]] // duplicate an element (duplicate IDs)
            default:
                var copy = arr
                let idx = Int(rng.next() % UInt64(copy.count))
                copy[idx] = mutateOnce(copy[idx], rng: &rng)
                return copy
            }
        default:
            return node
        }
    }

    /// Applies `passes` independent single mutations to a decoded JSON tree, deterministically
    /// from `seed`.
    private static func mutate(_ root: Any, seed: UInt64, passes: Int = 3) -> Any {
        var rng = SeededRandom(seed: seed)
        var node = root
        for _ in 0..<passes { node = mutateOnce(node, rng: &rng) }
        return node
    }

    private static func copyRecursively(from source: URL, to destination: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory) else { return }
        if isDirectory.boolValue {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            for name in try FileManager.default.contentsOfDirectory(atPath: source.path) {
                try copyRecursively(from: source.appendingPathComponent(name), to: destination.appendingPathComponent(name))
            }
        } else {
            try Data(contentsOf: source).write(to: destination)
        }
    }

    private static func mutatedData(_ relativePath: String, seed: UInt64, passes: Int = 3) throws -> Data {
        let original = try JSONSerialization.jsonObject(with: Fixtures.data(relativePath))
        let mutated = mutate(original, seed: seed, passes: passes)
        // Not every mutation yields valid JSON (e.g. a Double.nan/.infinity scalar); fall back to
        // the original bytes in that case rather than skip the seed's other, valid mutations.
        guard JSONSerialization.isValidJSONObject(mutated),
              let data = try? JSONSerialization.data(withJSONObject: mutated) else {
            return try Fixtures.data(relativePath)
        }
        return data
    }

    /// Runs `body` and fails loudly if it takes longer than `seconds` — a hang is exactly as
    /// unacceptable as a crash for this charter ("finish in bounded time").
    private func withinBudget(_ label: String, seconds: Double = 45, _ body: () throws -> Void) rethrows {
        let clock = ContinuousClock()
        let elapsed = try clock.measure(body)
        #expect(elapsed < .seconds(seconds), "\(label) took \(elapsed), exceeding the \(seconds)s crash-safety budget")
    }

    // MARK: - Mappers

    @Test(arguments: Array(0..<40 as Range<UInt64>))
    func assignmentGroupMapperNeverCrashesOnMutatedFixtures(_ seed: UInt64) throws {
        try withinBudget("assignment group mapper, seed \(seed)") {
            let data = try Self.mutatedData("personas/flagship/assignment_groups/51845.json", seed: seed)
            _ = try? AssignmentGroupMapper.map(data, courseID: "51845") // throwing is fine; crashing is not
        }
    }

    @Test(arguments: Array(0..<40 as Range<UInt64>))
    func courseMapperNeverCrashesOnMutatedFixtures(_ seed: UInt64) throws {
        try withinBudget("course mapper, seed \(seed)") {
            let data = try Self.mutatedData("personas/flagship/courses.json", seed: seed)
            _ = try? CourseMapper.map(data, host: "canvas.fixtures.example")
        }
    }

    @Test(arguments: Array(0..<20 as Range<UInt64>))
    func plannerItemMapperNeverCrashesOnMutatedFixtures(_ seed: UInt64) throws {
        try withinBudget("planner mapper, seed \(seed)") {
            let data = try Self.mutatedData("personas/flagship/planner_items.page1.json", seed: seed)
            _ = try? PlannerItemMapper.map(data, host: "canvas.fixtures.example")
        }
    }

    @Test(arguments: Array(0..<20 as Range<UInt64>))
    func calendarEventMapperNeverCrashesOnMutatedFixtures(_ seed: UInt64) throws {
        try withinBudget("calendar event mapper, seed \(seed)") {
            let data = try Self.mutatedData("personas/flagship/calendar_events.chunk1.page1.json", seed: seed)
            _ = try? CalendarEventMapper.map(data)
        }
    }

    @Test(arguments: Array(0..<20 as Range<UInt64>))
    func announcementMapperNeverCrashesOnMutatedFixtures(_ seed: UInt64) throws {
        try withinBudget("announcement mapper, seed \(seed)") {
            let data = try Self.mutatedData("personas/flagship/announcements.chunk1.json", seed: seed)
            _ = try? AnnouncementMapper.map(data)
        }
    }

    @Test(arguments: Array(0..<20 as Range<UInt64>))
    func profileAndColorMappersNeverCrashOnMutatedFixtures(_ seed: UInt64) {

        withinBudget("profile/color mappers, seed \(seed)") {
            _ = try? ProfileMapper.map(Self.mutatedData("personas/flagship/profile.json", seed: seed))
            _ = try? UserColorMapper.map(Self.mutatedData("personas/flagship/colors.json", seed: seed))
        }
    }

    // MARK: - LiveCanvasGateway over ReplayTransport (the full pipeline, not just one mapper)

    @Test(arguments: Array(0..<10 as Range<UInt64>))
    func liveCanvasGatewayNeverCrashesWithMutatedCoursesOrAssignmentGroups(_ seed: UInt64) async throws {
        // Copies the flagship fixture tree to a scratch directory, replacing courses.json and
        // one assignment_groups file with mutated bytes, then replays the *whole* pipeline
        // (CanvasClient -> LiveCanvasGateway -> every mapper) over it, exactly as production does.
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("crash-safety-fuzz-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        // Only what a "flagship" replay actually reads (not the whole fixtures/canvas tree).
        // `FileManager.copyItem` intermittently fails with EINVAL on a directory under this
        // host's bind-mounted /repo (varies by which entry it reaches first); a plain
        // read-then-write recursive copy sidesteps whatever syscall that uses.
        try Self.copyRecursively(from: Fixtures.root().appendingPathComponent("manifest.json"),
                                to: scratch.appendingPathComponent("manifest.json"))
        try Self.copyRecursively(from: Fixtures.root().appendingPathComponent("errors"),
                                to: scratch.appendingPathComponent("errors"))
        try Self.copyRecursively(from: Fixtures.root().appendingPathComponent("personas/flagship"),
                                to: scratch.appendingPathComponent("personas/flagship"))

        try Self.mutatedData("personas/flagship/courses.json", seed: seed)
            .write(to: scratch.appendingPathComponent("personas/flagship/courses.json"))
        try Self.mutatedData("personas/flagship/assignment_groups/51845.json", seed: seed &+ 1)
            .write(to: scratch.appendingPathComponent("personas/flagship/assignment_groups/51845.json"))

        let routes = try CanvasManifest.personaRoutes("flagship")
        let transport = ReplayTransport(routes: routes, root: scratch)
        let credential = CanvasCredential(host: "canvas.fixtures.example", userID: "sample", accessToken: "t",
                                          refreshToken: "r", accessTokenExpiresAt: .distantFuture)
        struct NeverRefresh: TokenRefreshing {
            func refresh(_ c: CanvasCredential) async throws -> CanvasCredential { throw AuthError.reauthRequired }
        }
        let tokens = TokenCoordinator(initial: credential, store: InMemoryCredentialStore(credential),
                                      refresher: NeverRefresh(), clock: TestClock())
        let client = CanvasClient(host: "canvas.fixtures.example", transport: transport, tokens: tokens)
        let gateway = LiveCanvasGateway(host: "canvas.fixtures.example", accountKey: AccountKey("fuzz"), client: client)

        let clock = ContinuousClock()
        var caught: (any Error)?
        let elapsed = await clock.measure {
            do { _ = try await gateway.fetchSnapshot(previous: nil, now: TestClock().now()) }
            catch { caught = error } // a thrown RefreshFailure/.contract is success; a crash is not
        }
        _ = caught
        #expect(elapsed < .seconds(60), "the full gateway pipeline must finish in bounded time even on corrupt input")
    }

    // MARK: - Domain engines: pathological (non-JSON-representable) values built directly

    private static let poisonDoubles: [Double] = [.infinity, -.infinity, .nan, .greatestFiniteMagnitude, -.greatestFiniteMagnitude, 1e50, -1, 0]
    private static let poisonDates: [Date] = [
        Date(timeIntervalSince1970: .infinity), Date(timeIntervalSince1970: -.infinity),
        Date(timeIntervalSince1970: .nan), .distantPast, .distantFuture,
    ]

    @Test(arguments: Array(0..<poisonDoubles.count))
    func gradeEngineAndDropRuleSelectionNeverCrashOnPoisonValues(_ i: Int) {
        let poison = Self.poisonDoubles[i]
        let group = GradeInput.Group(id: "g1", weight: poison, rules: DropRules(dropLowest: 1, dropHighest: 1))
        let items = (0..<8).map { j -> GradeInput.Item in
            let total: Double = (j == 3) ? poison : Double(j * 10)
            let score: Double = (j == 5) ? poison : Double(j)
            return GradeInput.Item(id: CanvasID("a\(j)"), groupID: "g1", pointsPossible: total,
                                   submission: GradeInput.ScoredSubmission(score: score))
        }
        let input = GradeInput(weighting: i % 2 == 0 ? .percent : .points, groups: [group], items: items)
        let clock = ContinuousClock()
        let elapsed = clock.measure { _ = GradeEngine.scores(for: input) }
        #expect(elapsed < .seconds(45))
    }

    @Test(arguments: Array(0..<poisonDoubles.count))
    func goalSeekNeverCrashesOnPoisonValues(_ i: Int) {
        let poison = Self.poisonDoubles[i]
        let group = GradeInput.Group(id: "g1", weight: 100, rules: DropRules())
        let items = (0..<4).map { j in
            GradeInput.Item(id: CanvasID("a\(j)"), groupID: "g1", pointsPossible: 10,
                            submission: GradeInput.ScoredSubmission(score: Double(j)))
        }
        let input = GradeInput(weighting: .points, groups: [group], items: items)
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            _ = GoalSeek.solve(assignmentID: "a0", targetPercent: poison, in: input, precision: 0.01)
            _ = GoalSeek.solve(assignmentID: "a0", targetPercent: 90, in: input, precision: poison)
        }
        #expect(elapsed < .seconds(45))
    }

    @Test(arguments: Array(0..<poisonDates.count))
    func priorityScoreAlertEngineAndReminderPlannerNeverCrashOnPoisonDates(_ i: Int) {
        let poisonDate = Self.poisonDates[i]
        let course = Course(id: "c1", name: "N", courseCode: "N101", term: nil, teachers: [], timeZone: nil,
                            appliesGroupWeights: false, hasGradingPeriods: false, currentGradingPeriodID: nil,
                            gradeVisibility: .visible, scores: nil, currentPeriodScores: nil, htmlURL: nil)
        let assignment = Assignment(id: "a1", courseID: "c1", groupID: "g1", name: "A", dueAt: poisonDate, lockAt: poisonDate,
                                    pointsPossible: 10, gradingType: .points, omitFromFinalGrade: false, htmlURL: nil,
                                    submission: Submission(score: nil, grade: nil, submittedAt: nil, gradedAt: nil, postedAt: nil,
                                                           excused: false, missing: false, late: false, workflowState: "unsubmitted"))
        let now = Date(timeIntervalSince1970: 1_790_600_400)
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            _ = PriorityScore.isExcluded(assignment: assignment, markedDone: false, now: now)
            _ = PriorityScore.weight(assignment: assignment, course: course, groups: [])
            _ = AlertEngine.missingAlert(assignment: assignment, now: now)
            _ = AlertEngine.dueSoonAlert(assignment: assignment, priorityScore: 50, weight: 0.5, now: now)
            _ = ReminderPlanner.plan(accountKey: AccountKey("fuzz"),
                                     candidates: [ReminderCandidate(assignment: assignment, isExam: false, priority: 50)],
                                     settings: ReminderSettings(), now: now, timeZone: .current, refresh: RefreshRecord())
        }
        #expect(elapsed < .seconds(45))
    }

    @Test func changeDigestNeverCrashesOnPoisonCourseScores() {
        func course(_ score: Double?) -> Course {
            Course(id: "c1", name: "N", courseCode: "N101", term: nil, teachers: [], timeZone: nil,
                  appliesGroupWeights: false, hasGradingPeriods: false, currentGradingPeriodID: nil,
                  gradeVisibility: .visible,
                  scores: score.map { ComputedScores(currentScore: $0, finalScore: $0, currentGrade: nil, finalGrade: nil) },
                  currentPeriodScores: nil, htmlURL: nil)
        }
        func snapshot(_ score: Double?) -> CanvasSnapshot {
            CanvasSnapshot(generation: 1, accountKey: AccountKey("t"), host: "h", fetchedAt: Date(timeIntervalSince1970: 0),
                          profile: UserProfile(id: "1", name: "S", shortName: nil, timeZone: nil, calendarFeedURL: nil),
                          courses: [course(score)], groups: [:], gradingPeriods: [:], planner: [], events: [],
                          announcements: [], courseColors: [:], sections: [:])
        }
        for poison in Self.poisonDoubles {
            let clock = ContinuousClock()
            let elapsed = clock.measure { _ = ChangeDigest.diff(old: snapshot(50), new: snapshot(poison)) }
            #expect(elapsed < .seconds(45))
        }
    }
}
