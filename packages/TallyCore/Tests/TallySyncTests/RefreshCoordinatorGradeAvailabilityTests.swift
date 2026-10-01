import Foundation
import Testing
import TallyDomain
import TallyStore
import TallyTestSupport
@testable import TallySync

/// Plan 08 §4.3 (XG-02): at commit the coordinator builds one `GradeAvailabilityIndex`, with the
/// student's overrides (G-3), and hands it to the digest and the glance. The overrides arrive the
/// way the digest thresholds do; since XG-04 a change also rewrites the glance at once, as "Show
/// Grades in Widgets" does, and a grades opt-in rewrite uses them too.
@Suite("RefreshCoordinator: grade availability at commit, and the override input",
       .timeLimit(.minutes(TestTimeBudget.minutes(1))))
struct RefreshCoordinatorGradeAvailabilityTests {
    /// The `external-grades` persona's anchor, 2026-09-28T13:00:00Z.
    static let anchor = Date(timeIntervalSince1970: 1_790_600_400)

    /// The persona, one generation past `previous`, with SPAN-2's current score set to `spanish`.
    static func persona(_ base: CanvasSnapshot, previous: CanvasSnapshot?, spanish: Double) -> CanvasSnapshot {
        let courses = base.courses.map { course in
            guard course.courseCode == "SPAN-2" else { return course }
            return Course(id: course.id, name: course.name, courseCode: course.courseCode, term: course.term,
                          teachers: course.teachers, timeZone: course.timeZone, appliesGroupWeights: course.appliesGroupWeights,
                          hasGradingPeriods: course.hasGradingPeriods, currentGradingPeriodID: course.currentGradingPeriodID,
                          gradeVisibility: course.gradeVisibility,
                          scores: ComputedScores(currentScore: spanish, finalScore: course.scores?.finalScore,
                                                 currentGrade: course.scores?.currentGrade, finalGrade: course.scores?.finalGrade),
                          currentPeriodScores: course.currentPeriodScores, htmlURL: course.htmlURL)
        }
        return CanvasSnapshot(
            generation: (previous?.generation ?? 0) + 1, accountKey: base.accountKey, host: base.host,
            fetchedAt: base.fetchedAt, profile: base.profile, courses: courses, groups: base.groups,
            gradingPeriods: base.gradingPeriods, planner: base.planner, events: base.events,
            announcements: base.announcements, courseColors: base.courseColors, sections: base.sections)
    }

    private func glance(_ store: SnapshotStore) async -> GlanceProjection? {
        guard case .loaded(let glance) = await store.loadGlance() else { return nil }
        return glance
    }

    /// SPAN-2's current score at generations 1, 2 and 3.
    static let spanishScores: [Double] = [80, 90, 99]

    @Test func overridesApplyFromTheNextCommitToTheGlanceAndTheDigest() async throws {
        let base = try await PersonaSnapshotHarness.fetchSnapshot(persona: "external-grades", now: Self.anchor)
        let spanish = try #require(base.courses.first { $0.courseCode == "SPAN-2" })
        let gateway = ScriptedGateway { previous, _ in
            let generation = Int(previous?.generation ?? 0)
            return Self.persona(base, previous: previous, spanish: Self.spanishScores[min(generation, 2)])
        }
        let (coordinator, store) = try makeCoordinator(gateway: gateway, includeGrades: true)
        let inbox = EventInbox()
        let consumer = Task { await drain(await coordinator.events(), into: inbox) }
        defer { consumer.cancel() }

        _ = await coordinator.run(trigger: .manual)
        #expect(await glance(store)?.gradeSummary == .band(.bRange), "SPAN-2 alone, at 80")

        _ = await coordinator.run(trigger: .manual)
        #expect(await glance(store)?.gradeSummary == .band(.aRange), "SPAN-2 alone, at 90")

        #expect(await coordinator.updateGradeAvailabilityOverrides([spanish.id: .keptOutsideCanvas]))
        #expect(await coordinator.gradeAvailabilityOverrides == [spanish.id: .keptOutsideCanvas])
        let rewritten = try #require(await glance(store))
        #expect(rewritten.generation == 2, "XG-04: the committed snapshot's glance, rewritten at once")
        #expect(rewritten.gradeSummary == .notInCanvas)

        _ = await coordinator.run(trigger: .manual)
        let third = try #require(await glance(store))
        #expect(third.generation == 3)
        #expect(third.gradeSummary == .notInCanvas, "SPAN-2 is kept outside: nothing left in Canvas")
        #expect(third.courses.first { $0.id == spanish.id }?.gradeStatus == .keptOutsideCanvas)

        #expect(await eventually {
            await inbox.events.filter { if case .committed = $0 { true } else { false } }.count == 3
        })
        let digests = await inbox.events.compactMap { event -> ChangeDigest? in
            if case .committed(_, let digest) = event { return digest }
            return nil
        }
        #expect(digests.map(\.courseScoreChanges) == [
            [],
            [.init(courseID: spanish.id, previousScore: 80, newScore: 90)],
            [], // 90 -> 99, but the student said SPAN-2's grades are kept outside Canvas
        ])
    }

    /// XG-04: a change reaches the widget's file at once (the `rewriteGlance` pattern of "Show
    /// Grades in Widgets", PR #7), so the widget never disagrees with the Dashboard until the next
    /// refresh; an unchanged map writes nothing.
    @Test func anOverrideChangeRewritesTheGlanceAtOnce() async throws {
        let base = try await PersonaSnapshotHarness.fetchSnapshot(persona: "external-grades", now: Self.anchor)
        let spanish = try #require(base.courses.first { $0.courseCode == "SPAN-2" })
        let english = try #require(base.courses.first { $0.courseCode == "ENG-10" })
        let gateway = ScriptedGateway { previous, _ in Self.persona(base, previous: previous, spanish: 91) }
        let (coordinator, store) = try makeCoordinator(gateway: gateway, includeGrades: true)

        #expect(!(await coordinator.updateGradeAvailabilityOverrides([english.id: .inCanvas])),
                "nothing committed yet: stored for the first commit, nothing to rewrite")
        _ = await coordinator.run(trigger: .manual)
        let first = try #require(await glance(store))
        #expect(first.gradeSummary == .band(.aRange))
        #expect(first.courses.first { $0.id == english.id }?.gradeStatus == .notYetPosted, "the first commit used the stored No")

        #expect(await coordinator.updateGradeAvailabilityOverrides([english.id: .inCanvas, spanish.id: .keptOutsideCanvas]))
        let yes = try #require(await glance(store))
        #expect(yes.generation == first.generation)
        #expect(yes.gradeSummary == .notInCanvas)
        #expect(yes.courses.first { $0.id == spanish.id }?.gradeStatus == .keptOutsideCanvas)
        #expect(yes.courses.first { $0.id == spanish.id }?.currentGrade == nil, "no band for a course kept outside Canvas")

        #expect(!(await coordinator.updateGradeAvailabilityOverrides([english.id: .inCanvas, spanish.id: .keptOutsideCanvas])),
                "the same answers: no rewrite, no widget reload")
        #expect(await coordinator.updateGradeAvailabilityOverrides([:]), "back to Automatic")
        let automatic = try #require(await glance(store))
        #expect(automatic.gradeSummary == .band(.aRange))
        #expect(automatic.courses.first { $0.id == english.id }?.gradeStatus == .keptOutsideCanvas)
        #expect(automatic.courses.first { $0.id == spanish.id }?.gradeStatus == .averaged)
    }

    /// XG-04: the account's coordinator starts from the stored answers (`AccountSessionFactory`),
    /// and starting writes nothing: the glance on disk was written with them.
    @Test func theStoredOverridesAtInitClassifyCommitsWithoutARewrite() async throws {
        let base = try await PersonaSnapshotHarness.fetchSnapshot(persona: "external-grades", now: Self.anchor)
        let spanish = try #require(base.courses.first { $0.courseCode == "SPAN-2" })
        let first = Self.persona(base, previous: nil, spanish: 91)
        let accountKey = AccountKey("xg04-init")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tally-xg04-\(UUID().uuidString)")
        try ProtectedFile.prepareDirectory(root, excludeFromBackup: true)
        let sealer = VaultSealer(account: accountKey.rawValue, keyring: VaultKeyring(store: InMemoryVaultKeyStore()),
                                 mayCreateKeys: true)
        let store = SnapshotStore(root: root, accountKey: accountKey, sealer: sealer)
        try await store.commit(first, includeGrades: true)
        #expect(await glance(store)?.gradeSummary == .band(.aRange), "written before the student's answer was known")

        let overrides: [CanvasID<Course>: GradeAvailabilityOverride] = [spanish.id: .keptOutsideCanvas]
        let gateway = ScriptedGateway { previous, _ in Self.persona(base, previous: previous, spanish: 92) }
        let coordinator = RefreshCoordinator(gateway: gateway, store: store, clock: TestClock(), initialSnapshot: first,
                                             includeGrades: true, gradeAvailabilityOverrides: overrides)
        #expect(await coordinator.gradeAvailabilityOverrides == overrides)
        #expect(await glance(store)?.gradeSummary == .band(.aRange), "starting rewrites nothing")
        #expect(!(await coordinator.updateGradeAvailabilityOverrides(overrides)), "the same answers again: no rewrite")

        _ = await coordinator.run(trigger: .manual)
        let committed = try #require(await glance(store))
        #expect(committed.generation == 2)
        #expect(committed.gradeSummary == .notInCanvas, "the first commit classifies with the stored answers")
    }

    @Test func aGradesOptInRewriteUsesTheOverrides() async throws {
        let base = try await PersonaSnapshotHarness.fetchSnapshot(persona: "external-grades", now: Self.anchor)
        let spanish = try #require(base.courses.first { $0.courseCode == "SPAN-2" })
        let gateway = ScriptedGateway { previous, _ in Self.persona(base, previous: previous, spanish: 91) }
        let (coordinator, store) = try makeCoordinator(gateway: gateway, includeGrades: false)
        await coordinator.updateGradeAvailabilityOverrides([spanish.id: .keptOutsideCanvas])
        _ = await coordinator.run(trigger: .manual)
        #expect(await glance(store)?.gradeSummary == .notOptedIn)

        #expect(await coordinator.updateIncludeGrades(true))
        #expect(await glance(store)?.gradeSummary == .notInCanvas, "the rewrite classifies with the override")
    }

    @Test func theCommitIndexIsTheSnapshotsAtItsFetchTimeWithTheOverrides() async throws {
        let base = try await PersonaSnapshotHarness.fetchSnapshot(persona: "external-grades", now: Self.anchor)
        // The coordinator's clock reads 20 days before the fetch: then nothing in the persona is past
        // the 14-day grace window, so an index built at the clock's time would differ.
        let clock = TestClock(Self.anchor.addingTimeInterval(-20 * 24 * 3600))
        let (coordinator, _) = try makeCoordinator(gateway: ScriptedGateway(), clock: clock, includeGrades: true)
        let english = try #require(base.courses.first { $0.courseCode == "ENG-10" })
        await coordinator.updateGradeAvailabilityOverrides([english.id: .inCanvas])
        let index = await coordinator.gradeAvailability(of: base)
        #expect(index == GradeAvailabilityIndex(snapshot: base, overrides: [english.id: .inCanvas], now: base.fetchedAt))
        #expect(index != GradeAvailabilityIndex(snapshot: base, overrides: [english.id: .inCanvas], now: clock.now()))
        #expect(index.school == .mixed(outside: 2), "ENG-10 is in Canvas by the student's word; ALG2 and BIO-H are outside")
    }
}
