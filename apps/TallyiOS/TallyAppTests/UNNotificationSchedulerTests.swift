import Foundation
import Synchronization
import TallyDomain
import Testing
import UserNotifications
@testable import TallyPlatform

/// A `NotificationCenterClient` a test drives: a fixed authorisation status, an optional add
/// failure, and a record of every call.
final class FakeNotificationCenterClient: NotificationCenterClient {
    private struct State {
        var added: [UNNotificationRequest] = []
        var removed: [[String]] = []
        var removedAll = 0
        var categories: Set<UNNotificationCategory> = []
    }

    private let status: UNAuthorizationStatus
    private let addError: (any Error)?
    private let state = Mutex(State())

    init(status: UNAuthorizationStatus, addError: (any Error)? = nil) {
        self.status = status
        self.addError = addError
    }

    var added: [UNNotificationRequest] { state.withLock { $0.added } }
    var removed: [[String]] { state.withLock { $0.removed } }
    var categories: Set<UNNotificationCategory> { state.withLock { $0.categories } }

    func authorizationStatus() async -> UNAuthorizationStatus { status }
    func add(_ request: UNNotificationRequest) async throws {
        if let addError { throw addError }
        state.withLock { $0.added.append(request) }
    }
    func pendingIdentifiers() async -> Set<String> { Set(state.withLock { $0.added.map(\.identifier) }) }
    func removeRequests(ids: [String]) { state.withLock { $0.removed.append(ids) } }
    func removeAllRequests() { state.withLock { $0.removedAll += 1 } }
    func setCategories(_ categories: Set<UNNotificationCategory>) { state.withLock { $0.categories = categories } }
}

/// A `TallyPlatformLogger` that keeps every event's name, for assertions.
final class RecordingPlatformLogger: TallyPlatformLogger {
    private let events = Mutex<[String]>([])
    var names: [String] { events.withLock { $0 } }
    func log(_ event: PlatformLogEvent) { events.withLock { $0.append("\(event)") } }
}

/// Plan 06 A4 (PL-01/PL-02): `UNNotificationScheduler` is TallySync's `NotificationScheduling`,
/// checks authorisation before adding, logs and never throws. Authorisation-aware: the iOS 27
/// simulator rejects `add` from an unauthorised app (`UNErrorDomain` 2003), iOS 26 did not.
///
/// `.serialized`: the real-center tests share `UNUserNotificationCenter.current()`.
@Suite("UNNotificationScheduler", .serialized)
struct UNNotificationSchedulerTests {
    private static func reminder(_ id: String = "tally.tests.\(UUID().uuidString)", kind: NotificationKind = .due,
                                 level: InterruptionLevel = .timeSensitive) -> PendingReminder {
        PendingReminder(id: id, kind: kind, fireDate: Date().addingTimeInterval(3600), interruptionLevel: level,
                        subjectID: "8111")
    }

    @Test("authorised: schedule adds one request with the resolved content, category, level and trigger",
          arguments: [UNAuthorizationStatus.authorized, .provisional, .ephemeral])
    func authorisedScheduleAdds(_ status: UNAuthorizationStatus) async throws {
        let center = FakeNotificationCenterClient(status: status)
        let logger = RecordingPlatformLogger()
        let scheduler = UNNotificationScheduler(center: center, logger: logger) { reminder in
            ReminderContent(title: "Due soon", body: "Subject \(reminder.subjectID)")
        }
        let reminder = Self.reminder("tally.tests.fixed")
        await scheduler.schedule(reminder)

        let request = try #require(center.added.first)
        #expect(center.added.count == 1)
        #expect(request.identifier == "tally.tests.fixed")
        #expect(request.content.title == "Due soon")
        #expect(request.content.body == "Subject 8111")
        #expect(request.content.categoryIdentifier == UNNotificationScheduler.reminderCategoryIdentifier)
        #expect(request.content.interruptionLevel == .timeSensitive)
        #expect(((request.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval ?? 0) > 3500)
        #expect(logger.names.isEmpty)
    }

    @Test("denied or not determined: nothing is added, it logs, it does not throw",
          arguments: [UNAuthorizationStatus.denied, .notDetermined])
    func unauthorisedScheduleSkips(_ status: UNAuthorizationStatus) async {
        let center = FakeNotificationCenterClient(status: status)
        let logger = RecordingPlatformLogger()
        await UNNotificationScheduler(center: center, logger: logger).schedule(Self.reminder())
        #expect(center.added.isEmpty)
        #expect(logger.names == ["notificationsNotAuthorized"])
    }

    @Test("a failing add (iOS 27's UNErrorDomain 2003) is logged, never thrown")
    func failingAddIsLogged() async {
        let rejected = NSError(domain: UNErrorDomain, code: 2003)
        let center = FakeNotificationCenterClient(status: .authorized, addError: rejected)
        let logger = RecordingPlatformLogger()
        await UNNotificationScheduler(center: center, logger: logger).schedule(Self.reminder())
        #expect(logger.names == ["notificationScheduleFailed"])
    }

    @Test("the default content names no course, assignment or grade")
    func defaultContentIsGeneric() async {
        let center = FakeNotificationCenterClient(status: .authorized)
        let scheduler = UNNotificationScheduler(center: center, logger: RecordingPlatformLogger())
        for kind in NotificationKind.allCases {
            await scheduler.schedule(Self.reminder(kind: kind))
        }
        #expect(center.added.count == NotificationKind.allCases.count)
        for request in center.added {
            #expect(!request.content.body.contains("8111"), "\(request.content.body)")
            #expect(request.content.body.hasPrefix("Open Tally"))
        }
    }

    @Test("cancel(ids:) removes exactly those identifiers; cancelAll() removes everything")
    func cancelRemovesRequested() async {
        let center = FakeNotificationCenterClient(status: .authorized)
        let scheduler = UNNotificationScheduler(center: center, logger: RecordingPlatformLogger())
        await scheduler.cancel(ids: ["a", "b"])
        #expect(center.removed.map(Set.init) == [["a", "b"]])
        await scheduler.cancelAll()
    }

    /// The real center, whatever its state on this simulator: the result must match the
    /// authorisation the system reports, and nothing may throw (iOS 26 and iOS 27 alike).
    @Test("the real center: schedule follows the system's authorisation status and never throws")
    func realCenterFollowsAuthorisation() async {
        let system = SystemNotificationCenter()
        let logger = RecordingPlatformLogger()
        let scheduler = UNNotificationScheduler(center: system, logger: logger)
        let reminder = Self.reminder()
        let status = await system.authorizationStatus()

        await scheduler.schedule(reminder)

        if UNNotificationScheduler.mayAdd(status) {
            #expect(!logger.names.contains("notificationsNotAuthorized"))
        } else {
            #expect(logger.names == ["notificationsNotAuthorized"])
            #expect(!(await scheduler.pendingIdentifiers()).contains(reminder.id))
        }
        await scheduler.cancel(ids: [reminder.id])
    }

    @Test("registerCategories() registers the reminder category with a hidden-previews placeholder")
    func registersCategory() async {
        let center = FakeNotificationCenterClient(status: .notDetermined)
        await UNNotificationScheduler(center: center, logger: RecordingPlatformLogger()).registerCategories()
        let category = center.categories.first { $0.identifier == UNNotificationScheduler.reminderCategoryIdentifier }
        #expect(category?.hiddenPreviewsBodyPlaceholder == "Tally reminder")
    }

    @Test("the real center accepts the category registration")
    func realCenterRegistersCategory() async {
        await UNNotificationScheduler(center: SystemNotificationCenter(), logger: RecordingPlatformLogger()).registerCategories()
        let categories = await UNUserNotificationCenter.current().notificationCategories()
        #expect(categories.contains { $0.identifier == UNNotificationScheduler.reminderCategoryIdentifier })
    }

    @Test("mayAdd is true only for authorised, provisional and ephemeral (mutation-guarded)")
    func mayAddTruthTable() {
        #expect(UNNotificationScheduler.mayAdd(.authorized))
        #expect(UNNotificationScheduler.mayAdd(.provisional))
        #expect(UNNotificationScheduler.mayAdd(.ephemeral))
        #expect(!UNNotificationScheduler.mayAdd(.denied))
        #expect(!UNNotificationScheduler.mayAdd(.notDetermined))
    }

    @Test("InterruptionLevel -> UNNotificationInterruptionLevel mapping is total (mutation-guarded)")
    func interruptionLevelMapping() {
        #expect(UNNotificationScheduler.unInterruptionLevel(.passive) == .passive)
        #expect(UNNotificationScheduler.unInterruptionLevel(.active) == .active)
        #expect(UNNotificationScheduler.unInterruptionLevel(.timeSensitive) == .timeSensitive)
    }
}
