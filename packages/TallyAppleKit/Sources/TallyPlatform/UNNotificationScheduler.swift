import Foundation
import TallyDomain
import TallyFeatures
// ideas2 report #4: FocusFilterCriteria, to set each notification's Focus-filter criteria.
import TallyIntents
import TallyStrings
import TallySync
import UserNotifications

/// The slice of `UNUserNotificationCenter` that `UNNotificationScheduler` uses (plan 06 A4), so
/// tests can drive each authorisation state and observe what would be added.
public protocol NotificationCenterClient: Sendable {
    func authorizationStatus() async -> UNAuthorizationStatus
    /// Shows the system permission alert when the permission is not yet determined (M3-C: only ever
    /// reached from a student's tap, `ReminderPlatform.requestPermission()`).
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func pendingIdentifiers() async -> Set<String>
    /// Every pending request's identifier, title and body (M3-C: a reminder whose words changed is
    /// scheduled again).
    func pendingContents() async -> [String: ReminderContent]
    func removeRequests(ids: [String])
    func removeAllRequests()
    func setCategories(_ categories: Set<UNNotificationCategory>)
}

/// The real center. `@unchecked Sendable`: `UNUserNotificationCenter` predates Swift
/// concurrency's `Sendable` annotations, but Apple documents it as safe to use from any thread
/// (CI run 36334644286 showed the build fails without this).
public struct SystemNotificationCenter: NotificationCenterClient, @unchecked Sendable {
    private let center: UNUserNotificationCenter

    public init(_ center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    public func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await center.requestAuthorization(options: options)
    }

    public func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    public func pendingIdentifiers() async -> Set<String> {
        Set(await center.pendingNotificationRequests().map(\.identifier))
    }

    public func pendingContents() async -> [String: ReminderContent] {
        let requests = await center.pendingNotificationRequests()
        return Dictionary(requests.map { ($0.identifier, ReminderContent(title: $0.content.title, body: $0.content.body)) },
                          uniquingKeysWith: { first, _ in first })
    }

    public func removeRequests(ids: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    public func removeAllRequests() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    public func setCategories(_ categories: Set<UNNotificationCategory>) {
        center.setNotificationCategories(categories)
    }
}

/// What a reminder says. `PendingReminder` carries only a kind and a subject ID; the app layer
/// resolves display text from the current snapshot and injects that resolver.
public struct ReminderContent: Sendable, Equatable {
    public let title: String
    public let body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }

    /// Text that names no course, assignment or grade: the default until the app injects its
    /// snapshot-backed resolver (security.md §3.3: never student content on the Lock Screen by
    /// default).
    public static func generic(for kind: NotificationKind) -> ReminderContent {
        switch kind {
        case .due:
            ReminderContent(title: String(localized: L10n.Notifications.dueTitle()),
                            body: String(localized: L10n.Notifications.dueBody()))
        case .followup:
            ReminderContent(title: String(localized: L10n.Notifications.followupTitle()),
                            body: String(localized: L10n.Notifications.followupBody()))
        case .exam:
            ReminderContent(title: String(localized: L10n.Notifications.examTitle()),
                            body: String(localized: L10n.Notifications.examBody()))
        case .digest:
            ReminderContent(title: String(localized: L10n.Notifications.digestTitle()),
                            body: String(localized: L10n.Notifications.digestBody()))
        case .weekAhead:
            ReminderContent(title: String(localized: L10n.Notifications.weekAheadTitle()),
                            body: String(localized: L10n.Notifications.weekAheadBody()))
        case .gradePosted:
            ReminderContent(title: String(localized: L10n.Notifications.gradePostedTitle()),
                            body: String(localized: L10n.Notifications.gradePostedBody()))
        case .belowGoal:
            ReminderContent(title: String(localized: L10n.Notifications.belowGoalTitle()),
                            body: String(localized: L10n.Notifications.belowGoalBody()))
        case .sentinel:
            ReminderContent(title: String(localized: L10n.Notifications.sentinelTitle()),
                            body: String(localized: L10n.Notifications.sentinelBody()))
        case .adHoc:
            ReminderContent(title: String(localized: L10n.Notifications.adHocTitle()),
                            body: String(localized: L10n.Notifications.adHocBody()))
        case .renewalReminder:
            ReminderContent(title: String(localized: L10n.Notifications.renewalReminderTitle()),
                            body: String(localized: L10n.Notifications.renewalReminderBody()))
        }
    }

    /// EB-20b: the renewal reminder's rich content, once `SubscriptionEngine` has a verified
    /// renewal date to schedule with (`defaultContent(_:)` below decodes it). `displayPrice` is
    /// the one named place to add StoreKit's own formatted amount later: counsel's Q37 is open, so
    /// it is always `nil` today and never read.
    public static func renewalReminder(planName: String, renewalDate: Date, displayPrice: String? = nil) -> ReminderContent {
        let date = renewalDate.formatted(date: .abbreviated, time: .omitted)
        return ReminderContent(
            title: String(localized: L10n.Notifications.renewalReminderRichTitle(plan: planName, date: date)),
            body: String(localized: L10n.Notifications.renewalReminderRichBody()))
    }
}

/// `UNUserNotificationCenter`-backed conformance to TallySync's `NotificationScheduling`, the port
/// `NotificationReconciler` drives (plan 06 A4, PL-01/PL-02).
///
/// It checks authorisation before every `schedule`: when notifications are denied or not yet
/// determined it adds nothing, logs `.notificationsNotAuthorized`, and returns. The iOS 27
/// simulator rejects `add` from an unauthorised app with `UNErrorDomain` 2003 ("Source is not
/// authorized", run 36355787178), which iOS 26 accepted silently. Any other failure to add is
/// logged as `.notificationScheduleFailed`. It never throws, as the port requires.
public struct UNNotificationScheduler: NotificationScheduling {
    /// The one category every Tally-originated notification uses.
    /// `hiddenPreviewsBodyPlaceholder` (WP5): when the user has "Show
    /// Previews" off, or the notification arrives on a locked device, the
    /// system shows this instead of `body` — never a course or assignment
    /// name (security.md §3.3's Lock Screen control).
    public static let reminderCategoryIdentifier = "TALLY_REMINDER"

    private let center: any NotificationCenterClient
    private let logger: any TallyPlatformLogger
    private let content: @Sendable (PendingReminder) -> ReminderContent

    public init(
        center: any NotificationCenterClient = SystemNotificationCenter(),
        logger: any TallyPlatformLogger = OSLogPlatformLogger(),
        content: @escaping @Sendable (PendingReminder) -> ReminderContent = UNNotificationScheduler.defaultContent
    ) {
        self.center = center
        self.logger = logger
        self.content = content
    }

    /// EB-20b: every production call site's content resolver (the default above): generic for
    /// every kind except `.renewalReminder`, which gets the plan name and the renewal date once
    /// `subjectID` decodes to one (`SubscriptionEngine.reconcileRenewalReminders` encodes it as a
    /// Unix timestamp); generic otherwise, so a malformed or pre-EB-20b value never shows a wrong
    /// date — it shows nothing date-specific at all.
    public static func defaultContent(_ reminder: PendingReminder) -> ReminderContent {
        guard reminder.kind == .renewalReminder, let renewalDate = renewalDate(from: reminder.subjectID) else {
            return ReminderContent.generic(for: reminder.kind)
        }
        return ReminderContent.renewalReminder(planName: String(localized: L10n.Subscription.name()), renewalDate: renewalDate)
    }

    /// Decodes the renewal date `SubscriptionEngine` encodes into `PendingReminder.subjectID` for
    /// `.renewalReminder` alone (a Unix timestamp string). `nil` for anything unparseable, so the
    /// caller falls back to the generic key rather than trap or misread.
    static func renewalDate(from subjectID: String) -> Date? {
        guard let seconds = TimeInterval(subjectID) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// Registers the categories every Tally notification needs (`hiddenPreviewsBodyPlaceholder`;
    /// WP5). Idempotent: call again after every launch.
    public func registerCategories() async {
        let category = UNNotificationCategory(
            identifier: Self.reminderCategoryIdentifier,
            actions: [],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: String(localized: L10n.Notifications.hiddenPreviewPlaceholder()),
            options: [])
        center.setCategories([category])
        logger.log(.notificationCategoriesRegistered(count: 1))
    }

    public func pendingIdentifiers() async -> Set<String> {
        await center.pendingIdentifiers()
    }

    public func schedule(_ reminder: PendingReminder) async {
        await schedule(reminder, text: content(reminder))
    }

    /// `courseID` (ideas2 report #4): the reminder's course, `nil` for the generic fallback
    /// content (no snapshot to resolve a course from) and for an account-level reminder.
    private func schedule(_ reminder: PendingReminder, text: ReminderContent, courseID: String? = nil) async {
        guard Self.mayAdd(await center.authorizationStatus()) else {
            logger.log(.notificationsNotAuthorized)
            return
        }
        let criteria = FocusFilterCriteria.criteria(courseID: courseID, level: Self.focusLevel(for: reminder))
        let request = Self.request(id: reminder.id, title: text.title, body: text.body,
                                   interruptionLevel: reminder.interruptionLevel, fireDate: reminder.fireDate,
                                   filterCriteria: criteria)
        do {
            try await center.add(request)
        } catch {
            logger.log(.notificationScheduleFailed)
        }
    }

    /// ideas2 report #4: maps a reminder's existing kind and interruption level (no new data) to
    /// the Focus filter's severity (`FocusFilterCriteria.Level`, `urgentLevels == [.critical,
    /// .high]`). A Time Sensitive reminder is always critical; an exam reminder counts as urgent
    /// even before it reaches Time Sensitive (T-3d/T-1d), since an exam matters more than a
    /// routine due-date nudge at the same interruption level.
    static func focusLevel(for reminder: PendingReminder) -> FocusFilterCriteria.Level {
        switch reminder.interruptionLevel {
        case .timeSensitive: .critical
        case .active: reminder.kind == .exam ? .high : .medium
        case .passive: .info
        }
    }

    public func cancel(ids: Set<String>) async {
        center.removeRequests(ids: Array(ids))
    }

    public func cancelAll() async {
        center.removeAllRequests()
    }

    /// The options "Turn On Reminders" asks for (ux-ui.md §3.2 stage 6: `[.alert, .sound, .badge]`).
    static let requestedOptions: UNAuthorizationOptions = [.alert, .sound, .badge]

    /// The system's status in `ReminderPermission`'s words: exactly the statuses `mayAdd` allows
    /// are `.authorized`.
    static func permission(_ status: UNAuthorizationStatus) -> ReminderPermission {
        switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized, .provisional, .ephemeral: .authorized
        @unknown default: .denied
        }
    }

    /// Only an app the user let post notifications may add one (provisional and ephemeral
    /// authorisation deliver quietly, so they count).
    static func mayAdd(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral: true
        case .denied, .notDetermined: false
        @unknown default: false
        }
    }

    /// Pure content/trigger construction, split out of `schedule` so it is
    /// directly testable without depending on notification authorization.
    ///
    /// `filterCriteria` (ideas2 report #4): a Focus filter (`TallyFocusFilter`,
    /// `FocusFilterCriteria.predicate(courseIDs:onlyUrgent:)`) silences a notification only when
    /// it carries criteria that fail that predicate; one with none (`nil`) always gets through.
    /// `FocusFilterCriteria.criteria(courseID:level:)` never returns `nil`, so every reminder this
    /// scheduler adds now actually participates in a Focus filter the student has configured,
    /// where before none did.
    static func request(
        id: String, title: String, body: String, interruptionLevel: InterruptionLevel, fireDate: Date,
        filterCriteria: String? = nil
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = reminderCategoryIdentifier
        content.interruptionLevel = unInterruptionLevel(interruptionLevel)
        content.filterCriteria = filterCriteria

        let interval = max(1, fireDate.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    static func unInterruptionLevel(_ level: InterruptionLevel) -> UNNotificationInterruptionLevel {
        switch level {
        case .passive: return .passive
        case .active: return .active
        case .timeSensitive: return .timeSensitive
        }
    }
}

/// M3-C (E07, UX-WP-12): the reminders pipeline's and permission UI's port (`TallyFeatures`). The
/// composition root already injects this adapter as `AccountEnvironment.notifications`, so the
/// pipeline finds it there.
extension UNNotificationScheduler: ReminderPlatform {
    /// Reads the status; never shows a prompt.
    public func permission() async -> ReminderPermission {
        Self.permission(await center.authorizationStatus())
    }

    /// The system alert, the first time; afterwards iOS answers from its setting without asking.
    /// Only a student's tap reaches this (the Dashboard tip, or Settings).
    public func requestPermission() async -> ReminderPermission {
        do {
            _ = try await center.requestAuthorization(options: Self.requestedOptions)
        } catch {
            logger.log(.notificationsNotAuthorized)
        }
        return await permission()
    }

    public func schedule(_ reminder: PendingReminder, content: NotificationContent.Rendered) async {
        await schedule(reminder, text: ReminderContent(title: content.title, body: content.body), courseID: content.courseID)
    }

    public func pendingContents() async -> [String: NotificationContent.Rendered] {
        await center.pendingContents().mapValues { NotificationContent.Rendered(title: $0.title, body: $0.body) }
    }
}
