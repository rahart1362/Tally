import Foundation
import TallyDomain
import TallySync

/// The system's notification permission, in this module's words (M3-C, UX-WP-12). iOS's own
/// permission is the reminders' on/off switch: Tally has no separate setting.
public nonisolated enum ReminderPermission: Sendable, Equatable {
    /// Never asked. Only an in-context tap asks (the Dashboard tip, or Settings), never the launch.
    case notDetermined
    /// The student said no, or turned notifications off in iOS Settings: only iOS Settings can undo it.
    case denied
    /// Tally may post notifications (provisional and ephemeral authorisation count: they deliver).
    case authorized
}

/// What the reminders pipeline and the permission UI need from the platform's notification center
/// (architecture.md §3.1: "Features never import TallyPlatform; the app's composition root injects
/// adapters through protocols"). `UNNotificationScheduler` (TallyPlatform) conforms; the composition
/// root already injects it as `AccountEnvironment.notifications`.
///
/// It extends TallySync's `NotificationScheduling`, the port `NotificationReconciler` drives, with:
/// - the permission, read without asking, and the one call that asks (`requestPermission()`), which
///   only a student's tap reaches;
/// - scheduling with the text this app resolved from the snapshot (`PendingReminder` carries only a
///   kind and a subject ID);
/// - the text of what is pending, so a reminder whose words changed (a renamed assignment, or
///   "Hide Course Names" turned on) is scheduled again under the same identifier.
public nonisolated protocol ReminderPlatform: NotificationScheduling {
    /// The current permission. Never shows a prompt.
    func permission() async -> ReminderPermission
    /// Asks iOS for permission (the system alert, when not yet determined), then returns the
    /// permission that results. Only ever called from a student's tap.
    func requestPermission() async -> ReminderPermission
    /// Registers the notification categories (the hidden-previews placeholder). Idempotent.
    func registerCategories() async
    /// Schedules `reminder` with `content`, replacing any pending request with the same identifier.
    func schedule(_ reminder: PendingReminder, content: NotificationContent.Rendered) async
    /// Every pending request's identifier and text.
    func pendingContents() async -> [String: NotificationContent.Rendered]
}
