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

    @Test("schedule() enqueues a pending request with the given content and interruption level")
    func scheduleEnqueuesRequest() async throws {
        let scheduler = UNNotificationScheduler(center: center)
        let id = "tally.tests.\(UUID().uuidString)"
        try await scheduler.schedule(
            id: id, title: "Due soon", body: "Problem Set 4", interruptionLevel: .timeSensitive,
            fireDate: Date().addingTimeInterval(3600))

        let ids = await scheduler.pendingIdentifiers()
        #expect(ids.contains(id))

        let requests = await center.pendingNotificationRequests()
        let request = requests.first { $0.identifier == id }
        #expect(request?.content.title == "Due soon")
        #expect(request?.content.body == "Problem Set 4")
        #expect(request?.content.categoryIdentifier == UNNotificationScheduler.reminderCategoryIdentifier)
        #expect(request?.content.interruptionLevel == .timeSensitive)

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

        let ids = await scheduler.pendingIdentifiers()
        #expect(ids.contains(keep))
        #expect(!ids.contains(drop))

        await scheduler.cancel(ids: [keep])
    }

    @Test("cancelAll() clears every pending Tally request")
    func cancelAllClears() async throws {
        let scheduler = UNNotificationScheduler(center: center)
        try await scheduler.schedule(
            id: "tally.tests.\(UUID().uuidString)", title: "A", body: "-", interruptionLevel: .passive,
            fireDate: Date().addingTimeInterval(3600))

        await scheduler.cancelAll()

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
