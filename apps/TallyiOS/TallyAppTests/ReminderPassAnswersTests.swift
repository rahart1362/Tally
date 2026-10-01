#if DEBUG
import Foundation
import Synchronization
import Testing
import TallyDomain
import TallyStore
import TallySync
import TallyTestSupport
@testable import TallyFeatures

/// DEBUG only, like every suite over `AccountLifecycleSupport`'s test doubles (`RecordingTransport`).
///
/// XG-04's open item O1 (`xg04-06-report.md` §11, done in M3-B1): a reminders pass builds
/// `ReminderSubjects` with the "grades kept outside Canvas" answers stored in `UserState` v5, so
/// the priority's course modifiers classify each course as the Dashboard does. Before, the pass
/// classified every course as Automatic, and a student's "Yes" never reached the reminders.
///
/// Serialized with the account-lifecycle suites: every pass runs through `ReminderPipeline`'s
/// process-wide queue. Synthetic `external-grades` persona only.
extension AccountLifecycleSuites {
    @Suite("XG-04 O1: a reminders pass classifies each course with the stored answers")
    struct ReminderPassAnswersTests {
        /// The external-grades anchor plus 12 hours (2026-09-29T01:00Z). SPAN-2's "Tarea 13" is due 29
        /// hours later. With SPAN-2 in Canvas (91.39%, near the 90% boundary, §5.1's bonus) its
        /// priority is 61; without that bonus it is 56. Time Sensitive starts at
        /// `InsightsConfig.dueSoonCriticalMinPriority` (60), so the final reminder's interruption
        /// level shows which rule the pass used. (Computed on Linux with the same rule for anchor
        /// +0 h to +72 h: every instant from +10 h to +17 h straddles 60; M3-B1 journal.)
        static let now = ExternalGrades.anchor.addingTimeInterval(12 * 3600)

        @Test("A stored Yes lowers the pass's priorities exactly as the Dashboard's rule does; Automatic restores them")
        func storedAnswersReachThePass() async throws {
            let snapshot = try await ExternalGrades.snapshot()
            let spanish = try #require(snapshot.courses.first { $0.courseCode == "SPAN-2" })
            let tarea = try #require((snapshot.groups[spanish.id] ?? []).flatMap(\.assignments).first { $0.name == "Tarea 13" })
            let rig = try ReminderAnswersRig(now: Self.now)
            let coordinator = rig.coordinator(over: snapshot)
            let finalReminder = NotificationID.make(accountKey: snapshot.accountKey, kind: .due, canvasID: tarea.id.rawValue,
                                                    ruleID: "due", offset: "3600")

            // Automatic (nothing stored): SPAN-2 is in Canvas, and its score adds the bonus.
            _ = await rig.pass(coordinator)
            #expect(rig.platform.level(of: finalReminder) == .timeSensitive)
            #expect(rig.platform.dueLevels == Self.planned(snapshot, answers: [:]))

            // Yes, stored as Course Detail's menu stores it: no grade modifier, as on the Dashboard.
            let yes: [CanvasID<Course>: GradeAvailabilityOverride] = [spanish.id: .keptOutsideCanvas]
            try await rig.save(UserState(gradeAvailabilityOverrides: yes), for: snapshot.accountKey)
            _ = await rig.pass(coordinator)
            #expect(rig.platform.level(of: finalReminder) == .active, "the stored Yes never reached the pass")
            #expect(rig.platform.dueLevels == Self.planned(snapshot, answers: yes))
            let index = GradeAvailabilityIndex(snapshot: snapshot, overrides: yes, now: Self.now)
            #expect(TallyDomain.DashboardBuilder.modifierScore(of: spanish, availability: index[spanish.id]) == nil,
                    "the Dashboard gives SPAN-2 no score once kept outside Canvas")

            // Automatic again: the bonus is back.
            try await rig.save(UserState(), for: snapshot.accountKey)
            _ = await rig.pass(coordinator)
            #expect(rig.platform.level(of: finalReminder) == .timeSensitive)
        }

        /// Every `.due` reminder's interruption level as `ReminderSubjects` (the Dashboard's rule, with
        /// `answers`) and the Balanced plan give it at `now`: what the pass must schedule.
        static func planned(_ snapshot: CanvasSnapshot, answers: [CanvasID<Course>: GradeAvailabilityOverride])
            -> [String: InterruptionLevel] {
            let subjects = ReminderSubjects(snapshot: snapshot, now: now, gradeAvailabilityOverrides: answers)
            var refresh = RefreshRecord()
            refresh.succeeded(dataFetchedAt: snapshot.fetchedAt)
            let plan = ReminderPlanner.plan(accountKey: snapshot.accountKey, candidates: subjects.candidates,
                                            settings: ReminderSettings(preset: .balanced, hideCourseNames: false),
                                            now: now, timeZone: ReminderAnswersRig.timeZone, refresh: refresh)
            var levels: [String: InterruptionLevel] = [:]
            for reminder in plan where reminder.kind == .due && reminder.fireDate > now {
                levels[reminder.id] = reminder.interruptionLevel
            }
            return levels
        }
    }
}

/// A `ReminderPlatform` that keeps each scheduled request itself (its interruption level), not only
/// its words; always authorized.
final class LevelRecordingReminderPlatform: ReminderPlatform {
    private let state = Mutex([String: (reminder: PendingReminder, content: NotificationContent.Rendered)]())

    func level(of id: String) -> InterruptionLevel? { state.withLock { $0[id]?.reminder.interruptionLevel } }

    /// Every pending `.due` reminder's interruption level, by identifier.
    var dueLevels: [String: InterruptionLevel] {
        state.withLock { pending in
            var levels: [String: InterruptionLevel] = [:]
            for (id, entry) in pending where entry.reminder.kind == .due { levels[id] = entry.reminder.interruptionLevel }
            return levels
        }
    }

    var pendingCount: Int { state.withLock { $0.count } }

    func permission() async -> ReminderPermission { .authorized }
    func requestPermission() async -> ReminderPermission { .authorized }
    func registerCategories() async {}

    func schedule(_ reminder: PendingReminder, content: NotificationContent.Rendered) async {
        state.withLock { $0[reminder.id] = (reminder, content) }
    }

    func schedule(_ reminder: PendingReminder) async {
        await schedule(reminder, content: NotificationContent.Rendered(title: "Tally", body: "Reminder"))
    }

    func pendingContents() async -> [String: NotificationContent.Rendered] { state.withLock { $0.mapValues(\.content) } }
    func pendingIdentifiers() async -> Set<String> { state.withLock { Set($0.keys) } }

    func cancel(ids: Set<String>) async {
        state.withLock { pending in
            for id in ids { pending[id] = nil }
        }
    }
}

/// An `AccountEnvironment` over a temporary store root, in-memory ports, a `LevelRecordingReminderPlatform`
/// and a fixed clock; the pass runs in Chicago time (the persona's school).
struct ReminderAnswersRig: Sendable {
    static let timeZone = TimeZone(identifier: "America/Chicago") ?? .gmt
    let root: URL
    let platform = LevelRecordingReminderPlatform()
    let environment: AccountEnvironment
    let now: Date

    init(now: Date) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("tally-o1-\(UUID().uuidString)")
        try ProtectedFile.prepareDirectory(root, excludeFromBackup: true)
        self.now = now
        let root = self.root
        environment = AccountEnvironment(
            storeRoot: { root }, credentialStore: InMemoryCredentialStore(),
            keyring: VaultKeyring(store: InMemoryVaultKeyStore()), lockPreferences: InMemoryAppLockPreferenceStore(),
            transport: RecordingTransport(), notifications: platform, clock: FixedClock(now: now))
    }

    /// A coordinator holding `snapshot` as its committed snapshot (no refresh runs here).
    func coordinator(over snapshot: CanvasSnapshot) -> RefreshCoordinator {
        RefreshCoordinator(gateway: ServingGateway(snapshot),
                           store: environment.snapshotStore(for: snapshot.accountKey, root: root),
                           clock: FixedClock(now: now), initialSnapshot: snapshot)
    }

    func pass(_ coordinator: RefreshCoordinator) async -> ReminderPassOutcome? {
        await ReminderPipeline.reconcile(coordinator: coordinator, environment: environment, timeZone: Self.timeZone,
                                         locale: Locale(identifier: "en_US"))
    }

    func save(_ state: UserState, for account: AccountKey) async throws {
        try await UserStateStore(root: root, accountKey: account, sealer: environment.sealer(for: account)).save(state)
    }
}
#endif
