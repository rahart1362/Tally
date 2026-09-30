import Foundation
import Synchronization
import Testing
import TallyDomain
import TallyStore
import TallyTestSupport
@testable import TallyFeatures

/// `UserState` v4 in the app (M3-A O3; M3-C O1, O2): a signed-in account's course order, "done" marks
/// and reminders-tip dismissal are sealed in its `UserState`, so they survive a relaunch; a done mark
/// takes the item out of the reminders.
@Suite("UserState v4 wiring: course order, done marks and the reminders tip persist per account")
@MainActor
struct UserStateV4WiringTests {
    private final class Counter: Sendable {
        private let count = Mutex(0)
        func record() { count.withLock { $0 += 1 } }
        var value: Int { count.withLock { $0 } }
    }

    private func accountAccess() throws -> (UserStateStore, AccountUserStateAccess) {
        let account = AccountKey("v4-wiring-\(UUID().uuidString)")
        let (directory, sealer) = try ScreenModelSupport.sealer(account)
        let store = UserStateStore(root: directory, accountKey: account, sealer: sealer)
        return (store, AccountUserStateAccess(store: store, runtime: AccountRuntime()))
    }

    @Test("course order and done marks survive a relaunch; only a done-mark change runs a reminders pass")
    func screenStatePersistsAndDoneMarksRunAPass() async throws {
        let (store, access) = try accountAccess()
        let passes = Counter()
        let first = ScreenLocalState(store: AccountLocalScreenStateStore(access: access, onDoneMarksChanged: { passes.record() }))
        await first.load()

        first.setCourseOrder([CanvasID("51842"), CanvasID("51840")])
        await first.awaitSaved()
        #expect(passes.value == 0, "a reorder alone runs no reminders pass")
        first.setDone([CanvasID<Assignment>("9001")], done: true)
        await first.awaitSaved()
        #expect(passes.value == 1, "a done mark runs one pass, so its reminders are cancelled")

        guard case .loaded(let onDisk) = await store.load() else { Issue.record("expected the sealed UserState"); return }
        #expect(onDisk.courseOrder == [CanvasID("51842"), CanvasID("51840")])
        #expect(onDisk.doneAssignments == [CanvasID("9001")])

        // A relaunch: a new Home over the same account's store reads both back.
        let relaunched = ScreenLocalState(store: AccountLocalScreenStateStore(access: access))
        await relaunched.load()
        #expect(relaunched.courseOrder == [CanvasID("51842"), CanvasID("51840")])
        #expect(relaunched.isDone(CanvasID("9001")))
    }

    @Test("the reminders tip's dismissal outlives the model, for 7 days")
    func tipDismissalPersists() async throws {
        let (_, access) = try accountAccess()
        let clock = TestClock()
        let first = RemindersModel(platform: nil, clock: clock)
        first.tipDismissalStore = UserStateTipDismissalStore(access: access)
        first.dismissTip()
        await first.awaitTipSaved()

        let relaunched = RemindersModel(platform: nil, clock: clock)
        relaunched.tipDismissalStore = UserStateTipDismissalStore(access: access)
        await relaunched.refreshPermission()
        #expect(relaunched.isTipSnoozed, "still dismissed after a relaunch")

        clock.advance(by: RemindersConfig.tipSnooze + .seconds(60))
        await relaunched.refreshPermission()
        #expect(!relaunched.isTipSnoozed, "back after the snooze")
    }

    @Test("an item marked done is not a reminder candidate")
    func doneMarkExcludesTheCandidate() async throws {
        let now = ReminderTestAnchor.value
        let snapshot = try await FlagshipSnapshotHarness.fetchSnapshot(now: now)
        let open = ReminderSubjects(snapshot: snapshot, now: now)
        let marked = try #require(open.candidates.first?.assignment.id, "the flagship has open work due soon")

        let afterMark = ReminderSubjects(snapshot: snapshot, now: now, doneAssignments: [marked])
        #expect(!afterMark.candidates.contains { $0.assignment.id == marked })
        #expect(afterMark.candidates.count == open.candidates.count - 1)
    }
}

/// The flagship replay's own anchor (2026-09-21T14:13:20Z; `FlagshipSnapshotHarness`'s default).
private enum ReminderTestAnchor {
    static let value = Date(timeIntervalSince1970: 1_790_000_000)
}
