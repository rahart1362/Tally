#if DEBUG
import Foundation
import Synchronization
import Testing
import TallyDomain
import TallyStore
import TallyStrings
import TallySync
import TallyTestSupport
@testable import TallyFeatures

/// DEBUG only, like the lifecycle support it uses (`AccountHarness`, the DEBUG
/// `CanvasSnapshot.restamped(accountKey:generation:)`).
///
/// M3-C (E07, UX-WP-12): the post-commit reminders pipeline over a fake `ReminderPlatform` (never
/// the real notification center, never the system permission alert), and the permission UI's model.
/// Every value is synthetic: the flagship fixtures, placeholder tokens.
enum ReminderTestSupport {
    /// The flagship replay's own anchor (2026-09-21T14:13:20Z): plenty of work is due in the next
    /// 14 days, so the plan does not depend on the day the tests run.
    static let anchor = Date(timeIntervalSince1970: 1_790_000_000)
    static let timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
    static let locale = Locale(identifier: "en_US")
    static let flagshipCourseCodes = ["BIO 101", "MATH 122", "ENG 101", "PSY 101", "HIST 210"]

    static func sentinelID(_ account: AccountKey) -> String {
        NotificationID.make(accountKey: account, kind: .sentinel, canvasID: "-", ruleID: "sentinel", offset: "0")
    }
}

/// A `ReminderPlatform` a test drives: a permission (and what a request answers), the pending
/// requests with their words, every call counted, and an optional hold on the next pending read,
/// so a test can act while a pass is in flight.
final class FakeReminderPlatform: ReminderPlatform {
    private struct State {
        var permission: ReminderPermission
        var answer: ReminderPermission
        var pending: [String: NotificationContent.Rendered] = [:]
        var scheduledIDs: [String] = []
        var cancelledIDs: [String] = []
        var requests = 0
        var permissionReads = 0
        var pendingReads = 0
        var holdArmed = false
        var holding = false
        var released = false
        var held: CheckedContinuation<Void, Never>?
    }

    private let state: Mutex<State>

    init(permission: ReminderPermission = .authorized, answer: ReminderPermission = .authorized) {
        state = Mutex(State(permission: permission, answer: answer))
    }

    var pending: [String: NotificationContent.Rendered] { state.withLock { $0.pending } }
    var scheduledIDs: [String] { state.withLock { $0.scheduledIDs } }
    var requests: Int { state.withLock { $0.requests } }
    var permissionReads: Int { state.withLock { $0.permissionReads } }
    var pendingReads: Int { state.withLock { $0.pendingReads } }
    var isHolding: Bool { state.withLock { $0.holding } }

    func setPermission(_ permission: ReminderPermission) { state.withLock { $0.permission = permission } }

    /// The next `pendingContents()` waits until `release()`.
    func holdNextPendingRead() { state.withLock { $0.holdArmed = true; $0.released = false } }

    func release() {
        let held = state.withLock { state -> CheckedContinuation<Void, Never>? in
            state.released = true
            defer { state.held = nil }
            return state.held
        }
        held?.resume()
    }

    func permission() async -> ReminderPermission {
        state.withLock { $0.permissionReads += 1; return $0.permission }
    }

    func requestPermission() async -> ReminderPermission {
        state.withLock { state in
            state.requests += 1
            if state.permission == .notDetermined { state.permission = state.answer }
            return state.permission
        }
    }

    func registerCategories() async {}

    func schedule(_ reminder: PendingReminder, content: NotificationContent.Rendered) async {
        state.withLock { $0.pending[reminder.id] = content; $0.scheduledIDs.append(reminder.id) }
    }

    func schedule(_ reminder: PendingReminder) async {
        await schedule(reminder, content: NotificationContent.Rendered(title: "Tally", body: "Reminder"))
    }

    func pendingContents() async -> [String: NotificationContent.Rendered] {
        let holds = state.withLock { state -> Bool in
            state.pendingReads += 1
            guard state.holdArmed else { return false }
            state.holdArmed = false
            state.holding = true
            return true
        }
        if holds {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let resumeNow = state.withLock { state -> Bool in
                    if state.released { return true }
                    state.held = continuation
                    return false
                }
                if resumeNow { continuation.resume() }
            }
            state.withLock { $0.holding = false }
        }
        return state.withLock { $0.pending }
    }

    func pendingIdentifiers() async -> Set<String> { state.withLock { Set($0.pending.keys) } }

    func cancel(ids: Set<String>) async {
        state.withLock { state in
            for id in ids { state.pending[id] = nil }
            state.cancelledIDs.append(contentsOf: ids)
        }
    }
}

/// An `AccountHarness` whose environment injects a `FakeReminderPlatform` and a fixed clock (the
/// flagship anchor unless a test picks another instant).
struct ReminderRig: Sendable {
    let harness: AccountHarness
    let platform: FakeReminderPlatform
    let environment: AccountEnvironment
    let now: Date

    init(permission: ReminderPermission = .authorized, answer: ReminderPermission = .authorized,
         now: Date = ReminderTestSupport.anchor) throws {
        harness = try AccountHarness()
        platform = FakeReminderPlatform(permission: permission, answer: answer)
        self.now = now
        let root = harness.root
        environment = AccountEnvironment(
            storeRoot: { root }, credentialStore: harness.credentials, keyring: harness.keyring,
            lockPreferences: harness.lockPreferences, transport: harness.transport, notifications: platform,
            clock: FixedClock(now: now),
            gatewayOverride: { account in FlagshipAccountGateway(account: account.accountKey) })
    }

    var account: AccountKey { harness.account }

    /// A coordinator over the account's flagship snapshot, with no pipeline attached (the tests drive
    /// `ReminderPipeline.reconcile` themselves).
    func coordinator() async throws -> RefreshCoordinator {
        let snapshot = try await FlagshipAccountGateway.flagship(account: account)
        return RefreshCoordinator(gateway: FlagshipAccountGateway(account: account),
                                  store: environment.snapshotStore(for: account, root: harness.root),
                                  clock: FixedClock(now: now), initialSnapshot: snapshot)
    }

    func pass(_ coordinator: RefreshCoordinator) async -> ReminderPassOutcome? {
        await ReminderPipeline.reconcile(coordinator: coordinator, environment: environment,
                                         timeZone: ReminderTestSupport.timeZone, locale: ReminderTestSupport.locale)
    }

    func ledger() async -> SyncLedgerLoadResult {
        await SyncLedgerStore(root: harness.root, accountKey: account, sealer: environment.sealer(for: account)).load()
    }

    func saveUserState(_ state: UserState) async throws {
        try await UserStateStore(root: harness.root, accountKey: account, sealer: environment.sealer(for: account)).save(state)
    }

    /// The composition root's shape over this environment (`AppEnvironment.live()`).
    @MainActor
    func appModel() -> AppModel {
        let environment = environment
        return AppModel(accountRuntime: AccountRuntime(resolve: { await AccountSessionFactory.activeCoordinator(environment) }),
                        accountEnvironment: environment)
    }
}

// MARK: - The words (R10)

@Suite("M3-C: reminder words from the snapshot (R10, §3.6)")
struct ReminderContentTests {
    private struct Planned {
        let subjects: ReminderSubjects
        let plan: [PendingReminder]
        let account: AccountKey
        let snapshot: CanvasSnapshot
    }

    private func makePlan(now: Date = ReminderTestSupport.anchor) async throws -> Planned {
        let account = AccountKey("m3c-content-\(UUID().uuidString)")
        let snapshot = try await FlagshipSnapshotHarness.fetchSnapshot(now: ReminderTestSupport.anchor)
            .restamped(accountKey: account, generation: 1)
        let subjects = ReminderSubjects(snapshot: snapshot, now: now)
        var refresh = RefreshRecord()
        refresh.succeeded(dataFetchedAt: now)
        let plan = ReminderPlanner.plan(accountKey: account, candidates: subjects.candidates, settings: ReminderSettings(),
                                        now: now, timeZone: ReminderTestSupport.timeZone, refresh: refresh)
        return Planned(subjects: subjects, plan: plan, account: account, snapshot: snapshot)
    }

    private func words(_ planned: Planned, hide: Bool) -> [String: NotificationContent.Rendered] {
        let format = ReminderTimeFormat(timeZone: ReminderTestSupport.timeZone, locale: ReminderTestSupport.locale)
        var out: [String: NotificationContent.Rendered] = [:]
        for reminder in planned.plan {
            out[reminder.id] = planned.subjects.content(for: reminder, accountKey: planned.account, hideCourseNames: hide,
                                                        lastSuccess: ReminderTestSupport.anchor, format: format)
        }
        return out
    }

    @Test("every due item has words; none carries a grade; Hide Course Names hides every course code and title")
    func wordsNeverLeak() async throws {
        let planned = try await makePlan()
        let due = planned.plan.filter { $0.kind == .due }
        #expect(due.count >= 10, "the flagship anchor should plan plenty of due reminders, got \(due.count)")

        let shown = words(planned, hide: false)
        #expect(due.allSatisfy { shown[$0.id] != nil }, "a due reminder had no words")
        #expect(shown.values.contains { text in ReminderTestSupport.flagshipCourseCodes.contains { text.title.contains($0) } },
                "course codes should show while Hide Course Names is off")
        let scores = planned.snapshot.courses.compactMap(\.scores?.currentScore)
            .map { $0.formatted(.number.precision(.fractionLength(1))) }
        for text in shown.values {
            #expect(!text.title.contains("%") && !text.body.contains("%"), "a grade-like value: \(text)")
            #expect(!scores.contains { text.title.contains($0) || text.body.contains($0) }, "a course score: \(text)")
        }

        let hidden = words(planned, hide: true)
        #expect(hidden.count == shown.count)
        let titles = planned.subjects.openItems.map(\.assignment.name)
        for text in hidden.values {
            for code in ReminderTestSupport.flagshipCourseCodes {
                #expect(!text.title.contains(code) && !text.body.contains(code), "\(code) shown with names hidden: \(text)")
            }
            for title in titles {
                #expect(!text.title.contains(title) && !text.body.contains(title), "\(title) shown with names hidden: \(text)")
            }
        }
    }

    @Test("the final due reminder allows for a submission Tally can't see; the day-before one does not")
    func finalReminderIsConditional() async throws {
        let planned = try await makePlan()
        let shown = words(planned, hide: false)
        let finals = planned.plan.filter {
            $0.kind == .due && $0.id == ReminderSubjects.finalDueReminderID(accountKey: planned.account, subjectID: $0.subjectID)
        }
        let earlier = planned.plan.filter { $0.kind == .due && !finals.contains($0) }
        #expect(!finals.isEmpty && !earlier.isEmpty)
        #expect(finals.allSatisfy { shown[$0.id]?.body.hasSuffix("if you haven't submitted yet.") == true })
        #expect(earlier.allSatisfy { shown[$0.id]?.body.hasSuffix("if you haven't submitted yet.") == false })
    }

    @Test("a digest with nothing due has no words, so it is never sent; the stale-data warning still has words")
    func emptyDigestsAreDropped() async throws {
        let later = ReminderTestSupport.anchor.addingTimeInterval(400 * 24 * 3600) // every flagship item is past
        let planned = try await makePlan(now: later)
        // Overdue work with no closing date stays open (`PriorityScore.isExcluded`), but none is due ahead.
        #expect(!planned.subjects.openItems.contains { $0.dueAt > later })
        // Built here rather than taken from the plan: the planner itself stops planning an empty
        // evening digest once PR #8 (P-2) lands, and the words step must hold either way.
        let format = ReminderTimeFormat(timeZone: ReminderTestSupport.timeZone, locale: ReminderTestSupport.locale)
        for kind in [NotificationKind.digest, .weekAhead] {
            let digest = PendingReminder(id: "d-\(kind)", kind: kind, fireDate: later.addingTimeInterval(3600),
                                         interruptionLevel: .passive, subjectID: "-")
            #expect(planned.subjects.content(for: digest, accountKey: planned.account, hideCourseNames: false,
                                             lastSuccess: later, format: format) == nil,
                    "a \(kind) with nothing due would have been sent")
        }
        let sentinel = PendingReminder(id: "s", kind: .sentinel, fireDate: later, interruptionLevel: .passive, subjectID: "-")
        let words = planned.subjects.content(for: sentinel, accountKey: planned.account, hideCourseNames: false,
                                             lastSuccess: later.addingTimeInterval(-24 * 3600), format: format)
        #expect(words?.title.hasPrefix("Tally hasn't refreshed since yesterday at") == true)
    }

    @Test("dates read relative to when the notification arrives")
    func dayTimeWords() {
        let format = ReminderTimeFormat(timeZone: ReminderTestSupport.timeZone, locale: ReminderTestSupport.locale)
        let fire = ReminderTestSupport.anchor // Mon 2026-09-21, 10:13 AM in New York
        let hour: TimeInterval = 3600
        #expect(format.dayTime(fire.addingTimeInterval(2 * hour), relativeTo: fire).hasPrefix("today at "))
        #expect(format.dayTime(fire.addingTimeInterval(24 * hour), relativeTo: fire).hasPrefix("tomorrow at "))
        #expect(format.dayTime(fire.addingTimeInterval(-24 * hour), relativeTo: fire).hasPrefix("yesterday at "))
        #expect(format.dayTime(fire.addingTimeInterval(4 * 24 * hour), relativeTo: fire).hasPrefix("Fri at "))
        #expect(format.dayTime(fire.addingTimeInterval(10 * 24 * hour), relativeTo: fire).hasPrefix("Oct 1 at "))
        let time = format.time(fire.addingTimeInterval(2 * hour))
        #expect(format.dayTime(fire.addingTimeInterval(2 * hour), relativeTo: fire) == "today at \(time)")
    }
}

// MARK: - The pipeline

// Serialized with the account-lifecycle suites: every reminders pass runs through `ReminderPipeline`'s
// process-wide `ReminderPassQueue`. Running this suite in parallel with `ReminderLifecycleTests` let one
// suite's passes hold the queue while the other waited (hypothesis for the recurring "no pass at launch /
// after the commit" timeouts: PR #11 required ios-build, PR #16 Xcode 27).
extension AccountLifecycleSuites {
@Suite("M3-C: the reminders pipeline (plan, reconcile, schedule)")
struct ReminderPipelineTests {
    @Test("a pass schedules the plan and records it; a second pass over the same data schedules and cancels nothing")
    func passIsIdempotent() async throws {
        let rig = try ReminderRig()
        let coordinator = try await rig.coordinator()

        let first = await rig.pass(coordinator)
        guard case .reconciled(let scheduled, let cancelled) = first else {
            Issue.record("the first pass did not reconcile: \(String(describing: first))")
            return
        }
        #expect(scheduled > 10 && cancelled == 0)
        #expect(rig.platform.pending.count == scheduled)
        #expect(rig.platform.pending.count <= TallyConfig.pendingNotificationCap)
        guard case .loaded(let ledger) = await rig.ledger() else {
            Issue.record("the ledger was not written")
            return
        }
        #expect(Set(ledger.notifications.keys) == Set(rig.platform.pending.keys))

        #expect(await rig.pass(coordinator) == .reconciled(scheduled: 0, cancelled: 0))
        #expect(rig.platform.scheduledIDs.count == scheduled, "the second pass scheduled something twice")
    }

    @Test("without permission a pass plans nothing, schedules nothing and writes no ledger",
          arguments: [ReminderPermission.denied, .notDetermined])
    func unauthorisedPassDoesNothing(_ permission: ReminderPermission) async throws {
        let rig = try ReminderRig(permission: permission)
        let coordinator = try await rig.coordinator()
        #expect(await rig.pass(coordinator) == .notAuthorized)
        #expect(rig.platform.scheduledIDs.isEmpty && rig.platform.pendingReads == 0)
        #expect(await rig.ledger() == .absent)
        #expect(rig.platform.requests == 0, "a pass asked for permission")
    }

    @Test("Hide Course Names: the next pass rewrites every pending reminder that named something, then settles")
    func hidingNamesRewritesPendingWords() async throws {
        let rig = try ReminderRig()
        let coordinator = try await rig.coordinator()
        _ = await rig.pass(coordinator)
        let named = rig.platform.pending.values.filter { text in
            ReminderTestSupport.flagshipCourseCodes.contains { text.title.contains($0) }
        }
        #expect(!named.isEmpty)

        try await rig.saveUserState(UserState(hideCourseNamesInNotifications: true))
        guard case .reconciled(let rescheduled, _) = await rig.pass(coordinator) else {
            Issue.record("the pass did not reconcile")
            return
        }
        #expect(rescheduled >= named.count, "only \(rescheduled) of \(named.count) named reminders were rewritten")
        for text in rig.platform.pending.values {
            for code in ReminderTestSupport.flagshipCourseCodes {
                #expect(!text.title.contains(code) && !text.body.contains(code), "\(code) still pending: \(text)")
            }
        }
        #expect(await rig.pass(coordinator) == .reconciled(scheduled: 0, cancelled: 0))
    }

    @Test("a cache more than a day old: the stale-data warning is not scheduled in the past (planner finding P-1)")
    func nothingInThePast() async throws {
        // The flagship is fetched now (`FlagshipAccountGateway`), so its warning is due in 24 h; the
        // pass runs 3 days later, when that date is past.
        let rig = try ReminderRig(now: Date().addingTimeInterval(3 * 24 * 3600))
        let coordinator = try await rig.coordinator()
        guard case .reconciled = await rig.pass(coordinator) else {
            Issue.record("the pass did not reconcile")
            return
        }
        #expect(rig.platform.pending[ReminderTestSupport.sentinelID(rig.account)] == nil,
                "the stale-data warning was scheduled for a moment already past")
        #expect(!rig.platform.pending.isEmpty, "nothing was scheduled at all")
    }

    @Test("a retired coordinator (sign-out) has no snapshot: a pass does nothing")
    func retiredCoordinatorDoesNothing() async throws {
        let rig = try ReminderRig()
        let coordinator = try await rig.coordinator()
        await coordinator.bumpEpochAndCancel()
        #expect(await rig.pass(coordinator) == .noSnapshot)
        #expect(rig.platform.scheduledIDs.isEmpty)
    }

    /// Plan 08 §3.3 fix (L10N-03a): `ReminderPipeline.reconcile`/`attach` used to default `locale:`
    /// to `Locale.current`; it is now `TallyLocale.effective` (`ReminderPipeline.swift`). Two
    /// otherwise-identical passes, one with the default and one with `locale: TallyLocale.effective`
    /// explicit, must schedule the same words.
    ///
    /// UNVERIFIED by mutation in this CI environment specifically, for the same reason noted on
    /// `FreshnessPresenterTests.defaultLocaleMatchesTallyLocaleEffective`: on iOS 26 the L10N-01
    /// spike found `Locale.current` for an English-shipping app already equal to
    /// `TallyLocale.effective` in every case it observed (`l10n-infra-report.md` §2 row 4), so a
    /// revert to the old `Locale.current` default would not change this test's result here. It still
    /// pins the intended, documented behaviour (`l10n02-report.md` §8 "For L10N-03a").
    @Test("the default locale is TallyLocale.effective: same reminder words as passing it explicitly")
    func defaultLocaleMatchesTallyLocaleEffective() async throws {
        let defaultRig = try ReminderRig()
        let defaultCoordinator = try await defaultRig.coordinator()
        _ = await ReminderPipeline.reconcile(coordinator: defaultCoordinator, environment: defaultRig.environment,
                                             timeZone: ReminderTestSupport.timeZone)

        let explicitRig = try ReminderRig()
        let explicitCoordinator = try await explicitRig.coordinator()
        _ = await ReminderPipeline.reconcile(coordinator: explicitCoordinator, environment: explicitRig.environment,
                                             timeZone: ReminderTestSupport.timeZone, locale: TallyLocale.effective)

        // Compared by words, not by identifier (each rig's account, and so each notification ID, differs).
        let defaultWords = Set(defaultRig.platform.pending.values.map { "\($0.title)|\($0.body)" })
        let explicitWords = Set(explicitRig.platform.pending.values.map { "\($0.title)|\($0.body)" })
        #expect(!defaultWords.isEmpty)
        #expect(defaultWords == explicitWords)
    }
}
} // AccountLifecycleSuites

// MARK: - The permission, asked in context (UX-WP-12)

// Serialized with the account-lifecycle suites: every reminders pass runs through `ReminderPipeline`'s
// process-wide `ReminderPassQueue`. Running this suite in parallel with `ReminderLifecycleTests` let one
// suite's passes hold the queue while the other waited (hypothesis for the recurring "no pass at launch /
// after the commit" timeouts: PR #11 required ios-build, PR #16 Xcode 27).
extension AccountLifecycleSuites {
@Suite("M3-C: the reminders permission and the Dashboard tip (UX-WP-12)")
@MainActor
struct RemindersModelTests {
    @Test("the tip: signed in, never asked, work due, not dismissed; each condition alone hides it")
    func tipPolicy() {
        #expect(ReminderTipPolicy.showsTip(isSampleData: false, permission: .notDetermined, hasUpcomingDueItem: true, isSnoozed: false))
        #expect(!ReminderTipPolicy.showsTip(isSampleData: true, permission: .notDetermined, hasUpcomingDueItem: true, isSnoozed: false))
        #expect(!ReminderTipPolicy.showsTip(isSampleData: false, permission: .denied, hasUpcomingDueItem: true, isSnoozed: false))
        #expect(!ReminderTipPolicy.showsTip(isSampleData: false, permission: .authorized, hasUpcomingDueItem: true, isSnoozed: false))
        #expect(!ReminderTipPolicy.showsTip(isSampleData: false, permission: nil, hasUpcomingDueItem: true, isSnoozed: false))
        #expect(!ReminderTipPolicy.showsTip(isSampleData: false, permission: .notDetermined, hasUpcomingDueItem: false, isSnoozed: false))
        #expect(!ReminderTipPolicy.showsTip(isSampleData: false, permission: .notDetermined, hasUpcomingDueItem: true, isSnoozed: true))
    }

    @Test("dismissed, the tip stays away for 7 days (clock-injected), then returns")
    func tipReturnsAfterSevenDays() async {
        let clock = TestClock()
        let model = RemindersModel(platform: FakeReminderPlatform(permission: .notDetermined), clock: clock)
        await model.refreshPermission()
        #expect(model.showsTip(isSampleData: false, hasUpcomingDueItem: true))

        model.dismissTip()
        #expect(!model.showsTip(isSampleData: false, hasUpcomingDueItem: true))
        clock.advance(by: RemindersConfig.tipSnooze - .seconds(1))
        await model.refreshPermission()
        #expect(!model.showsTip(isSampleData: false, hasUpcomingDueItem: true), "the tip came back early")
        clock.advance(by: .seconds(1))
        await model.refreshPermission()
        #expect(model.showsTip(isSampleData: false, hasUpcomingDueItem: true), "the tip never came back")
    }

    @Test("reading the permission never asks; Turn On asks once, and a yes schedules at once")
    func turnOnAsksOnceAndSchedules() async {
        let platform = FakeReminderPlatform(permission: .notDetermined, answer: .authorized)
        let passes = CallCounter()
        let model = RemindersModel(platform: platform, reconcile: { passes.increment() })
        await model.refreshPermission()
        await model.refreshPermission()
        #expect(platform.requests == 0, "reading the permission asked for it")
        #expect(model.status(isSampleData: false) == .off)

        model.requestPermission()
        model.requestPermission() // a second tap while the first is on screen
        await model.awaitWork()
        #expect(platform.requests == 1)
        #expect(model.permission == .authorized && model.status(isSampleData: false) == .on)
        #expect(passes.value == 1, "granting did not schedule the reminders at once")
        #expect(!model.showsTip(isSampleData: false, hasUpcomingDueItem: true))
    }

    @Test("denied: Settings offers Open Settings, the tip is gone, nothing is scheduled; allowed later in iOS Settings, it schedules")
    func deniedThenAllowedInSettings() async {
        let platform = FakeReminderPlatform(permission: .notDetermined, answer: .denied)
        let passes = CallCounter()
        let model = RemindersModel(platform: platform, reconcile: { passes.increment() })
        await model.refreshPermission()
        model.requestPermission()
        await model.awaitWork()
        #expect(model.status(isSampleData: false) == .deniedInSettings)
        #expect(!model.showsTip(isSampleData: false, hasUpcomingDueItem: true))
        #expect(passes.value == 0)

        platform.setPermission(.authorized) // the student turned notifications on in iOS Settings
        await model.refreshPermission()
        await model.awaitWork()
        #expect(model.status(isSampleData: false) == .on)
        #expect(passes.value == 1)
    }

    @Test("Hide Course Names is saved with the other settings, then runs a pass")
    func hideCourseNamesSavesThenReconciles() async {
        let access = InMemoryUserStateAccess()
        let saved = CallCounter()
        let settings = SettingsModel(userState: access, notificationSettingsSaved: { saved.increment() })
        await settings.load()
        #expect(!settings.hideCourseNamesInNotifications, "course names show by default (R10's toggle is opt-in)")
        settings.setHideCourseNamesInNotifications(true)
        await settings.awaitSaved()
        #expect(await access.load().hideCourseNamesInNotifications)
        #expect(saved.value == 1 && !settings.hideCourseNamesSaveFailed)
    }

    @Test("A11Y-11: only a tap asks: requestPermission() is called from the tip's and Settings' buttons alone")
    func onlyATapAsks() throws {
        let files = try ScreenSourceHygieneTests.appRoots.flatMap { try ScreenSourceHygieneTests.swiftFiles(under: $0) }
        func callSites(_ needle: String) throws -> [String: Int] {
            let hits = try ScreenSourceHygieneTests.hits(in: files) { line in
                !line.drop { $0 == " " }.hasPrefix("//") && line.contains(needle)
            }
            return Dictionary(grouping: hits) { String($0.prefix { $0 != ":" }) }.mapValues(\.count)
        }
        let reminders = "packages/TallyAppleKit/Sources/TallyFeatures/Reminders/"
        #expect(try callSites(".requestPermission()") == [reminders + "RemindersViews.swift": 2,
                                                          reminders + "RemindersModel.swift": 1],
                "the reminders permission is requested from somewhere other than a button")
        #expect(try callSites("requestAuthorization(").keys.sorted() == ["packages/TallyAppleKit/Sources/TallyPlatform/UNNotificationScheduler.swift"])
    }

    @Test("the UI-test hook scripts the permission; without it the injected platform is used")
    func testHookScripts() async {
        let deniedOnAsk = ReminderTestHooks.script(arguments: ["-TallyTestHooks.notifications", "notDetermined:denied"])
        #expect(deniedOnAsk?.state == .notDetermined && deniedOnAsk?.answer == .denied)
        let allowed = ReminderTestHooks.script(arguments: ["-TallyTestHooks.notifications", "authorized"])
        #expect(allowed?.state == .authorized && allowed?.answer == .authorized)
        #expect(ReminderTestHooks.script(arguments: ["-TallyTestHooks.notifications", "maybe"]) == nil)
        #expect(ReminderTestHooks.script(arguments: []) == nil)
        let injected = FakeReminderPlatform()
        let unhooked = ReminderTestHooks.platform(replacing: injected, arguments: []) as? FakeReminderPlatform
        #expect(unhooked === injected)
        let scripted = ReminderTestHooks.platform(replacing: injected, arguments: ["-TallyTestHooks.notifications", "notDetermined:denied"])
        #expect(await scripted?.permission() == .notDetermined)
        #expect(await scripted?.requestPermission() == .denied)
        #expect(injected.requests == 0, "the scripted permission reached the real platform")
    }
}
} // AccountLifecycleSuites

// MARK: - Over the account's lifecycle

extension AccountLifecycleSuites {
    /// The pipeline through the real composition: `AccountSessionFactory` attaches it to the account's
    /// coordinator, `AppModel` launches, commits and signs out. `.serialized` with the other lifecycle
    /// suites (`RefreshIntentBridge`).
    @Suite("M3-C: reminders over the account lifecycle", .serialized)
    @MainActor
    struct ReminderLifecycleTests {
        private func launched(_ rig: ReminderRig) async throws -> AppModel {
            try await rig.harness.seedSignedInAccount()
            let model = rig.appModel()
            await model.launch()
            await model.awaitLaunchWork()
            return model
        }

        @Test("launch plans once from the cached snapshot, before any refresh; an unchanged commit schedules nothing new")
        func launchThenCommit() async throws {
            // Diagnostic (PMO, 2026-10-01): this test intermittently waits ~30 s for a reminders pass
            // (PR #11, #16, XG-03 runs; 30.377 s in PR #17's run even with the suites serialized).
            // The REMINDER-TIMING lines show which step the time goes to; remove once explained.
            let rig = try ReminderRig()
            let clock = ContinuousClock()
            let started = clock.now
            func mark(_ step: String) { print("REMINDER-TIMING \(step) +\(clock.now - started) reads=\(rig.platform.pendingReads)") }
            let model = try await launched(rig)
            mark("launched")
            #expect(try await AccountTestSupport.eventually { rig.platform.pendingReads >= 1 }, "no pass at launch")
            mark("launch pass read")
            await ReminderPipeline.drain()
            let coordinator = try #require(await model.accountRuntime.coordinator())
            #expect(await coordinator.committedSnapshot?.generation == 1, "the launch pass waited for a refresh")
            let fromCache = rig.platform.scheduledIDs
            #expect(fromCache.count > 10, "the launch pass scheduled \(fromCache.count) reminders")
            let pendingFromCache = Set(rig.platform.pending.keys)

            await model.home?.start() // the launch refresh commits generation 2 (the same work)
            mark("home started")
            #expect(await coordinator.committedSnapshot?.generation == 2)
            #expect(try await AccountTestSupport.eventually { rig.platform.pendingReads >= 2 }, "no pass after the commit")
            mark("commit pass read")
            await ReminderPipeline.drain()
            let again = Set(rig.platform.scheduledIDs.dropFirst(fromCache.count))
            // Only the stale-data warning moves: each commit pushes it a day past the new fetch (R17).
            #expect(again.isSubset(of: [ReminderTestSupport.sentinelID(rig.account)]),
                    "an unchanged commit scheduled \(again.count) reminders again")
            #expect(Set(rig.platform.pending.keys) == pendingFromCache)
            guard case .loaded(let ledger) = await rig.ledger() else {
                Issue.record("no ledger after the commit's pass")
                return
            }
            #expect(Set(ledger.notifications.keys) == pendingFromCache)
        }

        @Test("denied: the launch schedules nothing and writes no ledger; Settings says so and the tip never shows")
        func deniedLaunch() async throws {
            let rig = try ReminderRig(permission: .denied)
            let model = try await launched(rig)
            // One read by the launch's pass, one by `attach` for the tip.
            #expect(try await AccountTestSupport.eventually { rig.platform.permissionReads >= 2 })
            await ReminderPipeline.drain()
            #expect(rig.platform.scheduledIDs.isEmpty)
            #expect(await rig.ledger() == .absent)
            #expect(model.reminders.status(isSampleData: false) == .deniedInSettings)
            #expect(!model.reminders.showsTip(isSampleData: false, hasUpcomingDueItem: true))
            #expect(rig.platform.requests == 0, "the launch asked for permission (A11Y-11)")
        }

        @Test("sign-out waits for a pass in flight, then nothing of the account stays pending or on disk")
        func signOutLeavesNothing() async throws {
            let rig = try ReminderRig()
            let account = rig.account
            let model = try await launched(rig)
            #expect(try await AccountTestSupport.eventually { rig.platform.pendingReads >= 1 })
            await ReminderPipeline.drain()
            #expect(!rig.platform.pending.isEmpty)

            // The commit's pass stops at its read of the pending requests.
            rig.platform.holdNextPendingRead()
            await model.home?.start()
            #expect(try await AccountTestSupport.eventually { rig.platform.isHolding }, "the commit's pass never started")

            model.signOut()
            try await Task.sleep(for: .milliseconds(300))
            #expect(!model.signOutSteps.contains(.purge), "the purge ran while a reminders pass was still in flight")
            rig.platform.release()
            await model.awaitTeardown()

            #expect(rig.platform.pending.isEmpty, "\(rig.platform.pending.count) reminders survived sign-out")
            #expect(!FileManager.default.fileExists(atPath: rig.harness.accountDirectory.path),
                    "a pass wrote the account's store after the purge")
            let scheduledAfter = rig.platform.scheduledIDs.count
            try await Task.sleep(for: .milliseconds(200))
            #expect(rig.platform.scheduledIDs.count == scheduledAfter, "a pass scheduled after sign-out")
            #expect(try await HomeTestSupport.waitUntil { CanvasSnapshotInstances.liveCount(for: account) == 0 },
                    "the reminders pipeline kept a CanvasSnapshot of the signed-out account")
        }

        @Test("sample data: no pass, nothing scheduled, and the tip never shows though work is due and nothing was asked")
        func sampleModeNeverAsks() async throws {
            let rig = try ReminderRig(permission: .notDetermined)
            let model = rig.appModel()
            model.bootstrap()
            model.enterSample()
            let home = try #require(model.home)
            await home.start()
            #expect(try await HomeTestSupport.waitUntil { home.phase == .loaded })
            #expect(home.isSampleData && !home.dashboard.dueSoon.isEmpty, "the sample dashboard should have work due")

            await model.reminders.refreshPermission()
            #expect(model.reminders.permission == .notDetermined)
            #expect(!model.reminders.showsTip(isSampleData: home.isSampleData, hasUpcomingDueItem: !home.dashboard.dueSoon.isEmpty))
            #expect(model.reminders.status(isSampleData: home.isSampleData) == .sampleData)
            #expect(await model.accountRuntime.coordinator() == nil)
            await ReminderPipeline.drain()
            #expect(rig.platform.scheduledIDs.isEmpty && rig.platform.requests == 0)
            model.exitSample()
            await model.awaitTeardown()
        }
    }
}
#endif
