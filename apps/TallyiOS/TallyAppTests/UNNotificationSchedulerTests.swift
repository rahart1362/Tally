import Foundation
import TallyDomain
import Testing
import UserNotifications
@testable import TallyPlatform

/// `.serialized`: `UNUserNotificationCenter.current()` is one process-wide
/// store: every test schedules under a unique UUID identifier and cleans up
/// after itself, but two tests must still never race the same center.
@Suite("UNNotificationScheduler", .serialized)
struct UNNotificationSchedulerTests {
    private let center = UNUserNotificationCenter.current()

    @Test("registerCategories() registers the reminder category with a hidden-previews placeholder")
    func registersCategory() async {
        let scheduler = UNNotificationScheduler(center: center)
        await scheduler.registerCategories()

        let categories = await center.notificationCategories()
        let category = categories.first { $0.identifier == UNNotificationScheduler.reminderCategoryIdentifier }
        #expect(category != nil)
        #expect(category?.hiddenPreviewsBodyPlaceholder == "Tally reminder")
    }

    @Test("request(...) builds exactly the content and trigger schedule() hands to UNUserNotificationCenter")
    func requestBuilderProducesExpectedContent() {
        let fireDate = Date().addingTimeInterval(3600)
        let request = UNNotificationScheduler.request(
            id: "tally.tests.fixed-id", title: "Due soon", body: "Problem Set 4",
            interruptionLevel: .timeSensitive, fireDate: fireDate)

        #expect(request.identifier == "tally.tests.fixed-id")
        #expect(request.content.title == "Due soon")
        #expect(request.content.body == "Problem Set 4")
        #expect(request.content.categoryIdentifier == UNNotificationScheduler.reminderCategoryIdentifier)
        #expect(request.content.interruptionLevel == .timeSensitive)
        let trigger = request.trigger as? UNTimeIntervalNotificationTrigger
        #expect(trigger != nil)
        #expect((trigger?.timeInterval ?? 0) > 3500)
    }

    /// `schedule()`/`cancel()` still exercise the real `UNUserNotificationCenter`
    /// so they are covered for crashes and API misuse, but the *pending-list*
    /// assertions are wrapped in `withKnownIssue`: confirmed on CI run
    /// 36335209586 that `add(_:)` does not surface a request via
    /// `pendingNotificationRequests()` in this hosted-test process, where
    /// notification authorization has never been requested/determined.
    /// architecture.md's WP-E07 already scopes this exact round trip as
    /// "macOS CI simulator; real prompts device-only" -- the content/trigger
    /// schedule() would pass to the center is covered instead, with no
    /// authorization dependency, by requestBuilderProducesExpectedContent above.
    @Test("schedule() enqueues a pending request with the given content and interruption level")
    func scheduleEnqueuesRequest() async throws {
        let scheduler = UNNotificationScheduler(center: center)
        let id = "tally.tests.\(UUID().uuidString)"
        try await scheduler.schedule(
            id: id, title: "Due soon", body: "Problem Set 4", interruptionLevel: .timeSensitive,
            fireDate: Date().addingTimeInterval(3600))

        await withKnownIssue("""
            UNUserNotificationCenter.add(_:) does not surface the request via \
            pendingNotificationRequests() in this hosted-test process (notification \
            authorization is never requested/determined here). See architecture.md \
            WP-E07: "real prompts device-only".
            """) {
            let ids = await scheduler.pendingIdentifiers()
            #expect(ids.contains(id))
            let requests = await center.pendingNotificationRequests()
            let request = requests.first { $0.identifier == id }
            #expect(request?.content.title == "Due soon")
        }

        await scheduler.cancel(ids: [id])
    }

    @Test("cancel(ids:) removes exactly those identifiers")
    func cancelRemovesRequested() async throws {
        let scheduler = UNNotificationScheduler(center: center)
        let keep = "tally.tests.\(UUID().uuidString)"
        let drop = "tally.tests.\(UUID().uuidString)"
        try await scheduler.schedule(id: keep, title: "Keep", body: "-", interruptionLevel: .active, fireDate: Date().addingTimeInterval(3600))
        try await scheduler.schedule(id: drop, title: "Drop", body: "-", interruptionLevel: .active, fireDate: Date().addingTimeInterval(3600))

        await scheduler.cancel(ids: [drop])

        await withKnownIssue("""
            Same root cause as scheduleEnqueuesRequest: pendingIdentifiers() is \
            never populated without notification authorization in this hosted-test \
            process, so "keep" cannot be observed as still pending here either. \
            cancel(ids:)'s own API calls (removePending/removeDelivered) still run \
            and are covered for crashes; the identifier-selection round trip is \
            device-only (architecture.md WP-E07).
            """) {
            let ids = await scheduler.pendingIdentifiers()
            #expect(ids.contains(keep))
            #expect(!ids.contains(drop))
        }

        await scheduler.cancel(ids: [keep])
    }

    @Test("cancelAll() runs without throwing and leaves nothing pending")
    func cancelAllClears() async throws {
        let scheduler = UNNotificationScheduler(center: center)
        try await scheduler.schedule(
            id: "tally.tests.\(UUID().uuidString)", title: "A", body: "-", interruptionLevel: .passive,
            fireDate: Date().addingTimeInterval(3600))

        await scheduler.cancelAll()

        // Not strong evidence on its own (pendingIdentifiers() is already
        // empty pre-cancel in this environment -- see scheduleEnqueuesRequest),
        // but real and worth keeping: proves cancelAll() completes without
        // throwing or crashing.
        let ids = await scheduler.pendingIdentifiers()
        #expect(ids.isEmpty)
    }

    @Test("InterruptionLevel -> UNNotificationInterruptionLevel mapping is total (mutation-guarded)")
    func interruptionLevelMapping() {
        #expect(UNNotificationScheduler.unInterruptionLevel(.passive) == .passive)
        #expect(UNNotificationScheduler.unInterruptionLevel(.active) == .active)
        #expect(UNNotificationScheduler.unInterruptionLevel(.timeSensitive) == .timeSensitive)
    }
}
