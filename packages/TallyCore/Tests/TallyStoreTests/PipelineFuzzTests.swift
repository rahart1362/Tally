import Foundation
import Testing
import TallyCanvasAPI
import TallyDomain
import TallyStore
import TallySync
import TallyTestSupport

/// CS-07 (crash-safety-2.md, CS7-4): the adversarial suite, extended from the mappers (CS-03) to
/// the whole post-fetch pipeline. A seeded mutator changes a real snapshot (the flagship persona,
/// fetched through the production gateway, and the stress snapshot), then every consumer runs on
/// the result: `GlanceProjectionBuilder`, `DashboardBuilder`, `ChangeDigest.diff` (mutated as the
/// older, the newer and both snapshots), `ReminderPlanner` into `NotificationReconciler` (twice),
/// `GradeEngine` through its real callers (`GradeEngine.scores(course:…)`, `WhatIfSimulator`,
/// `GoalSeek`), `AlertEngine` with `PriorityScore`, `SnapshotBudget`, `SnapshotStore` commit and
/// load, and `RefreshCoordinator` run and commit with a scripted gateway.
///
/// Mutations: repeated elements, reordering, emptied collections, dates at years 1 and 9999, and
/// extreme but finite numbers. Success means no trap and a bounded time per case. A consumer that
/// degrades its output is fine.
///
/// It lives in `TallyStoreTests`, and runs `.serialized`, on purpose. Test targets run as separate,
/// sequential processes, and this target has no wall-clock-sensitive tests. In `TallySyncTests`,
/// forty heavy cases running in parallel under ThreadSanitizer starved the refresh coordinator's
/// five-second `eventually` windows and failed a dozen of them (crash-safety-2.md, CS7-4).
// The time limit and the per-case budget scale together with TALLY_TEST_TIME_SCALE
// (TallyTestSupport/TestTimeBudget.swift): one minute and 45 s locally and on Linux CI; 4x on
// the macOS runner; 10x under the sanitizer targets.
@Suite("Pipeline fuzz: every post-fetch consumer survives mutated snapshots (CS-07)", .serialized,
       .timeLimit(.minutes(TestTimeBudget.minutes(1))))
struct PipelineFuzzTests {
    static let now = Date(timeIntervalSince1970: 1_790_600_400)
    /// Per-case budget, below the suite's one-minute limit. Generous for the sanitizer lanes, which
    /// run 5-15x slower (CS-04), and still far below a hang.
    static let budget: Duration = TestTimeBudget.seconds(45)

    // MARK: - Cases

    @Test(arguments: Array(0..<16 as Range<UInt64>))
    func flagshipMutationsNeverTrap(_ seed: UInt64) async throws {
        let original = try await Self.flagship()
        let mutated = SnapshotMutator.mutate(original, seed: seed, passes: 4)
        try await Self.withinBudget("flagship seed \(seed)") {
            try await Pipeline.run(mutated, previous: original, now: Self.now, goalSeekCourses: 1)
        }
    }

    /// The stress generator's shape (weighted groups, drop rules, grading periods, a planner year)
    /// at 3 courses x 80 assignments, so each case stays well inside the budget under sanitizers.
    @Test(arguments: Array(0..<4 as Range<UInt64>))
    func stressMutationsNeverTrap(_ seed: UInt64) async throws {
        let original = StressSnapshotFixture.make(
            scale: .init(courseCount: 3, assignmentsPerCourse: 80, plannerItemCount: 150, seed: 0xC0FF_EE00 &+ seed))
        let mutated = SnapshotMutator.mutate(original, seed: seed &* 7_919, passes: 6)
        try await Self.withinBudget("stress seed \(seed)") {
            try await Pipeline.run(mutated, previous: original, now: Self.now, goalSeekCourses: 1)
        }
    }

    /// The charter's full stress scale (20 courses x 250 assignments, a year of planner items)
    /// through the whole pipeline except `GoalSeek` (one GoalSeek is ~60 grade computations): as
    /// generated, then with a repeat, a reordering, extreme dates and extreme numbers. Nothing is
    /// emptied, so the load stays at full scale.
    @Test(arguments: [false, true])
    func fullStressScaleFinishesInBoundedTime(_ mutate: Bool) async throws {
        let original = StressSnapshotFixture.make()
        var input = original
        if mutate {
            var rng = SeededRandom(seed: 0x5EED)
            for kind in [SnapshotMutator.Kind.repeatElement, .reorder, .extremeDates, .extremeNumbers] {
                input = SnapshotMutator.apply(kind, to: input, rng: &rng)
            }
            #expect(input != original && input.courses.count >= original.courses.count)
        }
        try await Self.withinBudget("full stress, mutated: \(mutate)") {
            try await Pipeline.run(input, previous: original, now: Self.now, goalSeekCourses: 0)
        }
    }

    /// Every mutation kind alone, on the flagship, so a failure names the kind.
    @Test(arguments: SnapshotMutator.Kind.allCases)
    func eachMutationKindAloneNeverTraps(_ kind: SnapshotMutator.Kind) async throws {
        let original = try await Self.flagship()
        for seed in 0..<2 as Range<UInt64> {
            var rng = SeededRandom(seed: seed &+ 101)
            let mutated = SnapshotMutator.apply(kind, to: original, rng: &rng)
            try await Self.withinBudget("\(kind), seed \(seed)") {
                try await Pipeline.run(mutated, previous: original, now: Self.now, goalSeekCourses: 1)
            }
        }
    }

    /// Guards the fuzz itself: the seeds above must really change the snapshot, and every
    /// mutation kind must change it for some seed.
    @Test func theMutatorReallyChangesTheSnapshot() async throws {
        let original = try await Self.flagship()
        let changed = (0..<16 as Range<UInt64>).filter { SnapshotMutator.mutate(original, seed: $0, passes: 4) != original }
        #expect(changed.count >= 13, "only \(changed.count) of 16 seeds changed the flagship snapshot")
        for kind in SnapshotMutator.Kind.allCases {
            let anyChange = (0..<2 as Range<UInt64>).contains { seed in
                var rng = SeededRandom(seed: seed &+ 101)
                return SnapshotMutator.apply(kind, to: original, rng: &rng) != original
            }
            #expect(anyChange, "\(kind) never changed the flagship snapshot")
        }
    }

    // MARK: - Helpers

    static func flagship() async throws -> CanvasSnapshot {
        try await PersonaSnapshotHarness.fetchSnapshot(persona: "flagship", now: now)
    }

    static func withinBudget(_ label: String, _ body: () async throws -> Void) async throws {
        let clock = ContinuousClock()
        let start = clock.now
        try await body()
        let elapsed = clock.now - start
        #expect(elapsed < budget, "\(label) took \(elapsed), over the \(budget) crash-safety budget")
    }
}

// MARK: - The pipeline

enum Pipeline {
    /// Runs every post-fetch consumer on `snapshot`. `previous` is the snapshot before it, for the
    /// digest and the commit path. Throws only for test-infrastructure failures (a temp directory).
    static func run(_ snapshot: CanvasSnapshot, previous: CanvasSnapshot, now: Date, goalSeekCourses: Int) async throws {
        for includeGrades in [false, true] { _ = GlanceProjectionBuilder.build(from: snapshot, includeGrades: includeGrades) }

        let digest = ChangeDigest.diff(old: previous, new: snapshot)
        _ = ChangeDigest.diff(old: snapshot, new: previous)
        _ = ChangeDigest.diff(old: snapshot, new: snapshot, thresholds: DigestThresholds(global: .all))

        _ = DashboardBuilder.build(from: snapshot, digest: digest, digestAsOf: snapshot.fetchedAt, now: now)

        await reminders(snapshot, now: now)
        grades(snapshot, now: now, goalSeekCourses: goalSeekCourses)
        alerts(snapshot, now: now)
        _ = SnapshotBudget.enforce(snapshot, maxItems: 50)
        try await store(snapshot)
        try await coordinator(snapshot, previous: previous, now: now)
    }

    static func assignments(_ snapshot: CanvasSnapshot) -> [(Course, [AssignmentGroup], Assignment)] {
        snapshot.courses.flatMap { course in
            let groups = snapshot.groups[course.id] ?? []
            return groups.flatMap(\.assignments).map { (course, groups, $0) }
        }
    }

    static func reminders(_ snapshot: CanvasSnapshot, now: Date) async {
        let timeZone = snapshot.profile.timeZone.flatMap(TimeZone.init(identifier:)) ?? .gmt
        let candidates = assignments(snapshot).enumerated().map { index, item in
            ReminderCandidate(assignment: item.2, isExam: index.isMultiple(of: 5), priority: Double(index % 101),
                              markedDone: index.isMultiple(of: 11))
        }
        var record = RefreshRecord()
        record.succeeded(dataFetchedAt: snapshot.fetchedAt)
        let desired = ReminderPlanner.plan(accountKey: snapshot.accountKey, candidates: candidates,
                                           settings: ReminderSettings(), now: now, timeZone: timeZone, refresh: record)
        let platform = FakeNotificationCenter()
        let ledger = await NotificationReconciler.reconcile(desired: desired, ledger: SyncLedger(), platform: platform)
        _ = await NotificationReconciler.reconcile(desired: desired, ledger: ledger, platform: platform)
        for option in [SnoozeOption.oneHour, .tonight, .tomorrowMorning, .dayBeforeDue] {
            _ = ReminderPlanner.snoozeDate(option, now: now, dueAt: candidates.first?.assignment.dueAt, timeZone: timeZone)
        }
    }

    static func grades(_ snapshot: CanvasSnapshot, now: Date, goalSeekCourses: Int) {
        for (index, course) in snapshot.courses.enumerated() {
            let groups = snapshot.groups[course.id] ?? []
            let periods = snapshot.gradingPeriods[course.id] ?? []
            _ = GradeEngine.scores(course: course, groups: groups, gradingPeriods: periods)
            _ = GradeEngine.currentGradingPeriod(in: periods, at: now)
            let input = GradeInput(course: course, groups: groups, gradingPeriods: periods)
            guard let target = groups.flatMap(\.assignments).first(where: { ($0.pointsPossible ?? 0) > 0 }) else { continue }
            _ = WhatIfSimulator.scores(applying: [.init(assignmentID: target.id, score: target.pointsPossible ?? 0)], to: input)
            if index < goalSeekCourses {
                _ = GoalSeek.solve(assignmentID: target.id, targetPercent: 90, in: input)
            }
        }
    }

    static func alerts(_ snapshot: CanvasSnapshot, now: Date) {
        // Plan 08 XG-02: the grade alerts take the course's availability, so the classifier runs here too.
        let availability = GradeAvailabilityIndex(snapshot: snapshot, overrides: [:], now: now)
        var load: [AlertEngine.LoadItem] = []
        var schedule = snapshot.events.map { AlertEngine.ScheduleItem(id: $0.id.rawValue, start: $0.startAt, end: $0.endAt) }
        var ranked: [PriorityScore.RankedItem] = []
        for (order, course) in snapshot.courses.enumerated() {
            let groups = snapshot.groups[course.id] ?? []
            let context = PriorityScore.WeightContext(course: course, groups: groups,
                                                      gradingPeriods: snapshot.gradingPeriods[course.id] ?? [])
            let (belowGoal, nearBoundary) = PriorityScore.courseModifiers(currentScore: course.scores?.currentScore, goal: 90)
            for assignment in groups.flatMap(\.assignments) {
                let weight = context.weight(of: assignment)
                let hours = assignment.dueAt.map { $0.timeIntervalSince(now) / 3_600 }
                let modifiers = PriorityScore.Modifiers(overdueStillOpen: true, courseBelowGoal: belowGoal, nearBoundary: nearBoundary)
                let score = PriorityScore.score(hoursUntilDue: hours, courseWeight: weight, modifiers: modifiers)
                _ = PriorityScore.reasonFactors(hoursUntilDue: hours, weight: weight, modifiers: modifiers).map(PriorityScore.reasonPart)
                ranked.append(.init(assignmentID: assignment.id, score: score, dueAt: assignment.dueAt, weight: weight,
                                    courseOrder: order))
                _ = AlertEngine.missingAlert(assignment: assignment, now: now)?.dedupeKey
                _ = AlertEngine.dueSoonAlert(assignment: assignment, priorityScore: score, weight: weight, now: now)
                _ = AlertEngine.gradePostedAlert(previous: nil, current: assignment,
                                                 availability: availability[course.id] ?? .notYetPosted)?.dedupeKey
                if let due = assignment.dueAt {
                    load.append(.init(dueAt: due, weight: weight, courseID: course.id))
                    schedule.append(.init(id: assignment.id.rawValue, start: due, isExam: order.isMultiple(of: 2)))
                }
            }
            _ = AlertEngine.belowGoalAlert(courseID: course.id, currentScore: course.scores?.currentScore, goal: 90,
                                           wasActive: false, availability: availability[course.id] ?? .notYetPosted)
        }
        _ = PriorityScore.sorted(ranked)
        _ = AlertEngine.overloadClusters(load, now: now).map(\.dedupeKey)
        _ = AlertEngine.scheduleConflicts(schedule).map(\.dedupeKey)
    }

    static func store(_ snapshot: CanvasSnapshot) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tally-pipeline-fuzz-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try ProtectedFile.prepareDirectory(root, excludeFromBackup: true)
        let sealer = VaultSealer(account: snapshot.accountKey.rawValue, keyring: VaultKeyring(store: InMemoryVaultKeyStore()),
                                 mayCreateKeys: true)
        let store = SnapshotStore(root: root, accountKey: snapshot.accountKey, sealer: sealer)
        _ = try? await store.commit(snapshot, includeGrades: true) // an encoding failure is a thrown error, not a trap
        _ = await store.loadSnapshot()
        _ = await store.loadGlance()
    }

    /// Two refreshes over a fresh store, starting from `previous`: the mutated snapshot is
    /// committed and diffed against `previous`, then `previous` is committed and diffed against it.
    static func coordinator(_ snapshot: CanvasSnapshot, previous: CanvasSnapshot, now: Date) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tally-pipeline-fuzz-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try ProtectedFile.prepareDirectory(root, excludeFromBackup: true)
        let sealer = VaultSealer(account: snapshot.accountKey.rawValue, keyring: VaultKeyring(store: InMemoryVaultKeyStore()),
                                 mayCreateKeys: true)
        let coordinator = RefreshCoordinator(
            gateway: SequenceGateway([snapshot, previous]),
            store: SnapshotStore(root: root, accountKey: snapshot.accountKey, sealer: sealer), clock: TestClock(now),
            initialSnapshot: previous, liveRefreshBudget: .seconds(30), foregroundHardCeiling: .seconds(60),
            backgroundBudget: .seconds(60))
        for _ in 0..<2 { _ = await coordinator.run(trigger: .manual) }
        await coordinator.shutdown()
    }
}

/// A `CanvasGateway` that returns the given snapshots in turn, repeating the last one.
actor SequenceGateway: CanvasGateway {
    private let snapshots: [CanvasSnapshot]
    private var calls = 0

    init(_ snapshots: [CanvasSnapshot]) { self.snapshots = snapshots }

    func fetchSnapshot(previous: CanvasSnapshot?, now: Date) async throws -> CanvasSnapshot {
        defer { calls += 1 }
        return snapshots[min(calls, snapshots.count - 1)]
    }
}

// MARK: - The mutator

/// Seeded, value-level mutations of a `CanvasSnapshot`. Every mutation keeps the value well-typed:
/// it only produces what a hostile or buggy server, an overlapping page or a corrupted snapshot
/// could, never a non-finite number (those are CS-03's).
enum SnapshotMutator {
    enum Kind: String, CaseIterable, Sendable, CustomStringConvertible {
        case repeatElement, reorder, emptyCollection, extremeDates, extremeNumbers
        var description: String { rawValue }
    }

    /// Year 1 and year 9999, the ends of what `CanvasDate.parse` accepts.
    static let yearOne = Date(timeIntervalSince1970: -62_135_596_800) // 0001-01-01T00:00:00Z
    static let year9999 = Date(timeIntervalSince1970: 253_402_300_799) // 9999-12-31T23:59:59Z
    static let extremeDoubles: [Double] = [1e15, -1e15, 1e50, -1e50, 1e300, -1e300, .greatestFiniteMagnitude,
                                           -.greatestFiniteMagnitude, .leastNonzeroMagnitude, 0, -0.0, 100.000_000_1]
    static let extremeInts: [Int] = [.max, .min, .max - 1, -1, 0, 1_000_000]
    /// Assignment points and submission scores reach `DropRuleSelection`'s exact bisection. Until
    /// R-2 (resilience.md) these stayed within 1e15: one `GradeEngine.scores` call on one 50-item
    /// group took 91-106 s in debug with 1e300 and 1e-300 (crash-safety-2.md F-5). Now
    /// `GradeSanitizing` bounds them to 1e50 with a 1e-6 floor (R-2) and the bisection walks to a
    /// known root (R-2b), so they take every extreme value, including both bounds, one ulp past
    /// each, and 1e15, still past the ~1.4e14 where `GoalSeek` used to stall.
    static let gradeDoubles: [Double] = extremeDoubles + [1e9, 1e-9, 0.5, 1e50.nextUp, 1.0000000000000002e-06, 9.9999999999999995e-07]

    static func mutate(_ snapshot: CanvasSnapshot, seed: UInt64, passes: Int) -> CanvasSnapshot {
        var rng = SeededRandom(seed: seed)
        var result = snapshot
        for _ in 0..<passes {
            let kind = Kind.allCases[Int(rng.next() % UInt64(Kind.allCases.count))]
            result = apply(kind, to: result, rng: &rng)
        }
        return result
    }

    static func apply(_ kind: Kind, to snapshot: CanvasSnapshot, rng: inout SeededRandom) -> CanvasSnapshot {
        var s = Parts(snapshot)
        switch kind {
        case .repeatElement: s.repeatElement(&rng)
        case .reorder: s.reorder(&rng)
        case .emptyCollection: s.empty(&rng)
        case .extremeDates: s.extremeDates(&rng)
        case .extremeNumbers: s.extremeNumbers(&rng)
        }
        return s.snapshot(from: snapshot)
    }

    static func pick<T>(_ values: [T], _ rng: inout SeededRandom) -> T? {
        values.isEmpty ? nil : values[Int(rng.next() % UInt64(values.count))]
    }

    /// The snapshot's collections as mutable copies.
    struct Parts {
        var courses: [Course]
        var groups: [CanvasID<Course>: [AssignmentGroup]]
        var periods: [CanvasID<Course>: [GradingPeriod]]
        var planner: [PlannerItem]
        var events: [CalendarEvent]
        var announcements: [Announcement]

        init(_ s: CanvasSnapshot) {
            courses = s.courses; groups = s.groups; periods = s.gradingPeriods
            planner = s.planner; events = s.events; announcements = s.announcements
        }

        func snapshot(from s: CanvasSnapshot) -> CanvasSnapshot {
            CanvasSnapshot(generation: s.generation, accountKey: s.accountKey, host: s.host, fetchedAt: s.fetchedAt,
                           profile: s.profile, courses: courses, groups: groups, gradingPeriods: periods, planner: planner,
                           events: events, announcements: announcements, courseColors: s.courseColors, sections: s.sections)
        }

        var courseIDs: [CanvasID<Course>] { Array(Set(courses.map(\.id)).union(groups.keys)).sorted() }

        // MARK: Repeat an element (with changed content, so first-wins is exercised)

        mutating func repeatElement(_ rng: inout SeededRandom) {
            switch rng.next() % 8 {
            case 0: if let c = pick(courses, &rng) { courses.insert(c, at: Int(rng.next() % UInt64(courses.count + 1))) }
            case 1:
                if let id = pick(courseIDs, &rng), let list = groups[id], let g = pick(list, &rng) {
                    groups[id] = list + [g]
                }
            case 2: // an assignment within its group, across groups, or into another course
                guard let from = pick(courseIDs, &rng), let list = groups[from], let g = pick(list, &rng),
                      let a = pick(g.assignments, &rng), let to = pick(courseIDs, &rng),
                      let targets = groups[to], !targets.isEmpty else { return }
                let t = Int(rng.next() % UInt64(targets.count))
                var updated = targets
                updated[t] = DuplicateIDFixture.replacing(targets[t], assignments: targets[t].assignments + [a])
                groups[to] = updated
            case 3: if let id = pick(courseIDs, &rng), let list = periods[id], let p = pick(list, &rng) { periods[id] = list + [p] }
            case 4: if let p = pick(planner, &rng) { planner.insert(p, at: Int(rng.next() % UInt64(planner.count + 1))) }
            case 5: if let e = pick(events, &rng) { events.append(e) }
            case 6: if let a = pick(announcements, &rng) { announcements.append(a) }
            default: // a whole page repeated
                planner += planner.prefix(Int(rng.next() % 20))
            }
        }

        // MARK: Reorder a collection

        mutating func reorder(_ rng: inout SeededRandom) {
            switch rng.next() % 6 {
            case 0: courses.shuffle(using: &rng)
            case 1:
                if let id = pick(courseIDs, &rng), var list = groups[id] {
                    list.shuffle(using: &rng)
                    groups[id] = list.map { DuplicateIDFixture.replacing($0, assignments: $0.assignments.shuffled(using: &rng)) }
                }
            case 2: planner.shuffle(using: &rng)
            case 3: events.shuffle(using: &rng)
            case 4: announcements.shuffle(using: &rng)
            default: if let id = pick(courseIDs, &rng) { periods[id]?.shuffle(using: &rng) }
            }
        }

        // MARK: Empty a collection

        mutating func empty(_ rng: inout SeededRandom) {
            switch rng.next() % 8 {
            case 0: courses = []
            case 1: groups = [:]
            case 2: if let id = pick(courseIDs, &rng) { groups[id] = [] }
            case 3:
                if let id = pick(courseIDs, &rng), let list = groups[id] {
                    groups[id] = list.map { DuplicateIDFixture.replacing($0, assignments: []) }
                }
            case 4: planner = []
            case 5: events = []
            case 6: announcements = []
            default: periods = periods.mapValues { _ in [] }
            }
        }

        // MARK: Dates at years 1 and 9999

        mutating func extremeDates(_ rng: inout SeededRandom) {
            func date(_ rng: inout SeededRandom) -> Date { rng.next() % 2 == 0 ? yearOne : year9999 }
            switch rng.next() % 5 {
            case 0: // assignments and their submissions, in one course
                guard let id = pick(courseIDs, &rng), let list = groups[id] else { return }
                groups[id] = list.map { group in
                    DuplicateIDFixture.replacing(group, assignments: group.assignments.map { a in
                        let d = date(&rng)
                        return Assignment(id: a.id, courseID: a.courseID, groupID: a.groupID, name: a.name, dueAt: d,
                                          lockAt: rng.next() % 2 == 0 ? date(&rng) : a.lockAt,
                                          pointsPossible: a.pointsPossible, gradingType: a.gradingType,
                                          omitFromFinalGrade: a.omitFromFinalGrade, htmlURL: a.htmlURL,
                                          submission: a.submission.map { s in
                                              Submission(score: s.score, grade: s.grade, submittedAt: s.submittedAt.map { _ in d },
                                                         gradedAt: s.gradedAt.map { _ in d }, postedAt: s.postedAt.map { _ in d },
                                                         excused: s.excused, missing: s.missing, late: s.late,
                                                         workflowState: s.workflowState, id: s.id, gradingPeriodID: s.gradingPeriodID)
                                          },
                                          published: a.published, submissionTypes: a.submissionTypes)
                    })
                }
            case 1:
                guard let id = pick(courseIDs, &rng) else { return }
                periods[id] = (periods[id] ?? []).map { p in
                    let (a, b) = (date(&rng), date(&rng))
                    return GradingPeriod(id: p.id, title: p.title, startDate: min(a, b), endDate: max(a, b), closeDate: b,
                                         weight: p.weight, isClosed: p.isClosed)
                }
            case 2:
                planner = planner.map { item in
                    rng.next() % 3 == 0
                        ? PlannerItem(id: item.id, courseID: item.courseID, title: item.title, plannableType: item.plannableType,
                                      dueAt: date(&rng), pointsPossible: item.pointsPossible, submitted: item.submitted,
                                      graded: item.graded, missing: item.missing, late: item.late, excused: item.excused,
                                      markedComplete: item.markedComplete, htmlURL: item.htmlURL)
                        : item
                }
            case 3:
                events = events.map { e in
                    CalendarEvent(id: e.id, courseID: e.courseID, title: e.title, startAt: date(&rng),
                                  endAt: rng.next() % 2 == 0 ? date(&rng) : nil, allDay: e.allDay,
                                  locationName: e.locationName, htmlURL: e.htmlURL)
                }
            default:
                announcements = announcements.map { a in
                    Announcement(id: a.id, courseID: a.courseID, title: a.title, postedAt: date(&rng), isRead: a.isRead,
                                 htmlURL: a.htmlURL)
                }
            }
        }

        // MARK: Extreme but finite numbers

        mutating func extremeNumbers(_ rng: inout SeededRandom) {
            func number(_ rng: inout SeededRandom) -> Double { pick(extremeDoubles, &rng) ?? 0 }
            func gradeNumber(_ rng: inout SeededRandom) -> Double { pick(gradeDoubles, &rng) ?? 0 }
            switch rng.next() % 4 {
            case 0: // points, scores, weights and drop rules in one course
                guard let id = pick(courseIDs, &rng), let list = groups[id] else { return }
                groups[id] = list.map { g in
                    let changeRules = rng.next() % 2 == 0
                    let rules = changeRules
                        ? DropRules(dropLowest: pick(extremeInts, &rng) ?? 0, dropHighest: pick(extremeInts, &rng) ?? 0,
                                    neverDrop: g.rules.neverDrop)
                        : g.rules
                    let assignments = g.assignments.map { a -> Assignment in
                        guard rng.next() % 3 == 0 else { return a }
                        return Assignment(id: a.id, courseID: a.courseID, groupID: a.groupID, name: a.name, dueAt: a.dueAt,
                                          lockAt: a.lockAt, pointsPossible: gradeNumber(&rng), gradingType: a.gradingType,
                                          omitFromFinalGrade: a.omitFromFinalGrade, htmlURL: a.htmlURL,
                                          submission: a.submission.map { s in
                                              Submission(score: gradeNumber(&rng), grade: s.grade, submittedAt: s.submittedAt,
                                                         gradedAt: s.gradedAt, postedAt: s.postedAt, excused: s.excused,
                                                         missing: s.missing, late: s.late, workflowState: s.workflowState,
                                                         id: s.id, gradingPeriodID: s.gradingPeriodID)
                                          },
                                          published: a.published, submissionTypes: a.submissionTypes)
                    }
                    return AssignmentGroup(id: g.id, name: g.name, position: pick(extremeInts, &rng) ?? 0, weight: number(&rng),
                                           rules: rules, assignments: assignments)
                }
            case 1:
                courses = courses.map { c in
                    Course(id: c.id, name: c.name, courseCode: c.courseCode, term: c.term, teachers: c.teachers,
                           timeZone: c.timeZone, appliesGroupWeights: rng.next() % 2 == 0, hasGradingPeriods: c.hasGradingPeriods,
                           currentGradingPeriodID: c.currentGradingPeriodID, gradeVisibility: c.gradeVisibility,
                           scores: ComputedScores(currentScore: number(&rng), finalScore: number(&rng),
                                                  currentGrade: c.scores?.currentGrade, finalGrade: c.scores?.finalGrade),
                           currentPeriodScores: c.currentPeriodScores, htmlURL: c.htmlURL,
                           hasWeightedGradingPeriods: rng.next() % 2 == 0, studentEnrollmentCompleted: c.studentEnrollmentCompleted)
                }
            case 2:
                guard let id = pick(courseIDs, &rng) else { return }
                periods[id] = (periods[id] ?? []).map { p in
                    GradingPeriod(id: p.id, title: p.title, startDate: p.startDate, endDate: p.endDate, closeDate: p.closeDate,
                                  weight: number(&rng), isClosed: p.isClosed)
                }
            default:
                planner = planner.map { item in
                    PlannerItem(id: item.id, courseID: item.courseID, title: item.title, plannableType: item.plannableType,
                                dueAt: item.dueAt, pointsPossible: number(&rng), submitted: item.submitted, graded: item.graded,
                                missing: item.missing, late: item.late, excused: item.excused,
                                markedComplete: item.markedComplete, htmlURL: item.htmlURL)
                }
            }
        }
    }
}
