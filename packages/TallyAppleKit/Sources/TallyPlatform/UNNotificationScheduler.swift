import Foundation
import TallyDomain
import TallyFeatures
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
        case .due: ReminderContent(title: "Due soon", body: "Open Tally to see what's due.")
        case .followup: ReminderContent(title: "Still to do", body: "Open Tally to see what's left.")
        case .exam: ReminderContent(title: "Exam coming up", body: "Open Tally for the details.")
        case .digest: ReminderContent(title: "What changed", body: "Open Tally to see your updates.")
        case .weekAhead: ReminderContent(title: "Your week ahead", body: "Open Tally to plan your week.")
        case .gradePosted: ReminderContent(title: "New grade posted", body: "Open Tally to see it.")
        case .belowGoal: ReminderContent(title: "Below your goal", body: "Open Tally to see where you stand.")
        case .sentinel: ReminderContent(title: "Tally hasn't refreshed", body: "Open Tally to update your data.")
        }
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
        content: @escaping @Sendable (PendingReminder) -> ReminderContent = { ReminderContent.generic(for: $0.kind) }
    ) {
        self.center = center
        self.logger = logger
        self.content = content
    }

    /// Registers the categories every Tally notification needs (`hiddenPreviewsBodyPlaceholder`;
    /// WP5). Idempotent: call again after every launch.
    public func registerCategories() async {
        let category = UNNotificationCategory(
            identifier: Self.reminderCategoryIdentifier,
            actions: [],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Tally reminder",
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

    private func schedule(_ reminder: PendingReminder, text: ReminderContent) async {
        guard Self.mayAdd(await center.authorizationStatus()) else {
            logger.log(.notificationsNotAuthorized)
            return
        }
        let request = Self.request(id: reminder.id, title: text.title, body: text.body,
                                   interruptionLevel: reminder.interruptionLevel, fireDate: reminder.fireDate)
        do {
            try await center.add(request)
        } catch {
            logger.log(.notificationScheduleFailed)
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
    static func request(
        id: String, title: String, body: String, interruptionLevel: InterruptionLevel, fireDate: Date
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = reminderCategoryIdentifier
        content.interruptionLevel = unInterruptionLevel(interruptionLevel)

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
        await schedule(reminder, text: ReminderContent(title: content.title, body: content.body))
    }

    public func pendingContents() async -> [String: NotificationContent.Rendered] {
        await center.pendingContents().mapValues { NotificationContent.Rendered(title: $0.title, body: $0.body) }
    }
}
