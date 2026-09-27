import Foundation
import TallyDomain
import UserNotifications

/// The reminder port this adapter conforms to. `NotificationScheduling` has
/// not landed in `packages/TallyCore` on this branch (checked: no such
/// protocol exists anywhere under `packages/TallyCore/Sources` as of this
/// commit) — per the platform-adapters brief, it is defined locally here
/// rather than edited into the read-only `TallyCore` package. Flagged for
/// the PMO: once the sync team's `NotificationReconciler` port merges, this
/// protocol should move to (or be reconciled with) whatever shape
/// `TallyCore` settles on, and this adapter's conformance should follow.
///
/// Kept Foundation/`TallyDomain`-only in its own signature on purpose
/// (`InterruptionLevel` is already string-free and UIKit-free in
/// `TallyDomain/Reminders/ReminderTypes.swift`) even though its
/// *implementation* is necessarily UserNotifications-only, matching the
/// spirit of the other ports (`HTTPTransport`, `CredentialStore`, ...).
public protocol NotificationScheduling: Sendable {
    /// Registers the categories every Tally notification needs
    /// (`hiddenPreviewsBodyPlaceholder`; WP5). Idempotent — call again after
    /// every launch, it just re-registers the same set.
    func registerCategories() async

    /// Every currently pending Tally request's identifier, for the
    /// reconciler's diff-against-desired-set step (architecture.md §3.4
    /// post-commit pipeline step 2).
    func pendingIdentifiers() async -> Set<String>

    /// Schedules (or replaces) one local notification.
    func schedule(id: String, title: String, body: String, interruptionLevel: InterruptionLevel, fireDate: Date) async throws

    func cancel(ids: Set<String>) async
    func cancelAll() async
}

/// `UNUserNotificationCenter`-backed `NotificationScheduling` adapter.
/// `@unchecked Sendable`: `UNUserNotificationCenter` itself predates Swift
/// concurrency's `Sendable` annotations, but Apple documents it as safe to
/// use from any thread (it is normally accessed via the `.current()`
/// singleton), so the struct's automatic per-member Sendable check is
/// overridden rather than the type being made non-Sendable (which would
/// conflict with `NotificationScheduling: Sendable`). Confirmed by CI
/// (run 36334644286): without this, the build fails with "stored property
/// 'center' ... has non-Sendable type 'UNUserNotificationCenter'".
public struct UNNotificationScheduler: NotificationScheduling, @unchecked Sendable {
    /// The one category every Tally-originated notification uses.
    /// `hiddenPreviewsBodyPlaceholder` (WP5): when the user has "Show
    /// Previews" off, or the notification arrives on a locked device, the
    /// system shows this instead of `body` — never a course or assignment
    /// name (security.md §3.3's Lock Screen control).
    public static let reminderCategoryIdentifier = "TALLY_REMINDER"

    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func registerCategories() async {
        let category = UNNotificationCategory(
            identifier: Self.reminderCategoryIdentifier,
            actions: [],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Tally reminder",
            options: [])
        center.setNotificationCategories([category])
    }

    public func pendingIdentifiers() async -> Set<String> {
        Set(await center.pendingNotificationRequests().map(\.identifier))
    }

    public func schedule(
        id: String, title: String, body: String, interruptionLevel: InterruptionLevel, fireDate: Date
    ) async throws {
        try await center.add(Self.request(id: id, title: title, body: body, interruptionLevel: interruptionLevel, fireDate: fireDate))
    }

    /// Pure content/trigger construction, split out of `schedule` so it is
    /// directly testable without depending on notification authorization.
    /// architecture.md's own verification legend (WP-E07) scopes the real
    /// `add`/`pendingNotificationRequests()` round trip as "macOS CI
    /// simulator; real prompts device-only" — confirmed on CI run
    /// 36335209586: a hosted hosted-test process where authorization has
    /// never been requested/determined never surfaces an added request via
    /// `pendingNotificationRequests()`, even though `add` itself does not
    /// throw. This builder is what schedule() actually hands to
    /// `UNUserNotificationCenter`, so it is the meaningful thing to assert
    /// on hosted.
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

    public func cancel(ids: Set<String>) async {
        let list = Array(ids)
        center.removePendingNotificationRequests(withIdentifiers: list)
        center.removeDeliveredNotifications(withIdentifiers: list)
    }

    public func cancelAll() async {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    static func unInterruptionLevel(_ level: InterruptionLevel) -> UNNotificationInterruptionLevel {
        switch level {
        case .passive: return .passive
        case .active: return .active
        case .timeSensitive: return .timeSensitive
        }
    }
}
