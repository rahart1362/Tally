import Foundation
import Synchronization
import TallyDomain
import TallyFeatures
// ideas2 report #4: FocusFilterCriteria, to verify the notification's Focus-filter criteria.
import TallyIntents
import TallySync
import Testing
import UserNotifications
@testable import TallyPlatform

/// A `NotificationCenterClient` a test drives: an authorisation status (which a request can answer,
/// M3-C), an optional add failure, and a record of every call.
///
/// An `NSLock`, not a `Mutex`: `UNNotificationRequest` and `UNNotificationCategory` are not
/// `Sendable`, and `Mutex.withLock` only accepts values from a disconnected region, which a
/// method's own parameters are not (Swift 6 rejects `state.withLock { $0.added.append(request) }`
/// with "'inout sending' parameter '$0' cannot be task-isolated", CI run 36389673529).
/// `@unchecked Sendable`: every stored `var` is read and written only under `lock`.
final class FakeNotificationCenterClient: NotificationCenterClient, @unchecked Sendable {
    private let addError: (any Error)?
    /// What `requestAuthorization` turns a not-determined status into (M3-C); `nil` leaves it.
    private let answer: UNAuthorizationStatus?
    private let lock = NSLock()
    private var currentStatus: UNAuthorizationStatus
    private var addedRequests: [UNNotificationRequest] = []
    private var removedIDs: [[String]] = []
    private var removedAllCount = 0
    private var registeredCategories: Set<UNNotificationCategory> = []
    private var authorizationRequests: [UNAuthorizationOptions] = []

    init(status: UNAuthorizationStatus, addError: (any Error)? = nil, answer: UNAuthorizationStatus? = nil) {
        currentStatus = status
        self.addError = addError
        self.answer = answer
    }

    var added: [UNNotificationRequest] { lock.withLock { addedRequests } }
    var removed: [[String]] { lock.withLock { removedIDs } }
    var categories: Set<UNNotificationCategory> { lock.withLock { registeredCategories } }
    var requests: [UNAuthorizationOptions] { lock.withLock { authorizationRequests } }

    func authorizationStatus() async -> UNAuthorizationStatus { lock.withLock { currentStatus } }
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        lock.withLock {
            authorizationRequests.append(options)
            if currentStatus == .notDetermined, let answer { currentStatus = answer }
            return UNNotificationScheduler.mayAdd(currentStatus)
        }
    }
    func add(_ request: UNNotificationRequest) async throws {
        if let addError { throw addError }
        lock.withLock { addedRequests.append(request) }
    }
    func pendingIdentifiers() async -> Set<String> { lock.withLock { Set(addedRequests.map(\.identifier)) } }
    func pendingContents() async -> [String: ReminderContent] {
        lock.withLock {
            Dictionary(addedRequests.map { ($0.identifier, ReminderContent(title: $0.content.title, body: $0.content.body)) },
                       uniquingKeysWith: { _, last in last })
        }
    }
    func removeRequests(ids: [String]) { lock.withLock { removedIDs.append(ids) } }
    func removeAllRequests() { lock.withLock { removedAllCount += 1 } }
    func setCategories(_ categories: Set<UNNotificationCategory>) { lock.withLock { registeredCategories = categories } }
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
                                 level: InterruptionLevel = .timeSensitive, subjectID: String = "8111") -> PendingReminder {
        PendingReminder(id: id, kind: kind, fireDate: Date().addingTimeInterval(3600), interruptionLevel: level,
                        subjectID: subjectID)
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

    /// `.renewalReminder` is covered on its own below (`renewalReminderFallsBackToGenericWithoutADate`,
    /// `renewalReminderGetsRichContent`): EB-20b gives it rich content once `subjectID` decodes to
    /// a date, so it is not generic for every `subjectID` the way every other kind here is.
    @Test("the default content names no course, assignment or grade")
    func defaultContentIsGeneric() async {
        let center = FakeNotificationCenterClient(status: .authorized)
        let scheduler = UNNotificationScheduler(center: center, logger: RecordingPlatformLogger())
        let kinds = NotificationKind.allCases.filter { $0 != .renewalReminder }
        for kind in kinds {
            await scheduler.schedule(Self.reminder(kind: kind))
        }
        #expect(center.added.count == kinds.count)
        for request in center.added {
            #expect(!request.content.body.contains("8111"), "\(request.content.body)")
            #expect(request.content.body.hasPrefix("Open Tally"))
        }
    }

    // MARK: - EB-20b: the renewal reminder's rich content

    @Test("EB-20b: the renewal reminder falls back to the generic key when subjectID carries no date")
    func renewalReminderFallsBackToGenericWithoutADate() async throws {
        let center = FakeNotificationCenterClient(status: .authorized)
        let scheduler = UNNotificationScheduler(center: center, logger: RecordingPlatformLogger())
        // "-" (every other account-level reminder's own subjectID) and a pre-EB-20b reminder would
        // both fail to parse as a timestamp; either way, never a wrong date.
        await scheduler.schedule(Self.reminder(kind: .renewalReminder, subjectID: "-"))
        let request = try #require(center.added.first)
        #expect(request.content.body.hasPrefix("Open Tally"))
    }

    @Test("EB-20b: the renewal reminder gets the plan name and the renewal date once subjectID carries one, and no amount")
    func renewalReminderGetsRichContent() async throws {
        let center = FakeNotificationCenterClient(status: .authorized)
        let scheduler = UNNotificationScheduler(center: center, logger: RecordingPlatformLogger())
        let renewalDate = Date(timeIntervalSince1970: 1_800_000_000)
        await scheduler.schedule(Self.reminder(kind: .renewalReminder, subjectID: String(renewalDate.timeIntervalSince1970)))
        let request = try #require(center.added.first)
        let expectedDate = renewalDate.formatted(date: .abbreviated, time: .omitted)
        #expect(request.content.title.contains("Tally Annual"), "\(request.content.title)")
        #expect(request.content.title.contains(expectedDate), "\(request.content.title)")
        #expect(request.content.body.contains("Settings"), "\(request.content.body)")
        #expect(!request.content.title.contains("$") && !request.content.body.contains("$"), "no amount: \(request.content)")
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

    /// ideas2 report #4: `focusLevel` is the one thing that decides whether "Only urgent alerts"
    /// (`FocusFilterCriteria.urgentLevels == [.critical, .high]`) lets a reminder through.
    @Test("focusLevel: Time Sensitive is always critical; an exam is urgent even before Time Sensitive")
    func focusLevelMapping() {
        #expect(UNNotificationScheduler.focusLevel(for: Self.reminder(kind: .due, level: .timeSensitive)) == .critical)
        #expect(UNNotificationScheduler.focusLevel(for: Self.reminder(kind: .exam, level: .timeSensitive)) == .critical)
        #expect(UNNotificationScheduler.focusLevel(for: Self.reminder(kind: .exam, level: .active)) == .high)
        #expect(UNNotificationScheduler.focusLevel(for: Self.reminder(kind: .due, level: .active)) == .medium)
        #expect(UNNotificationScheduler.focusLevel(for: Self.reminder(kind: .followup, level: .active)) == .medium)
        #expect(UNNotificationScheduler.focusLevel(for: Self.reminder(kind: .digest, level: .passive)) == .info)
        #expect(FocusFilterCriteria.urgentLevels.contains(.critical) && FocusFilterCriteria.urgentLevels.contains(.high))
    }

    // MARK: - M3-C: the ReminderPlatform port (E07, UX-WP-12)

    @Test("M3-C: the composition root's adapter is a ReminderPlatform, so the pipeline finds it in the environment")
    func isAReminderPlatform() {
        let injected: any NotificationScheduling = UNNotificationScheduler(center: FakeNotificationCenterClient(status: .notDetermined),
                                                                           logger: RecordingPlatformLogger())
        #expect(injected is any ReminderPlatform)
    }

    @Test("M3-C: the permission is .authorized exactly when mayAdd allows adding (mutation-guarded)")
    func permissionMapping() {
        #expect(UNNotificationScheduler.permission(.notDetermined) == .notDetermined)
        #expect(UNNotificationScheduler.permission(.denied) == .denied)
        #expect(UNNotificationScheduler.permission(.authorized) == .authorized)
        #expect(UNNotificationScheduler.permission(.provisional) == .authorized)
        #expect(UNNotificationScheduler.permission(.ephemeral) == .authorized)
        for status: UNAuthorizationStatus in [.notDetermined, .denied, .authorized, .provisional, .ephemeral] {
            #expect((UNNotificationScheduler.permission(status) == .authorized) == UNNotificationScheduler.mayAdd(status))
        }
    }

    @Test("M3-C: reading the permission never asks; a request asks once for alert, sound and badge",
          arguments: [UNAuthorizationStatus.authorized, .denied])
    func requestAsksOnlyWhenCalled(_ answer: UNAuthorizationStatus) async {
        let center = FakeNotificationCenterClient(status: .notDetermined, answer: answer)
        let scheduler = UNNotificationScheduler(center: center, logger: RecordingPlatformLogger())
        #expect(await scheduler.permission() == .notDetermined)
        #expect(center.requests.isEmpty, "reading the permission asked for it")

        let result = await scheduler.requestPermission()
        #expect(result == UNNotificationScheduler.permission(answer))
        #expect(center.requests == [[.alert, .sound, .badge]])
    }

    @Test("M3-C: schedule(_:content:) adds the resolved words when allowed, nothing when not")
    func scheduleWithContent() async throws {
        let allowed = FakeNotificationCenterClient(status: .authorized)
        let scheduler = UNNotificationScheduler(center: allowed, logger: RecordingPlatformLogger())
        let rendered = NotificationContent.Rendered(title: "Lab Report 4 · BIO 101", body: "Due today at 6:00 PM.")
        await scheduler.schedule(Self.reminder("tally.tests.content", level: .active), content: rendered)
        let request = try #require(allowed.added.first)
        #expect(request.content.title == rendered.title && request.content.body == rendered.body)
        #expect(request.content.categoryIdentifier == UNNotificationScheduler.reminderCategoryIdentifier)
        #expect(request.content.interruptionLevel == .active)
        #expect(await scheduler.pendingContents() == ["tally.tests.content": rendered])

        let denied = FakeNotificationCenterClient(status: .denied)
        let logger = RecordingPlatformLogger()
        await UNNotificationScheduler(center: denied, logger: logger).schedule(Self.reminder(), content: rendered)
        #expect(denied.added.isEmpty)
        #expect(logger.names == ["notificationsNotAuthorized"])
    }

    /// ideas2 report #4: before this fix `request(...)` never set `filterCriteria`, so a "Study"/
    /// "Exam" Focus (`TallyFocusFilter`) was configured and kept by the system but changed
    /// nothing — every Tally notification always matched the filter's "no criteria" escape hatch.
    @Test("ideas2 #4: schedule(_:content:) sets the notification's Focus-filter criteria from the content's course")
    func scheduleSetsFocusFilterCriteria() async throws {
        let allowed = FakeNotificationCenterClient(status: .authorized)
        let scheduler = UNNotificationScheduler(center: allowed, logger: RecordingPlatformLogger())
        let withCourse = NotificationContent.Rendered(title: "Lab Report 4 · BIO 101", body: "Due today at 6:00 PM.",
                                                       courseID: "51842")
        await scheduler.schedule(Self.reminder("tally.tests.criteria.course", kind: .exam, level: .active), content: withCourse)
        let courseRequest = try #require(allowed.added.first { $0.identifier == "tally.tests.criteria.course" })
        #expect(courseRequest.content.filterCriteria == FocusFilterCriteria.criteria(courseID: "51842", level: .high))

        // An account-level reminder (no course) still gets criteria (never `nil`), so "only
        // certain courses" never silently also lets every courseless reminder through.
        let noCourse = NotificationContent.Rendered(title: "Evening digest", body: "3 things due tomorrow.")
        await scheduler.schedule(Self.reminder("tally.tests.criteria.nocourse", kind: .digest, level: .passive), content: noCourse)
        let digestRequest = try #require(allowed.added.first { $0.identifier == "tally.tests.criteria.nocourse" })
        #expect(digestRequest.content.filterCriteria == FocusFilterCriteria.criteria(courseID: nil, level: .info))

        // The generic single-arg path (NotificationReconciler's own `platform.schedule(_:)`, used
        // when no resolved content exists) still sets criteria, courseless but never `nil`.
        await scheduler.schedule(Self.reminder("tally.tests.criteria.generic", kind: .due, level: .timeSensitive))
        let genericRequest = try #require(allowed.added.first { $0.identifier == "tally.tests.criteria.generic" })
        #expect(genericRequest.content.filterCriteria == FocusFilterCriteria.criteria(courseID: nil, level: .critical))
    }
}
