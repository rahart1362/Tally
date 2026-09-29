#if DEBUG || TALLY_TEST_HOOKS
import Foundation
import Synchronization
import TallyDomain

/// UI-test hook for the reminders permission (M3-C): `-TallyTestHooks.notifications <state>[:<answer>]`
/// replaces the permission the reminders UI reads with a scripted one, so no UI test ever reaches the
/// system permission alert. `<state>` is the permission at launch and `<answer>` what "Turn On
/// Reminders" then gets (default `authorized`); each is `notDetermined`, `denied` or `authorized`.
///
/// It scripts the UI's permission only. Scheduling still goes to the real adapter, and the pipeline
/// reads the real permission, so on a simulator that was never asked it schedules nothing.
///
/// Never in a shipping build: like `LaunchTestHooks`, this compiles only under `DEBUG` or
/// `TALLY_TEST_HOOKS`, and CI's Release gate fails if any shipping binary contains the
/// `TallyTestHooks.` argument prefix.
nonisolated enum ReminderTestHooks {
    static let key = "TallyTestHooks.notifications"

    /// The scripted permission `arguments` ask for, or `nil` when they do not use the hook.
    static func script(arguments: [String]) -> (state: ReminderPermission, answer: ReminderPermission)? {
        guard let index = arguments.firstIndex(of: "-\(key)"), arguments.index(after: index) < arguments.endIndex else {
            return nil
        }
        let parts = arguments[arguments.index(after: index)].split(separator: ":").map(String.init)
        guard let state = parts.first.flatMap(permission) else { return nil }
        let answer = parts.count > 1 ? permission(parts[1]) ?? .authorized : .authorized
        return (state, answer)
    }

    /// `platform`, or a scripted stand-in when this process was launched with the hook.
    static func platform(replacing platform: (any ReminderPlatform)?,
                         arguments: [String] = ProcessInfo.processInfo.arguments) -> (any ReminderPlatform)? {
        guard let script = script(arguments: arguments) else { return platform }
        return ScriptedPermissionPlatform(base: platform, state: script.state, answer: script.answer)
    }

    private static func permission(_ name: String) -> ReminderPermission? {
        switch name {
        case "notDetermined": .notDetermined
        case "denied": .denied
        case "authorized": .authorized
        default: nil
        }
    }
}

/// A `ReminderPlatform` whose permission is scripted: it starts at `state` and a request answers
/// `answer` without any system alert. Everything else goes to `base` (or does nothing without one).
nonisolated final class ScriptedPermissionPlatform: ReminderPlatform {
    private let base: (any ReminderPlatform)?
    private let answer: ReminderPermission
    private let state: Mutex<(permission: ReminderPermission, requests: Int)>

    init(base: (any ReminderPlatform)?, state: ReminderPermission, answer: ReminderPermission) {
        self.base = base
        self.answer = answer
        self.state = Mutex((state, 0))
    }

    var requestCount: Int { state.withLock { $0.requests } }

    func permission() async -> ReminderPermission { state.withLock { $0.permission } }

    func requestPermission() async -> ReminderPermission {
        state.withLock { state in
            state.requests += 1
            if state.permission == .notDetermined { state.permission = answer }
            return state.permission
        }
    }

    func registerCategories() async { await base?.registerCategories() }
    func schedule(_ reminder: PendingReminder, content: NotificationContent.Rendered) async {
        await base?.schedule(reminder, content: content)
    }
    func pendingContents() async -> [String: NotificationContent.Rendered] { await base?.pendingContents() ?? [:] }
    func pendingIdentifiers() async -> Set<String> { await base?.pendingIdentifiers() ?? [] }
    func schedule(_ reminder: PendingReminder) async { await base?.schedule(reminder) }
    func cancel(ids: Set<String>) async { await base?.cancel(ids: ids) }
}
#endif
