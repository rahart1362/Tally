import Foundation
import Testing
import TallyDomain
import TallyStore
import TallyTestSupport
@testable import TallySync

/// WP-D02: `NotificationReconciler` against `FakeNotificationCenter` (`TallyTestSupport`).
@Suite("NotificationReconciler: desired vs ledger vs the platform's pending set")
struct NotificationReconcilerTests {
    private let anchor = Date(timeIntervalSince1970: 1_790_600_400)

    private func reminder(_ id: String, fireDate: Date? = nil, kind: NotificationKind = .due, subjectID: String = "1204400") -> PendingReminder {
        PendingReminder(id: id, kind: kind, fireDate: fireDate ?? anchor, interruptionLevel: .active, subjectID: subjectID)
    }

    @Test func missingReminderIsScheduledAndRecordedInTheLedger() async {
        let platform = FakeNotificationCenter()
        let desired = [reminder("a"), reminder("b")]

        let ledger = await NotificationReconciler.reconcile(desired: desired, ledger: SyncLedger(), platform: platform)

        #expect(Set(await platform.pendingIdentifiers()) == ["a", "b"])
        #expect(platform.scheduleCallCount == 2)
        #expect(platform.cancelCallCount == 0)
        #expect(Set(ledger.notifications.keys) == ["a", "b"])
    }

    @Test func runningTwiceWithNoDriftSchedulesAndCancelsNothingMore() async {
        let platform = FakeNotificationCenter()
        let desired = [reminder("a"), reminder("b")]

        let firstLedger = await NotificationReconciler.reconcile(desired: desired, ledger: SyncLedger(), platform: platform)
        let scheduleCallsAfterFirst = platform.scheduleCallCount
        let cancelCallsAfterFirst = platform.cancelCallCount

        let secondLedger = await NotificationReconciler.reconcile(desired: desired, ledger: firstLedger, platform: platform)

        #expect(platform.scheduleCallCount == scheduleCallsAfterFirst, "idempotent: no new schedule calls")
        #expect(platform.cancelCallCount == cancelCallsAfterFirst, "idempotent: no new cancel calls")
        #expect(secondLedger.notifications == firstLedger.notifications)
    }

    @Test func aReminderNoLongerDesiredIsCancelledAndDroppedFromTheLedger() async {
        let platform = FakeNotificationCenter()
        let afterFirst = await NotificationReconciler.reconcile(desired: [reminder("a"), reminder("b")], ledger: SyncLedger(), platform: platform)

        let afterSecond = await NotificationReconciler.reconcile(desired: [reminder("a")], ledger: afterFirst, platform: platform)

        #expect(await platform.pendingIdentifiers() == ["a"])
        #expect(platform.cancelCallCount == 1)
        #expect(Set(afterSecond.notifications.keys) == ["a"])
    }

    @Test func changedContentUnderTheSameIDIsRescheduled() async {
        let platform = FakeNotificationCenter()
        let ledger = await NotificationReconciler.reconcile(desired: [reminder("a", fireDate: anchor)], ledger: SyncLedger(), platform: platform)
        let scheduleCallsAfterFirst = platform.scheduleCallCount

        // Same id, but the assignment's due date moved: the fire date changes under the same
        // deterministic notification id.
        let moved = anchor.addingTimeInterval(3600)
        let updatedLedger = await NotificationReconciler.reconcile(desired: [reminder("a", fireDate: moved)], ledger: ledger, platform: platform)

        #expect(platform.scheduleCallCount == scheduleCallsAfterFirst + 1, "content changed under the same id -> rescheduled")
        #expect(platform.cancelCallCount == 0, "still desired -> never cancelled, only replaced")
        #expect(platform.pending.first { $0.id == "a" }?.fireDate == moved)
        #expect(updatedLedger.notifications["a"] != ledger.notifications["a"])
    }

    @Test func aPlatformEntryTallyDoesNotRememberIsTreatedAsStaleToo() async {
        // Models drift: the platform has "orphan" pending from a previous install/version that the
        // (empty, fresh) ledger never recorded.
        let platform = FakeNotificationCenter(seeding: [reminder("orphan")])

        let ledger = await NotificationReconciler.reconcile(desired: [reminder("a")], ledger: SyncLedger(), platform: platform)

        #expect(await platform.pendingIdentifiers() == ["a"])
        #expect(platform.cancelCallCount == 1)
        #expect(Set(ledger.notifications.keys) == ["a"])
    }

    @Test func desiredBeyondTheCapIsTruncatedSoonestFirst() async {
        let platform = FakeNotificationCenter()
        let early = reminder("early", fireDate: anchor)
        let mid = reminder("mid", fireDate: anchor.addingTimeInterval(60))
        let late = reminder("late", fireDate: anchor.addingTimeInterval(120))

        let ledger = await NotificationReconciler.reconcile(desired: [late, early, mid], ledger: SyncLedger(), platform: platform, cap: 2)

        #expect(await platform.pendingIdentifiers() == ["early", "mid"])
        #expect(Set(ledger.notifications.keys) == ["early", "mid"])
    }

    @Test func aPreviouslyDesiredEntryThatFallsOutsideAShrunkCapIsCancelled() async {
        let platform = FakeNotificationCenter()
        let a = reminder("a", fireDate: anchor)
        let b = reminder("b", fireDate: anchor.addingTimeInterval(60))
        let firstLedger = await NotificationReconciler.reconcile(desired: [a, b], ledger: SyncLedger(), platform: platform, cap: 2)
        #expect(Set(firstLedger.notifications.keys) == ["a", "b"])

        // The cap shrinks to 1: "b" (the later one) must be cancelled even though it is still, in
        // principle, desired.
        let secondLedger = await NotificationReconciler.reconcile(desired: [a, b], ledger: firstLedger, platform: platform, cap: 1)

        #expect(await platform.pendingIdentifiers() == ["a"])
        #expect(platform.cancelCallCount == 1)
        #expect(Set(secondLedger.notifications.keys) == ["a"])
    }
}
