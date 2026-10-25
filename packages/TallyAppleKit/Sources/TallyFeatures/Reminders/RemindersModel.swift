import Foundation
import Observation
import TallyDomain

/// UX-WP-12: when the Dashboard's reminders tip shows, and what Settings' Reminders section says.
/// Pure, so every rule is a plain unit test.
public nonisolated enum ReminderTipPolicy {
    /// The tip shows only on a signed-in account (never sample data: nothing is scheduled for it),
    /// only while the permission has never been asked (a tap can then show the system alert; after
    /// a "no", only iOS Settings can change it, and Settings says so), only once there is work due
    /// (ux-ui.md §3.2 stage 6: "only if there are upcoming due items"), and not within
    /// `RemindersConfig.tipSnooze` of being dismissed.
    public static func showsTip(isSampleData: Bool, permission: ReminderPermission?, hasUpcomingDueItem: Bool,
                                isSnoozed: Bool) -> Bool {
        !isSampleData && permission == .notDetermined && hasUpcomingDueItem && !isSnoozed
    }

    /// Whether a tip dismissed at `dismissedAt` is still away at `now`.
    public static func isSnoozed(dismissedAt: Date?, now: Date) -> Bool {
        guard let dismissedAt else { return false }
        return now < dismissedAt.addingTimeInterval(RemindersConfig.tipSnooze.timeInterval)
    }

    /// Settings' Reminders status.
    public enum Status: Sendable, Equatable {
        /// Sample data: reminders are never scheduled for it, and permission is never asked.
        case sampleData
        /// The permission has not been read yet.
        case checking
        case off
        /// "Notifications are off for Tally", with Open Settings.
        case deniedInSettings
        case on
    }

    public static func status(isSampleData: Bool, permission: ReminderPermission?) -> Status {
        if isSampleData { return .sampleData }
        switch permission {
        case nil: return .checking
        case .notDetermined: return .off
        case .denied: return .deniedInSettings
        case .authorized: return .on
        }
    }
}

/// EB-20b: when a renewal-reminder banner shows -- shared by Settings > Subscription's own banner
/// (`SubscriptionSettingsView`) and the Home's copy of it (`RenewalReminderHomeBanner`), so the
/// one rule lives in one place. Shown only while a reminder is actually due
/// (`SubscriptionModel.hasUpcomingRenewalReminder`) and notifications are not authorized yet
/// (never asked, or denied) -- never once allowed, and never for nothing (no subscription,
/// auto-renew off, or a school seat, all of which make `hasUpcomingRenewalReminder` false).
public nonisolated enum RenewalReminderBannerPolicy {
    public static func permission(hasUpcomingRenewalReminder: Bool, permission: ReminderPermission?) -> ReminderPermission? {
        guard hasUpcomingRenewalReminder else { return nil }
        guard permission == .notDetermined || permission == .denied else { return nil }
        return permission
    }
}

/// The reminders permission, asked in context (UX-WP-12, A11Y-11): never at launch, only when the
/// student taps "Turn On Reminders" on the Dashboard tip or in Settings. iOS's permission is the
/// on/off switch; turning it on runs a reminders pass at once, so the student's reminders exist before
/// the next refresh.
///
/// The tip's dismissal lasts `RemindersConfig.tipSnooze`. A signed-in account keeps it in its
/// `UserState` (`reminderTipDismissedUntil`, M3-C O1), so it outlives a relaunch.
@MainActor
@Observable
public final class RemindersModel {
    /// Explicit and nonisolated (plan 06 A2; swiftlang/swift#88036).
    nonisolated deinit {}

    /// `nil` until first read (`refreshPermission()`), and always without a platform.
    public private(set) var permission: ReminderPermission?
    /// A request is on screen (the system alert); the buttons wait.
    public private(set) var isRequesting = false
    public private(set) var isTipSnoozed = false

    @ObservationIgnored private var tipDismissedAt: Date?
    /// Where the tip's dismissal is kept (M3-C O1): the signed-in account's `UserState`, set by
    /// `AppModel` with the signed-in Home; `nil` (this session only) in sample mode and on Welcome.
    @ObservationIgnored public var tipDismissalStore: (any ReminderTipDismissalStoring)?
    private let tipSave = TaskBox()
    private let platform: (any ReminderPlatform)?
    private let clock: any DateProviding
    private let reconcile: @Sendable () async -> Void
    private let request = TaskBox()
    private let reconciling = TaskBox()

    /// - Parameters:
    ///   - platform: the notification adapter; `nil` in tests and previews without one (then the
    ///     permission stays unknown and nothing is shown or asked).
    ///   - reconcile: one reminders pass for the signed-in account (`AppModel` builds it).
    public init(platform: (any ReminderPlatform)?, clock: any DateProviding = SystemDateProvider(),
                reconcile: @escaping @Sendable () async -> Void = {}) {
        self.platform = platform
        self.clock = clock
        self.reconcile = reconcile
    }

    public func showsTip(isSampleData: Bool, hasUpcomingDueItem: Bool) -> Bool {
        ReminderTipPolicy.showsTip(isSampleData: isSampleData, permission: permission,
                                   hasUpcomingDueItem: hasUpcomingDueItem, isSnoozed: isTipSnoozed)
    }

    public func status(isSampleData: Bool) -> ReminderTipPolicy.Status {
        ReminderTipPolicy.status(isSampleData: isSampleData, permission: permission)
    }

    /// Reads the permission again (the tip and Settings appearing, the app becoming active: the
    /// student may have changed it in iOS Settings). Never asks.
    public func refreshPermission() async {
        if let store = tipDismissalStore, let until = await store.dismissedUntil() {
            tipDismissedAt = until.addingTimeInterval(-RemindersConfig.tipSnooze.timeInterval)
        }
        isTipSnoozed = ReminderTipPolicy.isSnoozed(dismissedAt: tipDismissedAt, now: clock.now())
        guard let platform else { return }
        apply(await platform.permission())
    }

    /// "Turn On Reminders": asks iOS (the system alert, the first time). Only a tap calls this.
    public func requestPermission() {
        guard let platform, !isRequesting else { return }
        isRequesting = true
        request.replace(with: Task { [weak self] in
            let answer = await platform.requestPermission()
            guard let self else { return }
            isRequesting = false
            apply(answer, reconcilesWhenAuthorized: true)
        })
    }

    /// The tip's dismiss: away for `RemindersConfig.tipSnooze` (this session).
    public func dismissTip() {
        let now = clock.now()
        tipDismissedAt = now
        isTipSnoozed = true
        guard let store = tipDismissalStore else { return }
        let until = now.addingTimeInterval(RemindersConfig.tipSnooze.timeInterval)
        tipSave.replace(with: Task { await store.setDismissedUntil(until) })
    }

    /// Waits for the latest dismissal save (tests).
    func awaitTipSaved() async {
        await tipSave.value()
    }

    /// One reminders pass now (Settings, after "Hide Course Names" is saved).
    public func reconcileNow() {
        let reconcile = reconcile
        reconciling.replace(with: Task { await reconcile() })
    }

    /// A newly allowed permission (from "not asked" or "denied") schedules the reminders at once, as
    /// does a request the student just granted. The first read at launch does not: the launch's own
    /// pass has that covered.
    private func apply(_ newPermission: ReminderPermission, reconcilesWhenAuthorized: Bool = false) {
        let becameAuthorized = newPermission == .authorized
            && (reconcilesWhenAuthorized || (permission != nil && permission != .authorized))
        if permission != newPermission { permission = newPermission }
        if becameAuthorized { reconcileNow() }
    }

    /// Tests: the request and the pass in flight, awaited.
    func awaitWork() async {
        await request.value()
        await reconciling.value()
    }
}
