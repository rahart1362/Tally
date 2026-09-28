import Foundation
import Testing
import TallyDomain
import TallyTestSupport

/// PERF-05 PA-4 (docs/pmo/reviews/perf-algorithms.md): the precomputed
/// `PriorityScore.WeightContext` (PA-2) against the per-call `weight` it replaced, over every
/// assignment of every fixture persona, the synthetic stress account, and a seeded adversarial
/// corpus. Equality is exact: the same bit pattern, which is stricter than `==` on `Double`
/// (it also tells `0.0` from `-0.0`).
///
/// The fixtures alone cannot catch a summation-order bug: every `points_possible` in
/// `fixtures/canvas` and in `StressSnapshotFixture` is a small integer, and integer sums come out
/// the same in any order. The adversarial corpus therefore uses fractional points (for example
/// 0.1 + 0.2 + 0.3 != 0.3 + 0.2 + 0.1 in binary floating point), and puts due dates exactly on
/// grading-period boundary minutes; `theAdversarialCorpusCanSeeOrderAndBoundaryMistakes` asserts
/// both properties hold, so a wrong-order sum or an off-by-one period cannot pass unnoticed.
@Suite("PriorityScore.weight: precomputed context vs the original per-call derivation (PERF-05)")
struct PriorityWeightDifferentialTests {
    /// `PriorityScore.weight` exactly as it stood on `pmo/assessment` @ 1ec17ff
    /// (`Insights/PriorityScore.swift:104-157`), kept as the reference implementation. Do not
    /// tidy it: its whole value is that it is the old code, character for character.
    enum Legacy {
        static func weight(
            assignment: Assignment,
            course: Course,
            groups: [AssignmentGroup],
            gradingPeriods: [GradingPeriod] = []
        ) -> Double {
            guard let possible = assignment.pointsPossible, possible > 0 else { return 0 }
            guard assignment.published, assignment.isGradeable, !assignment.omitFromFinalGrade else { return 0 }
            guard let group = groups.first(where: { $0.id == assignment.groupID }) else { return 0 }

            func counted(_ a: Assignment) -> Bool {
                a.published && a.isGradeable && !a.omitFromFinalGrade && (a.pointsPossible ?? 0) > 0
            }

            let usesPeriods = course.hasGradingPeriods && !gradingPeriods.isEmpty
            let ownPeriod = usesPeriods ? effectivePeriod(for: assignment, in: gradingPeriods) : nil
            func inScope(_ a: Assignment) -> Bool {
                guard usesPeriods, let ownPeriod else { return true }
                return effectivePeriod(for: a, in: gradingPeriods) == ownPeriod
            }

            var w: Double
            if course.appliesGroupWeights {
                let groupPossible = group.assignments.filter { counted($0) && inScope($0) }
                    .reduce(0.0) { $0 + ($1.pointsPossible ?? 0) }
                guard groupPossible > 0 else { return 0 }
                w = (group.weight ?? 0) / 100 * possible / groupPossible
            } else {
                let coursePossible = groups.flatMap(\.assignments).filter { counted($0) && inScope($0) }
                    .reduce(0.0) { $0 + ($1.pointsPossible ?? 0) }
                guard coursePossible > 0 else { return 0 }
                w = possible / coursePossible
            }

            let rules = group.rules
            if !rules.neverDrop.contains(assignment.id) {
                let droppable = group.assignments.filter { counted($0) && !rules.neverDrop.contains($0.id) }
                let n = droppable.count
                let k = max(0, rules.dropLowest) + max(0, rules.dropHighest)
                if n > 0, k > 0 {
                    w *= (1 - min(Double(k), Double(n)) / Double(n))
                }
            }
            return max(0, w)
        }

        static func effectivePeriod(for assignment: Assignment, in periods: [GradingPeriod]) -> CanvasID<GradingPeriod>? {
            guard let due = assignment.dueAt else { return nil }
            func minute(_ d: Date) -> Double { (d.timeIntervalSince1970 / 60).rounded(.down) }
            return periods.first { minute($0.startDate) < minute(due) && minute(due) <= minute($0.endDate) }?.id
        }
    }

    // MARK: - Comparison

    struct Tally {
        var compared = 0
        var nonZero = 0
        /// Items weighed against a single grading period's sums (the scope PA-2 had to rebuild).
        var periodScoped = 0
        var dropDiscounted = 0
        var mismatches: [String] = []

        mutating func merge(_ other: Tally) {
            compared += other.compared; nonZero += other.nonZero; periodScoped += other.periodScoped
            dropDiscounted += other.dropDiscounted; mismatches += other.mismatches
        }
    }

    /// Weighs every assignment in `groups` (plus `extra`, assignments outside the groups) three
    /// ways: the legacy per-call code, the context, and the public wrapper.
    static func compare(course: Course, groups: [AssignmentGroup], periods: [GradingPeriod],
                        extra: [Assignment] = []) -> Tally {
        var tally = Tally()
        let context = PriorityScore.WeightContext(course: course, groups: groups, gradingPeriods: periods)
        let usesPeriods = course.hasGradingPeriods && !periods.isEmpty
        for assignment in groups.flatMap(\.assignments) + extra {
            let old = Legacy.weight(assignment: assignment, course: course, groups: groups, gradingPeriods: periods)
            let viaContext = context.weight(of: assignment)
            let viaWrapper = PriorityScore.weight(assignment: assignment, course: course, groups: groups, gradingPeriods: periods)
            tally.compared += 1
            if old != 0 { tally.nonZero += 1 }
            if old != 0, usesPeriods, Legacy.effectivePeriod(for: assignment, in: periods) != nil { tally.periodScoped += 1 }
            if old != 0, let group = groups.first(where: { $0.id == assignment.groupID }),
               max(0, group.rules.dropLowest) + max(0, group.rules.dropHighest) > 0,
               !group.rules.neverDrop.contains(assignment.id) {
                tally.dropDiscounted += 1
            }
            if old.bitPattern != viaContext.bitPattern || old.bitPattern != viaWrapper.bitPattern {
                tally.mismatches.append("course \(course.id) assignment \(assignment.id): legacy \(old) "
                    + "context \(viaContext) wrapper \(viaWrapper)")
            }
        }
        return tally
    }

    static func compare(snapshot: CanvasSnapshot) -> Tally {
        var tally = Tally()
        for course in snapshot.courses {
            tally.merge(compare(course: course, groups: snapshot.groups[course.id] ?? [],
                                periods: snapshot.gradingPeriods[course.id] ?? []))
        }
        return tally
    }

    private static func expectIdentical(_ tally: Tally, _ label: String) {
        print("PERF-05-DIFF | weight/\(label) | compared=\(tally.compared) nonZero=\(tally.nonZero) "
            + "periodScoped=\(tally.periodScoped) dropDiscounted=\(tally.dropDiscounted) mismatches=\(tally.mismatches.count)")
        #expect(tally.mismatches.isEmpty,
                "\(label): \(tally.mismatches.count) of \(tally.compared) weights differ; first: \(tally.mismatches.prefix(5))")
    }

    // MARK: - Fixtures and the stress account

    @Test(arguments: Fixtures.personas)
    func everyPersonaAssignmentWeighsTheSame(_ persona: String) async throws {
        let snapshot = try await PersonaSnapshotHarness.fetchSnapshot(persona: persona, now: Date(timeIntervalSince1970: 1_790_000_000))
        let tally = Self.compare(snapshot: snapshot)
        Self.expectIdentical(tally, persona)
        if persona != "empty" {
            #expect(tally.compared > 0 && tally.nonZero > 0, "\(persona): nothing was weighed")
        }
    }

    @Test func everyStressAssignmentWeighsTheSame() {
        let snapshot = StressSnapshotFixture.make(scale: .stress)
        let tally = Self.compare(snapshot: snapshot)
        Self.expectIdentical(tally, "stress")
        #expect(tally.compared == StressSnapshotFixture.Scale.stress.totalAssignments)
        #expect(tally.periodScoped > 0 && tally.dropDiscounted > 0, "stress must exercise period scopes and drop rules")
    }

    // MARK: - Seeded adversarial corpus

    /// Mostly fractional values, which make summation order visible; about 1 in 14 is one of
    /// `counted`'s edge cases instead. (Rarer than the rest on purpose: one `+infinity` in a
    /// course makes every other item's share in that scope 0, which would hide the sums.)
    private static let fractionalPoints: [Double] = [0.1, 0.2, 0.3, 0.7, 1.0 / 3.0, 2.675, 1e16, 1e-3, 1.1, 2.2, 3.3, 10, 25, 99.99]
    private static func points(_ rng: inout SeededRandom) -> Double? {
        switch Int.random(in: 0..<100, using: &rng) {
        case 0: .infinity
        case 1: .nan
        case 2, 3: nil
        case 4, 5: 0
        case 6: -5
        default: fractionalPoints.randomElement(using: &rng) ?? 1
        }
    }
    private static let groupWeightChoices: [Double?] = [nil, 0, 20, 33.3, 12.5, 40, -5, .nan]
    static let periodSpan: TimeInterval = 30 * 86_400
    static let corpusBase = Date(timeIntervalSince1970: 1_790_000_000)

    struct AdversarialCourse: Sendable {
        let course: Course
        let groups: [AssignmentGroup]
        let periods: [GradingPeriod]
        let extra: [Assignment]
    }

    static func adversarialCourse(_ index: Int, rng: inout SeededRandom) -> AdversarialCourse {
        let courseID = CanvasID<Course>("adv-\(index)")
        let course = Course(id: courseID, name: "Adversarial \(index)", courseCode: "ADV \(index)", term: nil, teachers: [],
                            timeZone: nil, appliesGroupWeights: Bool.random(using: &rng),
                            hasGradingPeriods: Int.random(in: 0..<10, using: &rng) < 7,
                            currentGradingPeriodID: nil, gradeVisibility: .visible, scores: nil, currentPeriodScores: nil,
                            htmlURL: nil)

        // Periods: adjacent, sometimes overlapping, sometimes sharing an ID with an earlier one,
        // with sub-minute jitter on the bounds so minute truncation matters.
        var periods: [GradingPeriod] = []
        for p in 0..<Int.random(in: 0...4, using: &rng) {
            let overlap = Int.random(in: 0..<5, using: &rng) == 0 ? -3 * 86_400.0 : 0
            let start = corpusBase.addingTimeInterval(Double(p) * periodSpan + overlap + Double(Int.random(in: 0..<60, using: &rng)))
            let end = start.addingTimeInterval(periodSpan + Double(Int.random(in: 0..<60, using: &rng)))
            let reuse = p > 0 && Int.random(in: 0..<6, using: &rng) == 0
            let id: CanvasID<GradingPeriod> = reuse ? periods[Int.random(in: 0..<p, using: &rng)].id : CanvasID("adv-\(index)-p\(p)")
            periods.append(GradingPeriod(id: id, title: "P\(p)", startDate: start, endDate: end, closeDate: nil,
                                         weight: nil, isClosed: false))
        }

        func dueDate(_ rng: inout SeededRandom) -> Date? {
            switch Int.random(in: 0..<20, using: &rng) {
            case 0, 1, 2: return nil
            case 3...9:
                // Exactly on, or one second/minute either side of, a period bound's minute.
                guard let period = periods.randomElement(using: &rng) else { return corpusBase }
                let bound = Bool.random(using: &rng) ? period.startDate : period.endDate
                let minuteStart = (bound.timeIntervalSince1970 / 60).rounded(.down) * 60
                let offsets: [TimeInterval] = [0, 59, -1, 60, bound.timeIntervalSince1970 - minuteStart]
                return Date(timeIntervalSince1970: minuteStart + (offsets.randomElement(using: &rng) ?? 0))
            default:
                return corpusBase.addingTimeInterval(Double.random(in: -periodSpan...(5 * periodSpan), using: &rng))
            }
        }

        var groups: [AssignmentGroup] = []
        var allIDs: [CanvasID<Assignment>] = []
        let groupCount = Int.random(in: 1...5, using: &rng)
        let groupIDs = (0..<groupCount).map { g -> CanvasID<AssignmentGroup> in
            // Occasionally a duplicate group ID: `groups.first(where:)` must pick the first.
            g > 0 && Int.random(in: 0..<8, using: &rng) == 0 ? CanvasID("adv-\(index)-g0") : CanvasID("adv-\(index)-g\(g)")
        }
        for (g, groupID) in groupIDs.enumerated() {
            var assignments: [Assignment] = []
            for a in 0..<Int.random(in: 0...12, using: &rng) {
                let reuseID = !allIDs.isEmpty && Int.random(in: 0..<15, using: &rng) == 0
                let id = reuseID ? (allIDs.randomElement(using: &rng) ?? "adv-dup") : CanvasID<Assignment>("adv-\(index)-g\(g)-a\(a)")
                allIDs.append(id)
                let ownGroup: CanvasID<AssignmentGroup> = switch Int.random(in: 0..<20, using: &rng) {
                case 0: groupIDs.randomElement(using: &rng) ?? groupID // another group's ID
                case 1: CanvasID("adv-missing-group")
                default: groupID
                }
                let types: [String] = switch Int.random(in: 0..<20, using: &rng) {
                case 0: ["not_graded"]
                case 1: ["wiki_page"]
                case 2: []
                case 3: ["none"]
                default: ["online_upload"]
                }
                assignments.append(Assignment(
                    id: id, courseID: courseID, groupID: ownGroup, name: "A\(a)", dueAt: dueDate(&rng), lockAt: nil,
                    pointsPossible: points(&rng),
                    gradingType: .points, omitFromFinalGrade: Int.random(in: 0..<10, using: &rng) == 0, htmlURL: nil,
                    submission: nil, published: Int.random(in: 0..<10, using: &rng) != 0, submissionTypes: types))
            }
            var neverDrop = assignments.filter { _ in Int.random(in: 0..<5, using: &rng) == 0 }.map(\.id)
            if Int.random(in: 0..<10, using: &rng) == 0 { neverDrop.append("adv-not-in-group") }
            let rules = DropRules(dropLowest: [-1, 0, 0, 1, 2, 5, 20].randomElement(using: &rng) ?? 0,
                                  dropHighest: [-2, 0, 0, 1, 3].randomElement(using: &rng) ?? 0,
                                  neverDrop: neverDrop)
            groups.append(AssignmentGroup(id: groupID, name: "G\(g)", position: g,
                                          weight: groupWeightChoices.randomElement(using: &rng) ?? nil,
                                          rules: rules, assignments: assignments))
        }

        // Assignments that are not in any group but name an existing group: `weight` still sums
        // that group, without them.
        let extra = (0..<Int.random(in: 0...2, using: &rng)).map { e in
            Assignment(id: CanvasID("adv-\(index)-extra-\(e)"), courseID: courseID,
                       groupID: groupIDs.randomElement(using: &rng) ?? "adv-missing-group", name: "Extra \(e)",
                       dueAt: dueDate(&rng), lockAt: nil, pointsPossible: points(&rng),
                       gradingType: .points, omitFromFinalGrade: false, htmlURL: nil, submission: nil)
        }
        return AdversarialCourse(course: course, groups: groups, periods: periods, extra: extra)
    }

    static let adversarialCourseCount = 3_000
    static let adversarialSeed: UInt64 = 0x5EED_0005

    /// Built once and shared by both tests below (it is the slow part under the sanitizers).
    static let adversarialCorpus: [AdversarialCourse] = {
        var rng = SeededRandom(seed: adversarialSeed)
        return (0..<adversarialCourseCount).map { adversarialCourse($0, rng: &rng) }
    }()

    @Test func adversarialCoursesWeighTheSame() {
        var tally = Tally()
        for c in Self.adversarialCorpus {
            tally.merge(Self.compare(course: c.course, groups: c.groups, periods: c.periods, extra: c.extra))
        }
        Self.expectIdentical(tally, "adversarial")
        // Floors at about half of what this seed produces (compared 56,548, nonZero 18,200,
        // periodScoped 4,651, dropDiscounted 8,383): a guard against a generator edit that
        // quietly stops exercising a path, not a tuned expectation.
        #expect(tally.compared > 28_000, "compared only \(tally.compared)")
        #expect(tally.nonZero > 9_000 && tally.periodScoped > 2_300 && tally.dropDiscounted > 4_000,
                "coverage: nonZero \(tally.nonZero), periodScoped \(tally.periodScoped), dropDiscounted \(tally.dropDiscounted)")
    }

    /// The corpus is only a real check on PA-2's two riskiest details if (a) some of its sums
    /// change when added in a different order and (b) some due dates sit exactly on a period's
    /// boundary minute, where `<` vs `<=` decides the period. Both are asserted here, so a
    /// future edit to the generator cannot quietly remove them.
    @Test func theAdversarialCorpusCanSeeOrderAndBoundaryMistakes() {
        func minute(_ d: Date) -> Double { (d.timeIntervalSince1970 / 60).rounded(.down) }
        var orderSensitiveCourses = 0
        var boundaryItems = 0
        for c in Self.adversarialCorpus {
            let counted = c.groups.flatMap(\.assignments).filter {
                $0.published && $0.isGradeable && !$0.omitFromFinalGrade && ($0.pointsPossible ?? 0) > 0
            }.compactMap(\.pointsPossible)
            let forward = counted.reduce(0.0, +)
            let backward = counted.reversed().reduce(0.0, +)
            if forward.bitPattern != backward.bitPattern { orderSensitiveCourses += 1 }
            let bounds = Set(c.periods.flatMap { [minute($0.startDate), minute($0.endDate)] })
            boundaryItems += c.groups.flatMap(\.assignments).filter { a in a.dueAt.map { bounds.contains(minute($0)) } ?? false }.count
        }
        print("PERF-05-DIFF | weight/adversarial corpus | orderSensitiveCourses=\(orderSensitiveCourses) boundaryItems=\(boundaryItems)")
        // This seed: 1,290 order-sensitive courses and 9,596 boundary items; floors at about half.
        #expect(orderSensitiveCourses > 600, "only \(orderSensitiveCourses) courses have order-sensitive sums")
        #expect(boundaryItems > 4_500, "only \(boundaryItems) items are due on a period-boundary minute")
    }
}
