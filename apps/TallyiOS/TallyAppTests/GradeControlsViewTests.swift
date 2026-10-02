#if DEBUG
import Foundation
import Synchronization
import SwiftUI
import Testing
import TallyDomain
import TallyStore
import TallyStrings
import TallySync
import TallyTestSupport
import UIKit
@testable import TallyFeatures

/// DEBUG only, like every suite that uses `AccountHarness` (`AccountLifecycleTestSupport.swift`): the
/// Release test build (`make ios-perf`) has neither it nor the test hooks it stamps snapshots with
/// (PR #23's run 36922905739).
///
/// Plan 08 XG-04 (owner decision G-3): "This course's grades are kept outside Canvas: Automatic /
/// Yes / No" in Course Detail's menu. The answer is stored in `UserState` v5 and reaches every
/// consumer alike: the screens (`HomeProjector`), the glance and the digest (`RefreshCoordinator`,
/// the glance rewritten at once) and the reminders' priority (`ReminderSubjects`). Synthetic
/// `external-grades` and `flagship` personas only.
@Suite("XG-04: the per-course answer, from the menu to every consumer", .serialized)
@MainActor
struct GradeOverrideTests {
    private final class Reloads: Sendable {
        private let count = Mutex(0)
        func record() { count.withLock { $0 += 1 } }
        var value: Int { count.withLock { $0 } }
    }

    static func startedModel(_ snapshot: CanvasSnapshot, localStore: any LocalScreenStateStoring = InMemoryLocalScreenStateStore())
        async throws -> HomeModel {
        let model = HomeModel(source: OneUpdateHomeSource(snapshot: snapshot), projector: ScreenModelSupport.projector(),
                              clock: TestClock(ExternalGrades.anchor), localStore: localStore)
        await model.start()
        #expect(try await HomeTestSupport.waitUntil { model.phase == .loaded && model.courseCards.count == snapshot.courses.count })
        return model
    }

    @Test("The menu's three answers and the override each stores; its words")
    func choices() {
        #expect(GradeOverrideChoice.allCases == [.automatic, .yes, .no])
        for choice in GradeOverrideChoice.allCases {
            #expect(GradeOverrideChoice(choice.override) == choice)
        }
        #expect(GradeOverrideChoice.automatic.override == nil)
        #expect(GradeOverrideChoice.yes.override == .keptOutsideCanvas)
        #expect(GradeOverrideChoice.no.override == .inCanvas)
        #expect(GradeOverrideChoice.allCases.map { String(localized: $0.title) } == ["Automatic", "Yes", "No"])
        #expect(String(localized: L10n.GradeOverride.title()) == "This course's grades are kept outside Canvas")
        #expect(String(localized: L10n.GradeOverride.menu()) == "Course Options")
    }

    @Test("Menu state: an answer shows at once, every screen is projected with it, and Automatic undoes it")
    func menuStateReachesEveryScreen() async throws {
        let snapshot = try await ExternalGrades.snapshot()
        let spanish = try #require(snapshot.courses.first { $0.courseCode == "SPAN-2" })
        let english = try #require(snapshot.courses.first { $0.courseCode == "ENG-10" })
        let model = try await Self.startedModel(snapshot)
        let automatic = try #require(model.courseDetails[spanish.id])
        #expect(GradeOverrideChoice(model.gradeAvailabilityOverride(for: spanish.id)) == .automatic)
        #expect(automatic.grade.notInCanvas == nil && automatic.whatIf?.estimate == nil)
        #expect(model.dashboard.hero.averagedCount == 1)

        model.setGradeAvailabilityOverride(GradeOverrideChoice.yes.override, for: spanish.id)
        #expect(GradeOverrideChoice(model.gradeAvailabilityOverride(for: spanish.id)) == .yes, "the menu shows it at once")
        #expect(model.local.gradeAvailabilityOverrides == [spanish.id: .keptOutsideCanvas])
        await model.awaitGradeAvailabilityOverrideApplied()
        let yes = try #require(model.courseDetails[spanish.id])
        #expect(yes.grade.notInCanvas == .keptOutside(.school), "with SPAN-2 out, no course is graded in Canvas")
        #expect(yes.whatIf?.estimate != nil, "XG-06: the estimate")
        #expect(model.courseCards.first { $0.id == spanish.id }?.percentText == nil)
        let row = try #require(model.courses.first { $0.id == spanish.id })
        #expect(!row.gradeAvailability.isInCanvas && row.percent == nil && row.letterGrade == nil)
        #expect(model.dashboard.hero.averagedCount == 0 && model.dashboard.hero.school == .noneInCanvas)
        // The screens equal those built with the same answers, as the coordinator's index has them.
        let index = GradeAvailabilityIndex(snapshot: snapshot, overrides: [spanish.id: .keptOutsideCanvas], now: ExternalGrades.anchor)
        let expected = ScreenProjections.build(from: snapshot, formatter: ScreenFormatter(
            now: ExternalGrades.anchor, calendar: Self.chicago, locale: Locale(identifier: "en_US")), gradeAvailability: index)
        #expect(model.courseDetails == expected.courseDetails)

        model.setGradeAvailabilityOverride(GradeOverrideChoice.no.override, for: english.id)
        await model.awaitGradeAvailabilityOverrideApplied()
        #expect(GradeOverrideChoice(model.gradeAvailabilityOverride(for: english.id)) == .no)
        let no = try #require(model.courseDetails[english.id])
        #expect(no.grade.notInCanvas == nil, "No: ENG-10 is treated as graded in Canvas (no grade posted yet)")
        #expect(no.whatIf?.estimate == nil)

        model.setGradeAvailabilityOverride(GradeOverrideChoice.automatic.override, for: spanish.id)
        model.setGradeAvailabilityOverride(GradeOverrideChoice.automatic.override, for: english.id)
        await model.awaitGradeAvailabilityOverrideApplied()
        #expect(model.local.gradeAvailabilityOverrides.isEmpty)
        #expect(model.courseDetails[spanish.id] == automatic)
        #expect(model.courseDetails[english.id]?.grade.notInCanvas == .keptOutside(.course))
        await model.end()
    }

    @Test("The stored answers shape the first projection (the launch), before any change")
    func storedAnswersShapeTheFirstProjection() async throws {
        let snapshot = try await ExternalGrades.snapshot()
        let spanish = try #require(snapshot.courses.first { $0.courseCode == "SPAN-2" })
        let store = InMemoryLocalScreenStateStore()
        await store.save(LocalScreenState(gradeAvailabilityOverrides: [spanish.id: .keptOutsideCanvas], revision: 1))
        let model = try await Self.startedModel(snapshot, localStore: store)
        #expect(GradeOverrideChoice(model.gradeAvailabilityOverride(for: spanish.id)) == .yes)
        #expect(model.courseDetails[spanish.id]?.grade.notInCanvas == .keptOutside(.school))
        #expect(model.dashboard.hero.averagedCount == 0)
        await model.end()
    }

    static var chicago: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago") ?? .gmt
        return calendar
    }

    // MARK: One guard per test (a CI mutation run reports one failure per test)

    @Test("HomeProjector classifies with the answers it holds")
    func projectorUsesTheAnswers() async throws {
        let snapshot = try await ExternalGrades.snapshot()
        let spanish = try #require(snapshot.courses.first { $0.courseCode == "SPAN-2" })
        let projector = ScreenModelSupport.projector()
        await projector.install(HomeUpdate(generation: 1, snapshot: snapshot, digest: nil, digestAsOf: nil, freshness: .noCache))
        #expect(await projector.setGradeAvailabilityOverrides([spanish.id: .keptOutsideCanvas], revision: 1))
        let projection = try #require(await projector.project(now: ExternalGrades.anchor))
        let row = try #require(projection.courses.first { $0.id == spanish.id })
        #expect(!row.gradeAvailability.isInCanvas && row.percent == nil)
        #expect(projection.screens.courseDetails[spanish.id]?.grade.notInCanvas == .keptOutside(.school))
        #expect(projection.dashboard.hero.averagedCount == 0)
    }

    @Test("HomeProjector: an older hand-over of the answers never replaces a newer one")
    func projectorKeepsTheNewestAnswers() async {
        let projector = ScreenModelSupport.projector()
        let spanish: CanvasID<Course> = "77306"
        #expect(await projector.setGradeAvailabilityOverrides([spanish: .keptOutsideCanvas], revision: 2))
        #expect(!(await projector.setGradeAvailabilityOverrides([:], revision: 1)), "older: ignored")
        #expect(await projector.gradeAvailabilityOverrides == [spanish: .keptOutsideCanvas])
    }

    @Test("HomeProjector: the same answers again report no change, so nothing is projected again")
    func projectorReportsNoChangeForTheSameAnswers() async {
        let projector = ScreenModelSupport.projector()
        let spanish: CanvasID<Course> = "77306"
        #expect(await projector.setGradeAvailabilityOverrides([spanish: .inCanvas], revision: 1))
        #expect(!(await projector.setGradeAvailabilityOverrides([spanish: .inCanvas], revision: 2)))
    }

    @Test("HomeModel: a change hands the answers to the projector and projects again once")
    func aChangeProjectsAgainOnce() async throws {
        let snapshot = try await ExternalGrades.snapshot()
        let spanish = try #require(snapshot.courses.first { $0.courseCode == "SPAN-2" })
        let model = try await Self.startedModel(snapshot)
        let before = await model.projector.projectionCount
        model.setGradeAvailabilityOverride(.keptOutsideCanvas, for: spanish.id)
        await model.awaitGradeAvailabilityOverrideApplied()
        #expect(await model.projector.projectionCount == before + 1)
        #expect(await model.projector.gradeAvailabilityOverrides == [spanish.id: .keptOutsideCanvas])
        await model.end()
    }

    /// Counts saves (the same answer twice must not save twice).
    private actor CountingLocalStore: LocalScreenStateStoring {
        private let inner = InMemoryLocalScreenStateStore()
        private(set) var saves = 0
        func load() async -> LocalScreenState { await inner.load() }
        func save(_ state: LocalScreenState) async {
            saves += 1
            await inner.save(state)
        }
    }

    @Test("HomeModel: the same answer again saves nothing")
    func theSameAnswerSavesNothing() async throws {
        let snapshot = try await ExternalGrades.snapshot()
        let spanish = try #require(snapshot.courses.first { $0.courseCode == "SPAN-2" })
        let store = CountingLocalStore()
        let model = try await Self.startedModel(snapshot, localStore: store)
        model.setGradeAvailabilityOverride(.keptOutsideCanvas, for: spanish.id)
        await model.local.awaitSaved()
        #expect(await store.saves == 1)
        model.setGradeAvailabilityOverride(.keptOutsideCanvas, for: spanish.id)
        await model.local.awaitSaved()
        #expect(await store.saves == 1, "the same answer: no second save")
        await model.end()
    }

    @Test("HomeModel: at launch the stored answers reach the projector before the first update")
    func launchHandsTheStoredAnswersToTheProjector() async throws {
        let snapshot = try await ExternalGrades.snapshot()
        let spanish = try #require(snapshot.courses.first { $0.courseCode == "SPAN-2" })
        let store = InMemoryLocalScreenStateStore()
        await store.save(LocalScreenState(gradeAvailabilityOverrides: [spanish.id: .keptOutsideCanvas], revision: 1))
        let model = HomeModel(source: OneUpdateHomeSource(snapshot: snapshot), projector: ScreenModelSupport.projector(),
                              clock: TestClock(ExternalGrades.anchor), localStore: store)
        await model.prepare()
        #expect(await model.projector.gradeAvailabilityOverrides == [spanish.id: .keptOutsideCanvas])
        await model.end()
    }

    /// An account's sealed `UserState` and a coordinator that committed the persona, opted in to
    /// grades in widgets.
    private static func signedIn() async throws
        -> (snapshot: CanvasSnapshot, userState: UserStateStore, glance: SnapshotStore, runtime: AccountRuntime) {
        let snapshot = try await ExternalGrades.snapshot()
        let account = AccountKey("xg04-\(UUID().uuidString)")
        let (directory, sealer) = try ScreenModelSupport.sealer(account)
        let userStateStore = UserStateStore(root: directory, accountKey: account, sealer: sealer)
        try await userStateStore.save(UserState(showGradesInGlance: true))
        let snapshotStore = SnapshotStore(root: directory, accountKey: account, sealer: sealer)
        let coordinator = RefreshCoordinator(gateway: ServingGateway(snapshot), store: snapshotStore,
                                             clock: SystemDateProvider(), initialSnapshot: nil, includeGrades: true)
        let runtime = AccountRuntime()
        await runtime.install(coordinator)
        _ = await coordinator.run(trigger: .manual)
        return (snapshot, userStateStore, snapshotStore, runtime)
    }

    @Test("A signed-in save hands the answers to the coordinator: the glance is rewritten at once", .timeLimit(.minutes(2)))
    func aSavedAnswerRewritesTheGlance() async throws {
        let account = try await Self.signedIn()
        let spanish = try #require(account.snapshot.courses.first { $0.courseCode == "SPAN-2" })
        let access = AccountUserStateAccess(store: account.userState, runtime: account.runtime)
        try await access.update { $0.gradeAvailabilityOverrides = [spanish.id: .keptOutsideCanvas] }
        guard case .loaded(let glance) = await account.glance.loadGlance() else { Issue.record("no glance"); return }
        #expect(glance.gradeSummary == .notInCanvas)
        #expect(glance.courses.first { $0.id == spanish.id }?.gradeStatus == .keptOutsideCanvas)
    }

    @Test("The widget is reloaded exactly when an answer rewrote the glance", .timeLimit(.minutes(2)))
    func theWidgetReloadsWhenTheGlanceWasRewritten() async throws {
        let account = try await Self.signedIn()
        let spanish = try #require(account.snapshot.courses.first { $0.courseCode == "SPAN-2" })
        let reloads = Reloads()
        let access = AccountUserStateAccess(store: account.userState, runtime: account.runtime, reloadWidgets: { reloads.record() })
        try await access.update { $0.gradeAvailabilityOverrides = [spanish.id: .keptOutsideCanvas] }
        guard case .loaded(let glance) = await account.glance.loadGlance() else { Issue.record("no glance"); return }
        let rewritten = glance.gradeSummary == .notInCanvas
        #expect(reloads.value == (rewritten ? 1 : 0), "rewritten: \(rewritten), reloads: \(reloads.value)")
    }

    @Test("A signed-in answer is sealed in UserState v5")
    func anAnswerIsSealed() async throws {
        let account = AccountKey("xg04-seal-\(UUID().uuidString)")
        let (directory, sealer) = try ScreenModelSupport.sealer(account)
        let store = UserStateStore(root: directory, accountKey: account, sealer: sealer)
        let local = ScreenLocalState(store: AccountLocalScreenStateStore(access: AccountUserStateAccess(store: store, runtime: AccountRuntime())))
        await local.load()
        local.setGradeAvailabilityOverride(.inCanvas, for: "77301")
        await local.awaitSaved()
        guard case .loaded(let stored) = await store.load() else { Issue.record("no UserState"); return }
        #expect(stored.gradesOutsideCanvasOverride == ["77301": "inCanvas"])
    }

    @Test("A relaunch reads the sealed answers back")
    func aRelaunchReadsTheAnswers() async throws {
        let account = AccountKey("xg04-read-\(UUID().uuidString)")
        let (directory, sealer) = try ScreenModelSupport.sealer(account)
        let store = UserStateStore(root: directory, accountKey: account, sealer: sealer)
        try await store.save(UserState(gradeAvailabilityOverrides: ["77301": .inCanvas, "77306": .keptOutsideCanvas]))
        let local = ScreenLocalState(store: AccountLocalScreenStateStore(access: AccountUserStateAccess(store: store, runtime: AccountRuntime())))
        await local.load()
        #expect(local.gradeAvailabilityOverrides == ["77301": .inCanvas, "77306": .keptOutsideCanvas])
    }

    @Test("Reminders: the course modifiers follow the Dashboard's rule (a score only for .available)")
    func reminderModifierRule() async throws {
        let snapshot = try await ExternalGrades.snapshot()
        let spanish = try #require(snapshot.courses.first { $0.courseCode == "SPAN-2" })
        let assignment = try #require(snapshot.groups[spanish.id]?.first?.assignments.first)
        for state in [GradeAvailability.available, .lettersOnly, .hiddenByInstructor, .notYetPosted, .notGradedInCanvas,
                      .keptOutsideCanvas(.init(pastDueItems: 5, submittedOrOfflineItems: 5)), nil] {
            let modifiers = ReminderSubjects.modifiers(assignment: assignment, course: spanish, availability: state,
                                                       now: ExternalGrades.anchor)
            #expect(modifiers.nearBoundary == (state == .available), "\(String(describing: state))")
        }
    }

    @Test("Reminders: every candidate's priority uses the course's availability with the student's answers")
    func reminderPrioritiesUseTheAnswers() async throws {
        let snapshot = try await ExternalGrades.snapshot()
        let spanish = try #require(snapshot.courses.first { $0.courseCode == "SPAN-2" })
        let answers: [CanvasID<Course>: GradeAvailabilityOverride] = [spanish.id: .keptOutsideCanvas]
        let now = ExternalGrades.anchor
        let index = GradeAvailabilityIndex(snapshot: snapshot, overrides: answers, now: now)
        var firstCourse: [CanvasID<Assignment>: Course] = [:]
        for course in snapshot.courses {
            for assignment in (snapshot.groups[course.id] ?? []).flatMap(\.assignments) where firstCourse[assignment.id] == nil {
                firstCourse[assignment.id] = course
            }
        }
        let courseOf = firstCourse
        let candidates = ReminderSubjects(snapshot: snapshot, now: now, gradeAvailabilityOverrides: answers).candidates
        #expect(candidates.contains { courseOf[$0.assignment.id]?.id == spanish.id })
        for candidate in candidates {
            let course = try #require(courseOf[candidate.assignment.id])
            let due = try #require(candidate.assignment.dueAt)
            let weights = PriorityScore.WeightContext(course: course, groups: snapshot.groups[course.id] ?? [],
                                                      gradingPeriods: snapshot.gradingPeriods[course.id] ?? [])
            let expected = PriorityScore.score(
                hoursUntilDue: due.timeIntervalSince(now) / 3600, courseWeight: weights.weight(of: candidate.assignment),
                modifiers: ReminderSubjects.modifiers(assignment: candidate.assignment, course: course,
                                                      availability: index[course.id], now: now))
            #expect(candidate.priority == expected, "\(candidate.assignment.name)")
        }
    }

    // MARK: End to end

    @Test("Signed in: the answer is sealed in UserState v5, rewrites the glance at once and reloads the widget once",
          .timeLimit(.minutes(2)))
    func signedInAnswerReachesTheGlance() async throws {
        let snapshot = try await ExternalGrades.snapshot()
        let spanish = try #require(snapshot.courses.first { $0.courseCode == "SPAN-2" })
        let account = AccountKey("xg04-\(UUID().uuidString)")
        let (directory, sealer) = try ScreenModelSupport.sealer(account)
        let userStateStore = UserStateStore(root: directory, accountKey: account, sealer: sealer)
        // The student opted in to grades in widgets (a save of the defaults would turn them off:
        // quick run 36889880651 saw that rewrite, not this one).
        try await userStateStore.save(UserState(showGradesInGlance: true))
        let snapshotStore = SnapshotStore(root: directory, accountKey: account, sealer: sealer)
        let coordinator = RefreshCoordinator(gateway: ServingGateway(snapshot), store: snapshotStore,
                                             clock: SystemDateProvider(), initialSnapshot: nil, includeGrades: true)
        let runtime = AccountRuntime()
        await runtime.install(coordinator)
        _ = await coordinator.run(trigger: .manual)
        guard case .loaded(let before) = await snapshotStore.loadGlance() else { Issue.record("no glance"); return }
        #expect(before.gradeSummary == .band(.aRange) && before.courses.first { $0.id == spanish.id }?.gradeStatus == .averaged)

        let reloads = Reloads()
        let access = AccountUserStateAccess(store: userStateStore, runtime: runtime, reloadWidgets: { reloads.record() })
        let local = ScreenLocalState(store: AccountLocalScreenStateStore(access: access))
        await local.load()
        local.setGradeAvailabilityOverride(.keptOutsideCanvas, for: spanish.id)
        await local.awaitSaved()

        guard case .loaded(let after) = await snapshotStore.loadGlance() else { Issue.record("no glance"); return }
        #expect(after.generation == before.generation, "rewritten at once, before any refresh")
        #expect(after.gradeSummary == .notInCanvas)
        #expect(after.courses.first { $0.id == spanish.id }?.gradeStatus == .keptOutsideCanvas)
        #expect(reloads.value == 1)
        #expect(await coordinator.includeGrades, "still opted in: the rewrite is the answer's")
        guard case .loaded(let stored) = await userStateStore.load() else { Issue.record("no UserState"); return }
        #expect(stored.schemaVersion == 5 && stored.gradesOutsideCanvasOverride == [spanish.id: "keptOutsideCanvas"])
        #expect(stored.showGradesInGlance)

        local.setCourseOrder([spanish.id]) // another change: the glance is already right
        await local.awaitSaved()
        #expect(reloads.value == 1, "a save that leaves the answers alone reloads nothing")

        // A relaunch reads the answer back.
        let relaunched = ScreenLocalState(store: AccountLocalScreenStateStore(access: access))
        await relaunched.load()
        #expect(relaunched.gradeAvailabilityOverrides == [spanish.id: .keptOutsideCanvas])
    }

    @Test("A new session's coordinator starts from the stored answers (AccountSessionFactory): its first commit uses them",
          .timeLimit(.minutes(2)))
    func sessionStartsFromStoredAnswers() async throws {
        let previous = try await PersonaSnapshotHarness.fetchSnapshot(persona: "flagship-previous", now: ScreenFixtures.anchor)
        let current = try await PersonaSnapshotHarness.fetchSnapshot(persona: "flagship", now: ScreenFixtures.anchor)
        let math: CanvasID<Course> = "51842"

        /// The glance after the first commit of the coordinator `AccountSessionFactory` builds over
        /// a store holding `previous` and the stored `UserState`.
        func firstCommitGlance(stored: UserState) async throws -> GlanceProjection? {
            let harness = try AccountHarness(gateway: { account in
                ServingGateway(current.restamped(accountKey: account.accountKey, generation: 2))
            })
            let account = harness.account
            let snapshots = harness.environment.snapshotStore(for: account, root: harness.root)
            _ = try await snapshots.commit(previous.restamped(accountKey: account, generation: 1), includeGrades: true)
            try await UserStateStore(root: harness.root, accountKey: account, sealer: harness.environment.sealer(for: account))
                .save(stored)
            let coordinator = await AccountSessionFactory.coordinator(for: harness.record, root: harness.root,
                                                                      environment: harness.environment)
            _ = await coordinator.run(trigger: .manual)
            guard case .loaded(let glance) = await snapshots.loadGlance() else { return nil }
            return glance
        }

        let automatic = try #require(try await firstCommitGlance(stored: UserState(showGradesInGlance: true)))
        #expect(automatic.generation == 2 && automatic.courses.first { $0.id == math }?.gradeStatus == .averaged)
        let yes = try #require(try await firstCommitGlance(
            stored: UserState(showGradesInGlance: true, gradeAvailabilityOverrides: [math: .keptOutsideCanvas])))
        #expect(yes.generation == 2)
        #expect(yes.courses.first { $0.id == math }?.gradeStatus == .keptOutsideCanvas, "the stored Yes never reached the coordinator")
        #expect(yes.courses.first { $0.id == math }?.currentGrade == nil)
    }

    @Test("Reminders: a course kept outside Canvas adds no grade modifier to the priority; the flagship's are unchanged")
    func reminderPriorities() async throws {
        let snapshot = try await ExternalGrades.snapshot()
        let spanish = try #require(snapshot.courses.first { $0.courseCode == "SPAN-2" })
        let spanishWork = Set((snapshot.groups[spanish.id] ?? []).flatMap(\.assignments).map(\.id))
        // SPAN-2's 91.39% is near the 90% boundary, which raises its items' priority (§5.1). (Bound
        // first: Xcode 26.6's #expect expansion rejects an optional chain inside a call's argument
        // followed by a member of its non-optional result, CI run 36884815682.)
        let spanishModifiers = PriorityScore.courseModifiers(currentScore: spanish.scores?.currentScore, goal: nil)
        #expect(spanishModifiers.nearBoundary)
        let automatic = ReminderSubjects(snapshot: snapshot, now: ExternalGrades.anchor)
        let overridden = ReminderSubjects(snapshot: snapshot, now: ExternalGrades.anchor,
                                          gradeAvailabilityOverrides: [spanish.id: .keptOutsideCanvas])
        let before = automatic.candidates.filter { spanishWork.contains($0.assignment.id) }
        let after = overridden.candidates.filter { spanishWork.contains($0.assignment.id) }
        #expect(!before.isEmpty && before.map(\.assignment.id) == after.map(\.assignment.id))
        // No near-boundary bonus once kept outside Canvas. An overdue item's priority is already at
        // the 100 cap with or without it (Prueba 3, quick run 36889880651), so: never higher, and
        // lower for every item below the cap.
        for (old, new) in zip(before, after) {
            #expect(new.priority <= old.priority, "\(new.assignment.name)")
        }
        let belowCap = zip(before, after).filter { $0.0.priority < 100 }
        #expect(!belowCap.isEmpty, "the persona has SPAN-2 work below the cap")
        for (old, new) in belowCap {
            #expect(new.priority < old.priority, "\(new.assignment.name): no near-boundary bonus once kept outside Canvas")
        }
        let others = automatic.candidates.filter { !spanishWork.contains($0.assignment.id) }
        #expect(others == overridden.candidates.filter { !spanishWork.contains($0.assignment.id) })

        // The Dashboard's rule (`DashboardBuilder.modifierScore`), for every course and state.
        let assignment = try #require(snapshot.groups[spanish.id]?.first?.assignments.first)
        for state in [GradeAvailability.available, .lettersOnly, .hiddenByInstructor, .notYetPosted, .notGradedInCanvas,
                      .keptOutsideCanvas(.init(pastDueItems: 5, submittedOrOfflineItems: 5)), nil] {
            let modifiers = ReminderSubjects.modifiers(assignment: assignment, course: spanish, availability: state,
                                                       now: ExternalGrades.anchor)
            let expected = PriorityScore.courseModifiers(
                currentScore: TallyDomain.DashboardBuilder.modifierScore(of: spanish, availability: state), goal: nil)
            #expect(modifiers.nearBoundary == expected.nearBoundary && modifiers.courseBelowGoal == expected.belowGoal,
                    "\(String(describing: state))")
            #expect(modifiers.nearBoundary == (state == .available))
        }

        // The flagship: every course is in Canvas, so the reminders see each course's score as before.
        let flagship = try await PersonaSnapshotHarness.fetchSnapshot(persona: "flagship", now: ExternalGrades.anchor)
        let index = GradeAvailabilityIndex(snapshot: flagship, overrides: [:], now: ExternalGrades.anchor)
        for course in flagship.courses {
            #expect(TallyDomain.DashboardBuilder.modifierScore(of: course, availability: index[course.id]) == course.scores?.currentScore,
                    "\(course.courseCode)")
        }
    }
}

/// XG-06 in the sheet: the approved disclaimer only for a course whose grades are kept outside
/// Canvas, and labelled weight fields of at least 44 pt. No UI test (owner guidance).
@Suite("XG-06: the what-if sheet's disclaimer and weight fields", .serialized)
@MainActor
struct OutsideCanvasWhatIfViewTests {
    static let disclaimer = "Estimate only. Your school keeps grades outside Canvas, so Tally uses this course's Canvas categories, "
        + "which may not match how your school weighs your grade."

    @Test("The disclaimer is the owner's approved words, and the sheet's other new words")
    func copy() {
        #expect(String(localized: L10n.WhatIfEstimate.disclaimer()) == Self.disclaimer)
        #expect(String(localized: L10n.WhatIfEstimate.weightLabel("Homework")) == "Weight for Homework, percent of grade")
        #expect(String(localized: L10n.WhatIfEstimate.total("100%")) == "Total: 100%")
        #expect(WhatIfCopy.weightTotal(100, locale: Locale(identifier: "en_US")) == "100%")
        #expect(WhatIfCopy.weightTotal(75.555_5, locale: Locale(identifier: "en_US")) == "75.56%")
        #expect(WhatIfCopy.noGradeDash == "\u{2014}")
        #expect(WhatIfCopy.noGradeSpoken == "No estimate yet. Enter a score to see one.")
    }

    @Test("A11Y-04: the weight field's tap target is at least 46 pt (44 pt in the sheet drawn at 0.960)",
          arguments: [DynamicTypeSize.xSmall, .large, .accessibility5])
    func weightFieldTarget(size: DynamicTypeSize) {
        let category = WhatIfWeightCategory(id: "g1", name: "Homework", defaultWeight: 40, defaultText: "40")
        let host = UIHostingController(rootView:
            WhatIfWeightInput(text: .constant(""), category: category).environment(\.dynamicTypeSize, size))
        let fitted = host.sizeThatFits(in: CGSize(width: 320, height: 1_000))
        #expect(fitted.height >= WhatIfWeightInput.minimumHeight && WhatIfWeightInput.minimumHeight * 0.96 >= 44, "\(fitted)")
    }

    @Test("Kept outside Canvas: the disclaimer, then a labelled field per category", .enabled(if: !TestRuntime.sanitized))
    func sheetTree() async throws {
        let details = GradeNotInCanvasDetailTests.details(try await ExternalGrades.snapshot())
        let algebra = WhatIfModel(setup: try #require(details["ALG2"]?.whatIf))
        let elements = try await AccessibilityTree.elements(of: WhatIfSheet(model: algebra).frame(width: 390)) {
            $0.contains { $0.label.hasPrefix("Estimate only.") } && $0.contains { $0.label.hasPrefix("Weight for Tests") }
        }
        #expect(elements.contains { $0.label == Self.disclaimer }, "\(elements)")
        for category in ["Homework", "Tests"] {
            let field = try #require(elements.first { $0.label == "Weight for \(category), percent of grade" }, "\(elements)")
            #expect(field.frame.height > 0)
        }
        let disclaimerIndex = try #require(elements.firstIndex { $0.label == Self.disclaimer })
        let firstField = try #require(elements.firstIndex { $0.label.hasPrefix("Weight for") })
        #expect(disclaimerIndex < firstField, "the disclaimer comes first")
    }

    @Test("Graded in Canvas: no disclaimer and no weights in the sheet", .enabled(if: !TestRuntime.sanitized))
    func canvasSheetTree() async throws {
        let details = GradeNotInCanvasDetailTests.details(try await ExternalGrades.snapshot())
        let spanish = WhatIfModel(setup: try #require(details["SPAN-2"]?.whatIf))
        let spanishElements = try await AccessibilityTree.elements(of: WhatIfSheet(model: spanish).frame(width: 390)) {
            $0.contains { $0.label.contains("Simulation") }
        }
        #expect(!spanishElements.contains { $0.label.hasPrefix("Estimate only.") }, "\(spanishElements)")
        #expect(!spanishElements.contains { $0.label.hasPrefix("Weight for") }, "\(spanishElements)")
    }
}
#endif
