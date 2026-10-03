#if DEBUG
import Foundation
import Testing
import TallyDomain
import TallyStore
import TallySync
import TallyTestSupport
@testable import TallyFeatures

/// M3-D2 (m3d-report.md §6 option A): `AccountUserStateAccess.markDone` is the write
/// `MarkDoneIntentBridge`'s handler calls (registered at launch in `TallyApp.swift`), so this is
/// where the whole chain is exercised without touching the process-wide bridge itself — the same
/// reason `WidgetIntentsTests` never runs an intent's `perform()` against the live
/// `RefreshIntentBridge`: other suites install their own coordinators on these singletons, so a
/// test that set or read them here could race another suite's.
///
/// `GlancePlannerIDTests`-equivalent coverage for "an unknown ID never maps" lives in
/// `GlanceProjectionTests.glancePlannerIDOnlyMapsAssignmentItems` (TallyCore, pure); this suite
/// covers the other half of "unknown is a no-op": no signed-in account to write to.
@Suite("M3-D2: MarkDoneIntentBridge's write — the right assignment, the glance, the reminders pass, no account")
struct MarkDoneIntentTests {
    static let now = Date(timeIntervalSince1970: 1_790_000_000)
    /// 2 days out: comfortably after both Balanced due offsets (`InsightsConfig.balancedDueOffsets`:
    /// 24 h and 1 h before due), so both a reminder's fire date is still in the future at `now`.
    static let dueAt = now.addingTimeInterval(2 * 24 * 60 * 60)
    static let courseID: CanvasID<Course> = CanvasID("100")
    static let assignmentID: CanvasID<Assignment> = CanvasID("9001")

    /// One course, one open assignment due in two days — both as a `PlannerItem` (what the glance
    /// reads) and as a full `Assignment` inside `groups` (what the reminders pass reads), the same
    /// ID either way, so marking it done must take it out of both.
    static func snapshot(accountKey: AccountKey) -> CanvasSnapshot {
        let course = Course(id: courseID, name: "Biology", courseCode: "BIO 101", term: nil, teachers: [],
                            timeZone: nil, appliesGroupWeights: false, hasGradingPeriods: false,
                            currentGradingPeriodID: nil, gradeVisibility: .visible, scores: nil,
                            currentPeriodScores: nil, htmlURL: nil)
        let assignment = Assignment(id: assignmentID, courseID: courseID, groupID: CanvasID("1"), name: "Essay",
                                    dueAt: dueAt, lockAt: nil, pointsPossible: 10,
                                    gradingType: .points, omitFromFinalGrade: false, htmlURL: nil, submission: nil)
        let group = AssignmentGroup(id: CanvasID("1"), name: "Essays", position: 1, weight: nil, rules: DropRules(),
                                    assignments: [assignment])
        let planner = [PlannerItem(id: "assignment:9001", courseID: courseID, title: "Essay", plannableType: "assignment",
                                   dueAt: dueAt, pointsPossible: 10, submitted: false, graded: false,
                                   missing: false, late: false, excused: false, markedComplete: false, htmlURL: nil)]
        return CanvasSnapshot(
            generation: 1, accountKey: accountKey, host: "canvas.example.edu", fetchedAt: now,
            profile: UserProfile(id: "1", name: "Student", shortName: nil, timeZone: nil, calendarFeedURL: nil),
            courses: [course], groups: [courseID: [group]], gradingPeriods: [:], planner: planner, events: [],
            announcements: [], courseColors: [:],
            sections: Dictionary(uniqueKeysWithValues: SnapshotSection.allCases.filter(\.isRequired).map {
                ($0, SectionStatus(fetchedAt: now, carriedForward: false))
            }))
    }

    /// An `AccountEnvironment` over a fresh temporary root, with a `LevelRecordingReminderPlatform`
    /// (`ReminderPassAnswersTests.swift`, same target) so the reminders pass has somewhere real to
    /// schedule and cancel.
    private func makeEnvironment() throws -> (root: URL, environment: AccountEnvironment, platform: LevelRecordingReminderPlatform) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tally-markdone-\(UUID().uuidString)")
        try ProtectedFile.prepareDirectory(root, excludeFromBackup: true)
        let platform = LevelRecordingReminderPlatform()
        let environment = AccountEnvironment(
            storeRoot: { root }, credentialStore: InMemoryCredentialStore(),
            keyring: VaultKeyring(store: InMemoryVaultKeyStore()), lockPreferences: InMemoryAppLockPreferenceStore(),
            transport: RecordingTransport(), notifications: platform, clock: FixedClock(now: Self.now))
        return (root, environment, platform)
    }

    @Test("markDone writes the right assignment, rebuilds the glance (the item leaves it), and one reminders pass drops it")
    func marksTheRightAssignment() async throws {
        let (root, environment, platform) = try makeEnvironment()
        let record = AccountRecord.derived(host: "canvas.example.edu", canvasUserID: "markdone-\(UUID().uuidString)",
                                           clientID: "client-1", displayLabel: "Test School")
        let account = record.accountKey
        try AccountDirectoryStore(root: root).activate(record)

        let snapshot = Self.snapshot(accountKey: account)
        let store = environment.snapshotStore(for: account, root: root)
        try await store.commit(snapshot, includeGrades: false)

        let coordinator = RefreshCoordinator(gateway: ServingGateway(snapshot), store: store,
                                             clock: FixedClock(now: Self.now), initialSnapshot: snapshot)
        let runtime = AccountRuntime()
        await runtime.install(coordinator)

        // Seed: one pass while the item is still open, so the platform holds real pending
        // reminders for it before the mark.
        _ = await ReminderPipeline.reconcile(coordinator: coordinator, environment: environment)
        let pendingBeforeMark = platform.pendingCount
        #expect(pendingBeforeMark > 0, "the fixture's one open assignment must have scheduled reminders before it is marked done")

        let marked = await AccountUserStateAccess.markDone(Self.assignmentID, done: true, runtime: runtime, environment: environment)
        #expect(marked)

        // 1. The write: the right assignment, nothing else.
        guard case .loaded(let state) = await UserStateStore(root: root, accountKey: account, sealer: environment.sealer(for: account)).load()
        else {
            Issue.record("expected the sealed UserState to be readable")
            return
        }
        #expect(state.doneAssignments == [Self.assignmentID])

        // 2. The glance rebuild: the item leaves `dueSoon` at once, no refresh needed.
        guard case .loaded(let glance) = await store.loadGlance() else {
            Issue.record("expected a glance on disk")
            return
        }
        #expect(!glance.dueSoon.contains { $0.id == "assignment:9001" }, "the done item must leave the glance")

        // 3. The reminders pass: with the fixture's only assignment now done, the pass found
        // nothing to remind about, so strictly fewer requests are pending than before the mark.
        #expect(platform.pendingCount < pendingBeforeMark, "marking the item done must have run a reminders pass that dropped it")
    }

    @Test("markDone is a safe no-op with no signed-in account: nothing written, no crash")
    func noActiveAccountIsANoOp() async throws {
        let (root, environment, platform) = try makeEnvironment()
        let runtime = AccountRuntime()
        // No `AccountDirectoryStore(root:).activate(...)`: this root has never seen a sign-in.

        let marked = await AccountUserStateAccess.markDone(Self.assignmentID, done: true, runtime: runtime, environment: environment)
        #expect(!marked)
        #expect(platform.pendingCount == 0, "nothing should have been scheduled for an account that was never signed in")
        #expect((try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("accounts").path))?.isEmpty ?? true,
                "no account directory should exist")
    }
}
#endif
