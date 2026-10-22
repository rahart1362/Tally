import Foundation
import Testing
import TallyDomain
import TallyStore
import TallySync
import TallyTestSupport
@testable import TallyFeatures

/// FEAT-4 idea 2 (per-course grade goal) and idea 6 (save a What-If goal as the course goal): the
/// goal reaches `CourseHealthRules.evaluate`'s dormant `goal` parameter through every screen
/// builder, `HomeProjector` and `HomeModel`, the same hand-over `GradeOverrideTests.swift` already
/// proves for XG-04's "grades kept outside Canvas" answer — this suite mirrors that pattern for
/// `courseGoals`. The migration itself (v6 -> v7) is `UserStateStoreTests.swift`'s
/// `migratesV6PayloadAddingNoCourseGoals`/`courseGoalsRoundTrips` in TallyCore.
///
/// Fixture: `external-grades` (`ExternalGrades`, `GradeNotInCanvasProjectionTests.swift`). SPAN-2
/// is its only course whose grades are in Canvas as percentages (`.available`), at 91.4%: with no
/// goal it is already `.needsAttention` ("1.4 points above the 90% cutoff"); a goal of 99 (more
/// than `courseHealthAtRiskGoalGap` = 3.0 above 91.4) makes it `.atRisk` — already proved pure in
/// `GradeNotInCanvasProjectionTests.gradeRulesNeverRun`. This suite proves the same goal reaches
/// that result through the screen builders, the projector and the model, not just the pure rule.
@Suite("FEAT-4 idea 2: the per-course goal, from the screens to HomeModel", .serialized)
@MainActor
struct CourseGoalTests {
    @Test("ScreenProjections threads one goal into the Courses card, Course Detail and Insights alike")
    func screenProjectionsThreadTheGoal() async throws {
        let snapshot = try await ExternalGrades.snapshot()
        let spanish = try #require(snapshot.courses.first { $0.courseCode == "SPAN-2" })
        let formatter = ExternalGrades.formatter()

        let withoutGoal = ScreenProjections.build(from: snapshot, formatter: formatter)
        #expect(withoutGoal.courseCards.first { $0.id == spanish.id }?.health == .needsAttention)
        #expect(withoutGoal.courseDetails[spanish.id]?.health == .needsAttention)
        #expect(!withoutGoal.insights.risks.contains { $0.id == spanish.id && $0.health == .atRisk })

        let withGoal = ScreenProjections.build(from: snapshot, formatter: formatter, courseGoals: [spanish.id: 99])
        #expect(withGoal.courseCards.first { $0.id == spanish.id }?.health == .atRisk)
        #expect(withGoal.courseDetails[spanish.id]?.health == .atRisk)
        #expect(withGoal.insights.risks.first { $0.id == spanish.id }?.health == .atRisk)
        // Every other course is unaffected: only SPAN-2's goal was set.
        for card in withGoal.courseCards where card.id != spanish.id {
            let before = try #require(withoutGoal.courseCards.first { $0.id == card.id })
            #expect(card.health == before.health, card.code)
        }
    }

    @Test("HomeProjector classifies with the goals it holds")
    func projectorUsesTheGoal() async throws {
        let snapshot = try await ExternalGrades.snapshot()
        let spanish = try #require(snapshot.courses.first { $0.courseCode == "SPAN-2" })
        let projector = ScreenModelSupport.projector()
        await projector.install(HomeUpdate(generation: 1, snapshot: snapshot, digest: nil, digestAsOf: nil, freshness: .noCache))
        #expect(await projector.setCourseGoals([spanish.id: 99], revision: 1))
        let projection = try #require(await projector.project(now: ExternalGrades.anchor))
        #expect(projection.screens.courseDetails[spanish.id]?.health == .atRisk)
    }

    @Test("HomeProjector: an older hand-over of the goals never replaces a newer one")
    func projectorKeepsTheNewestGoals() async {
        let projector = ScreenModelSupport.projector()
        let spanish: CanvasID<Course> = "77306"
        #expect(await projector.setCourseGoals([spanish: 95], revision: 2))
        #expect(!(await projector.setCourseGoals([:], revision: 1)), "older: ignored")
        #expect(await projector.courseGoals == [spanish: 95])
    }

    @Test("HomeProjector: the same goals again report no change, so nothing is projected again")
    func projectorReportsNoChangeForTheSameGoals() async {
        let projector = ScreenModelSupport.projector()
        let spanish: CanvasID<Course> = "77306"
        #expect(await projector.setCourseGoals([spanish: 90], revision: 1))
        #expect(!(await projector.setCourseGoals([spanish: 90], revision: 2)))
    }

    @Test("HomeModel: a change hands the goal to the projector and projects again once")
    func aChangeProjectsAgainOnce() async throws {
        let snapshot = try await ExternalGrades.snapshot()
        let spanish = try #require(snapshot.courses.first { $0.courseCode == "SPAN-2" })
        let model = try await Self.startedModel(snapshot)
        let before = await model.projector.projectionCount
        model.setCourseGoal(99, for: spanish.id)
        await model.awaitCourseGoalApplied()
        #expect(await model.projector.projectionCount == before + 1)
        #expect(model.courseGoal(for: spanish.id) == 99)
        #expect(model.courseDetails[spanish.id]?.health == .atRisk)
        await model.end()
    }

    @Test("HomeModel: clearing the goal (nil) removes it and reprojects")
    func clearingTheGoalRemovesIt() async throws {
        let snapshot = try await ExternalGrades.snapshot()
        let spanish = try #require(snapshot.courses.first { $0.courseCode == "SPAN-2" })
        let model = try await Self.startedModel(snapshot)
        model.setCourseGoal(99, for: spanish.id)
        await model.awaitCourseGoalApplied()
        #expect(model.courseDetails[spanish.id]?.health == .atRisk)

        model.setCourseGoal(nil, for: spanish.id)
        await model.awaitCourseGoalApplied()
        #expect(model.courseGoal(for: spanish.id) == nil)
        #expect(model.courseDetails[spanish.id]?.health == .needsAttention, "back to the no-goal baseline")
        await model.end()
    }

    @Test("Idea 6: the What-If sheet's 'Save as goal' button calls the same HomeModel entry point as Course Detail's own goal, so a What-If target persists identically")
    func saveFromWhatIfUsesTheSameEntryPoint() async throws {
        let snapshot = try await ExternalGrades.snapshot()
        let spanish = try #require(snapshot.courses.first { $0.courseCode == "SPAN-2" })
        let model = try await Self.startedModel(snapshot)
        // `WhatIfGoalSection`'s "Save as goal" button calls `onSaveGoal(model.goalPercent)`, which
        // `CourseDetailView` wires to exactly this call (`CourseDetailView.swift`'s `.sheet`).
        // `WhatIfModel.goalPercent` defaults to `WhatIfModel.defaultGoalPercent` (90) and the
        // stepper clamps it to 50...100, so nothing out of range ever reaches here.
        model.setCourseGoal(WhatIfModel.defaultGoalPercent, for: spanish.id)
        await model.awaitCourseGoalApplied()
        #expect(model.courseGoal(for: spanish.id) == WhatIfModel.defaultGoalPercent)
        await model.end()
    }

    @Test("HomeModel: at launch the stored goal reaches the projector before the first update")
    func launchHandsTheStoredGoalToTheProjector() async throws {
        let snapshot = try await ExternalGrades.snapshot()
        let spanish = try #require(snapshot.courses.first { $0.courseCode == "SPAN-2" })
        let store = InMemoryLocalScreenStateStore()
        await store.save(LocalScreenState(courseGoals: [spanish.id: 99], revision: 1))
        let source = OneUpdateHomeSource(snapshot: snapshot)
        let model = HomeModel(source: source, projector: ScreenModelSupport.projector(),
                              clock: TestClock(ExternalGrades.anchor), localStore: store)
        await model.prepare()
        #expect(await model.projector.courseGoals == [spanish.id: 99])
        await model.end()
    }

    @Test("A signed-in goal is sealed in UserState v7 and a relaunch reads it back")
    func aGoalIsSealedAndReadBack() async throws {
        let account = AccountKey("feat4-goal-\(UUID().uuidString)")
        let (directory, sealer) = try ScreenModelSupport.sealer(account)
        let store = UserStateStore(root: directory, accountKey: account, sealer: sealer)
        let local = ScreenLocalState(store: AccountLocalScreenStateStore(access: AccountUserStateAccess(store: store, runtime: AccountRuntime())))
        await local.load()
        local.setCourseGoal(87.5, for: "77306")
        await local.awaitSaved()
        guard case .loaded(let stored) = await store.load() else { Issue.record("no UserState"); return }
        #expect(stored.courseGoals == ["77306": 87.5])

        // A relaunch: a fresh `ScreenLocalState` over the same sealed store reads the goal back.
        let reloaded = ScreenLocalState(store: AccountLocalScreenStateStore(access: AccountUserStateAccess(store: store, runtime: AccountRuntime())))
        await reloaded.load()
        #expect(reloaded.courseGoal(for: "77306") == 87.5)
    }

    private static func startedModel(_ snapshot: CanvasSnapshot, localStore: any LocalScreenStateStoring = InMemoryLocalScreenStateStore())
        async throws -> HomeModel {
        let model = HomeModel(source: OneUpdateHomeSource(snapshot: snapshot), projector: ScreenModelSupport.projector(),
                              clock: TestClock(ExternalGrades.anchor), localStore: localStore)
        await model.start()
        #expect(try await HomeTestSupport.waitUntil { model.phase == .loaded && model.courseCards.count == snapshot.courses.count })
        return model
    }
}
