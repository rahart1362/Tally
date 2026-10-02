import Foundation
import Synchronization
import TallyDomain
import TallyStore
import TallyStrings
import TallySync

/// What one reminders pass did (M3-C, E07). Counts only, never a title or an ID.
public nonisolated enum ReminderPassOutcome: Sendable, Equatable {
    /// Notifications are not allowed (never asked, or denied): nothing is planned or scheduled, and
    /// the ledger is left as it is (insights-at-a-glance.md §3.3: "Nothing is scheduled before
    /// notification permission is granted").
    case notAuthorized
    /// No committed snapshot: the account has no data yet, or it was signed out.
    case noSnapshot
    /// The account's store could not be read (locked device, unreadable ledger): try at the next commit.
    case storeUnavailable
    /// The platform now holds exactly the plan: `scheduled` requests were added or replaced and
    /// `cancelled` identifiers removed. Both are 0 when nothing changed (the pass is idempotent).
    case reconciled(scheduled: Int, cancelled: Int)
    /// PAY-07 (M3-B1): reminders need the trial or the subscription, and the entitlement gate said
    /// no, so the pass planned nothing: every pending Tally reminder of the account (`cancelled`)
    /// was withdrawn, and the ledger is empty.
    case withdrawn(cancelled: Int)
}

/// The post-commit reminders pipeline (M3-C, E07; architecture.md §3.4 step 2): `ReminderPlanner`
/// plans the Balanced preset (PMO R14) from the committed snapshot, `NotificationReconciler` diffs it
/// against the account's `SyncLedger` and the platform's pending requests, and the platform adds and
/// removes only the difference. Off the main actor throughout.
///
/// **When.** `attach(to:account:environment:)`, which `AccountSessionFactory` calls for every
/// coordinator it builds (the launch, a background launch, a sign-in), runs one pass from the cached
/// snapshot at once, then one after every `.committed` event. The permission UI runs one when the
/// student turns reminders on, and Settings when "Hide Course Names" is saved.
///
/// **One at a time.** Every pass, for any account, runs through one process-wide serial queue, so
/// two passes never interleave on a ledger. Each pass reads the coordinator's `committedSnapshot`
/// when it starts: a retired coordinator (sign-out) has none, so the pass does nothing.
/// `drain()` waits for every pass queued so far; sign-out calls it after retiring the coordinator and
/// before `SignOutUseCase` cancels the account's notifications, so no pass can schedule after that
/// cancel or write a ledger after the purge.
///
/// **Entitlement (PAY-07, M3-B1).** Reminders need the trial or the subscription. A pass asks the
/// account's entitlement gate (`AccountEnvironment.entitlement`); when it says no, the pass plans
/// nothing and so withdraws every pending Tally reminder (`.withdrawn`). The subscription engine
/// runs one pass when the answer changes, so a lapse withdraws them at once and a purchase plans
/// them again.
///
/// **Idempotent.** The planner's IDs are deterministic and the reconciler keys every decision by
/// them, so a second pass over the same snapshot at the same time schedules and cancels nothing.
/// A reminder whose words changed (a renamed assignment, "Hide Course Names") is scheduled again:
/// its ledger entry is dropped before reconciling when the pending text differs.
public nonisolated enum ReminderPipeline {
    /// The one serial queue every pass runs through.
    private static let passes = ReminderPassQueue()

    /// Subscribes to `coordinator`'s events, then (in a task that ends with the coordinator's event
    /// stream: sign-out, or the coordinator's release) runs a pass from the cached snapshot and one
    /// after every commit. Holds the coordinator weakly. A no-op when the injected notification
    /// adapter is not a `ReminderPlatform` (tests and previews with a plain scheduler).
    /// Plan 08 §3.3 (L10N-03a fix): defaulted to `Locale.current`, which agrees with
    /// `TallyLocale.effective` on iOS 26 in every case the L10N-01 spike observed, but
    /// `TallyLocale.effective` is the plan's single formatting locale (`l10n02-report.md` §8), so
    /// this is the safer default. Neither caller (`AccountSessionFactory.swift:59`,
    /// `AppModel.swift:129`) passes `locale:`.
    @concurrent
    public static func attach(to coordinator: RefreshCoordinator, account: AccountKey, environment: AccountEnvironment,
                              timeZone: TimeZone = .current, locale: Locale = TallyLocale.effective) async {
        guard let platform = environment.notifications as? any ReminderPlatform else { return }
        let events = await coordinator.events()
        Task(priority: .utility) { [weak coordinator] in
            await pass(coordinator, account: account, platform: platform, environment: environment,
                       timeZone: timeZone, locale: locale)
            for await event in events {
                guard case .committed = event else { continue }
                await pass(coordinator, account: account, platform: platform, environment: environment,
                           timeZone: timeZone, locale: locale)
            }
        }
    }

    /// One pass now, over `coordinator`'s committed snapshot (the permission UI and Settings). `nil`
    /// when the injected adapter is not a `ReminderPlatform`.
    /// Plan 08 §3.3 (L10N-03a fix): see `attach(to:account:environment:timeZone:locale:)`.
    @concurrent
    @discardableResult
    public static func reconcile(coordinator: RefreshCoordinator, environment: AccountEnvironment,
                                 timeZone: TimeZone = .current, locale: Locale = TallyLocale.effective) async -> ReminderPassOutcome? {
        guard let platform = environment.notifications as? any ReminderPlatform else { return nil }
        return await pass(coordinator, account: nil, platform: platform, environment: environment,
                          timeZone: timeZone, locale: locale)
    }

    /// Waits for every pass queued before this call. Sign-out calls it once the coordinator is retired.
    @concurrent
    public static func drain() async {
        await passes.drain()
    }

    /// One pass, queued behind every earlier one. `account`, when given, must be the snapshot's.
    @concurrent
    @discardableResult
    static func pass(_ coordinator: RefreshCoordinator?, account: AccountKey?, platform: any ReminderPlatform,
                     environment: AccountEnvironment, timeZone: TimeZone, locale: Locale) async -> ReminderPassOutcome {
        await passes.run {
            await run(coordinator, account: account, platform: platform, environment: environment,
                      format: ReminderTimeFormat(timeZone: timeZone, locale: locale))
        }
    }

    private static func run(_ coordinator: RefreshCoordinator?, account: AccountKey?, platform: any ReminderPlatform,
                            environment: AccountEnvironment, format: ReminderTimeFormat) async -> ReminderPassOutcome {
        guard await platform.permission() == .authorized else { return .notAuthorized }
        guard let snapshot = await coordinator?.committedSnapshot else { return .noSnapshot }
        let accountKey = snapshot.accountKey
        guard account == nil || account == accountKey, let root = try? environment.storeRoot() else { return .storeUnavailable }

        let sealer = environment.sealer(for: accountKey)
        let ledgerStore = SyncLedgerStore(root: root, accountKey: accountKey, sealer: sealer)
        var ledger: SyncLedger
        switch await ledgerStore.load() {
        case .loaded(let loaded): ledger = loaded
        case .absent, .unavailable(.discardAndRebuild): ledger = SyncLedger() // rederivable: rebuild from the platform
        case .unavailable: return .storeUnavailable
        }
        // Read only (never the owner: a pass must not delete a user-state file it cannot read). When
        // it cannot be read, course names are hidden: the student may have turned them off.
        // The done marks too (M3-C O2): an unreadable state keeps every reminder (none marked).
        // XG-04 O1 (plan 08 G-3): the student's "grades kept outside Canvas" answers, so the
        // priority's course modifiers classify each course as the Dashboard does; with no readable
        // state every course is Automatic, as on a fresh install.
        let hideCourseNames: Bool
        let doneAssignments: Set<CanvasID<Assignment>>
        let gradeAvailabilityOverrides: [CanvasID<Course>: GradeAvailabilityOverride]
        switch await UserStateStore(root: root, accountKey: accountKey, sealer: sealer, isOwner: false).load() {
        case .loaded(let state):
            hideCourseNames = state.hideCourseNamesInNotifications
            doneAssignments = state.doneAssignments
            gradeAvailabilityOverrides = state.gradeAvailabilityOverrides
        case .absent:
            hideCourseNames = UserState().hideCourseNamesInNotifications
            doneAssignments = []
            gradeAvailabilityOverrides = [:]
        case .unavailable:
            hideCourseNames = true
            doneAssignments = []
            gradeAvailabilityOverrides = [:]
        }

        let now = environment.clock.now()
        let subjects = ReminderSubjects(snapshot: snapshot, now: now, doneAssignments: doneAssignments,
                                        gradeAvailabilityOverrides: gradeAvailabilityOverrides)
        var refresh = RefreshRecord()
        refresh.succeeded(dataFetchedAt: snapshot.fetchedAt)
        // PAY-07 (M3-B1): on a lapse (the gate says no) the pass plans nothing, so the reconcile below
        // withdraws every pending Tally reminder of the account: the ledger's and the platform's.
        let remindersAllowed = await environment.entitlement.allows(.reminders)
        let plan = !remindersAllowed ? [] : ReminderPlanner.plan(
            accountKey: accountKey, candidates: subjects.candidates,
            settings: ReminderSettings(preset: .balanced, hideCourseNames: hideCourseNames),
            now: now, timeZone: format.timeZone, refresh: refresh)
        var desired: [PendingReminder] = []
        var contents: [String: NotificationContent.Rendered] = [:]
        for reminder in plan {
            // Never in the past. Defence in depth: before PR #8 the planner kept its reserved
            // reminders whatever their date, so a pass over a cache more than a day old planned the
            // stale-data warning in the past, which the adapter would post a second later (M3-C
            // report, planner finding P-1, fixed in TallyCore by the PMO).
            guard reminder.fireDate > now,
                  let content = subjects.content(for: reminder, accountKey: accountKey, hideCourseNames: hideCourseNames,
                                                 lastSuccess: refresh.lastSuccessAt, format: format) else { continue }
            desired.append(reminder)
            contents[reminder.id] = content
        }

        // Same identifier, different words: forget that it was scheduled, so it is scheduled again.
        let pending = await platform.pendingContents()
        for (id, content) in contents where pending[id].map({ $0 != content }) ?? false {
            ledger.notifications[id] = nil
        }

        await platform.registerCategories()
        let scheduler = ContentBoundScheduler(platform: platform, contents: contents)
        let reconciled = await NotificationReconciler.reconcile(desired: desired, ledger: ledger, platform: scheduler)
        do {
            try await ledgerStore.save(reconciled)
        } catch {
            // The platform already holds the plan; the next pass rebuilds the ledger from it.
        }
        guard remindersAllowed else { return .withdrawn(cancelled: scheduler.cancelledCount) }
        return .reconciled(scheduled: scheduler.scheduledCount, cancelled: scheduler.cancelledCount)
    }
}

/// Runs one piece of work at a time, in the order it was queued.
actor ReminderPassQueue {
    private var tail: Task<Void, Never>?

    func run<T: Sendable>(_ work: @escaping @Sendable () async -> T) async -> T {
        let previous = tail
        let task = Task<T, Never> {
            await previous?.value
            return await work()
        }
        tail = Task { _ = await task.value }
        return await task.value
    }

    func drain() async {
        await tail?.value
    }
}

/// `NotificationReconciler`'s view of the platform for one pass: each `schedule` carries the text
/// this pass resolved for that reminder, and every add and removal is counted.
nonisolated final class ContentBoundScheduler: NotificationScheduling {
    private let platform: any ReminderPlatform
    private let contents: [String: NotificationContent.Rendered]
    private let counts = Mutex((scheduled: 0, cancelled: 0))

    init(platform: any ReminderPlatform, contents: [String: NotificationContent.Rendered]) {
        self.platform = platform
        self.contents = contents
    }

    var scheduledCount: Int { counts.withLock { $0.scheduled } }
    var cancelledCount: Int { counts.withLock { $0.cancelled } }

    func pendingIdentifiers() async -> Set<String> {
        await platform.pendingIdentifiers()
    }

    func schedule(_ reminder: PendingReminder) async {
        // The pipeline only ever desires reminders it resolved text for.
        guard let content = contents[reminder.id] else { return }
        counts.withLock { $0.scheduled += 1 }
        await platform.schedule(reminder, content: content)
    }

    func cancel(ids: Set<String>) async {
        counts.withLock { $0.cancelled += ids.count }
        await platform.cancel(ids: ids)
    }
}
