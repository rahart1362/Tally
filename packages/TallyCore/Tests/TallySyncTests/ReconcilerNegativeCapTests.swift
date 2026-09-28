import Foundation
import Testing
import TallyDomain
import TallyStore
import TallyTestSupport
@testable import TallySync

/// R-4 (resilience.md, crash-safety-2.md F-8): `NotificationReconciler.reconcile` took
/// `desired.prefix(cap)`, which traps on a negative cap ("Can't take a prefix of negative
/// length"). A negative cap is now 0: nothing is kept, so everything pending is cancelled.
@Suite("NotificationReconciler: a negative cap is zero (R-4)", .timeLimit(.minutes(TestTimeBudget.minutes(1))))
struct ReconcilerNegativeCapTests {
    private let anchor = Date(timeIntervalSince1970: 1_790_600_400)

    private func reminder(_ id: String) -> PendingReminder {
        PendingReminder(id: id, kind: .due, fireDate: anchor, interruptionLevel: .active, subjectID: "1204400")
    }

    @Test(arguments: [-1, Int.min])
    func aNegativeCapKeepsNothing(_ cap: Int) async {
        let platform = FakeNotificationCenter()
        let first = await NotificationReconciler.reconcile(desired: [reminder("a"), reminder("b")], ledger: SyncLedger(), platform: platform)
        #expect(Set(await platform.pendingIdentifiers()) == ["a", "b"])

        let ledger = await NotificationReconciler.reconcile(desired: [reminder("a"), reminder("b")], ledger: first,
                                                            platform: platform, cap: cap)
        #expect(await platform.pendingIdentifiers().isEmpty)
        #expect(ledger.notifications.isEmpty)
    }
}
