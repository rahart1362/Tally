import Foundation
import Testing
import TallyDomain
import TallyStore
import TallyTestSupport
@testable import TallySync

/// CS-07 (crash-safety-2.md, CS7-1): the sync lane survives repeated identifiers.
///
/// - `NotificationReconciler.reconcile` used to trap (`Dictionary(uniqueKeysWithValues:)`) when
///   `desired` repeated a reminder ID, which `ReminderPlanner.plan` does whenever its candidate
///   list repeats an assignment.
/// - `RefreshCoordinator` commits whatever its gateway returns. A scripted gateway (or any gateway
///   other than `LiveCanvasGateway`) skips the gateway's de-duplication, so the commit path itself
///   (`SnapshotBudget`, `ChangeDigest.diff`, `SnapshotStore.commit`) must survive repeats.
@Suite("Repeated identifiers: reconciler and refresh coordinator never trap (CS-07)", .timeLimit(.minutes(TestTimeBudget.minutes(1))))
struct DuplicateIDSyncTests {
    private let now = DuplicateIDFixture.now

    private func reminder(_ id: String, firesIn seconds: TimeInterval, subjectID: String = "8111") -> PendingReminder {
        PendingReminder(id: id, kind: .due, fireDate: now.addingTimeInterval(seconds), interruptionLevel: .active,
                        subjectID: subjectID)
    }

    // MARK: - NotificationReconciler

    /// The reconciler orders `desired` soonest first, then keeps the first reminder for each ID:
    /// here the original, which is also the soonest.
    @Test func reconcilerSchedulesTheFirstOfARepeatedReminderID() async {
        let platform = FakeNotificationCenter()
        let desired = [reminder("a", firesIn: 3_600), reminder("b", firesIn: 5_400),
                       reminder("a", firesIn: 7_200, subjectID: "repeat")]

        let ledger = await NotificationReconciler.reconcile(desired: desired, ledger: SyncLedger(), platform: platform)

        #expect(await platform.pendingIdentifiers() == ["a", "b"])
        #expect(Set(ledger.notifications.keys) == ["a", "b"])
        let scheduledA = platform.pending.first { $0.id == "a" }
        #expect(scheduledA?.fireDate == now.addingTimeInterval(3_600))
        #expect(scheduledA?.subjectID == "8111")
    }

    @Test(arguments: DuplicateIDFixture.Kind.allCases)
    func plannerThenReconcilerSurviveARepeatedID(_ kind: DuplicateIDFixture.Kind) async {
        let snapshot = DuplicateIDFixture.snapshot(duplicating: kind)
        let candidates = DuplicateIDFixture.allAssignments(snapshot).map { ReminderCandidate(assignment: $0, priority: 70) }
        let desired = ReminderPlanner.plan(accountKey: snapshot.accountKey, candidates: candidates, settings: ReminderSettings(),
                                           now: now, timeZone: TimeZone(identifier: "America/New_York") ?? .current,
                                           refresh: RefreshRecord())
        let platform = FakeNotificationCenter()

        let ledger = await NotificationReconciler.reconcile(desired: desired, ledger: SyncLedger(), platform: platform)

        #expect(await platform.pendingIdentifiers() == Set(desired.map(\.id)))
        #expect(Set(ledger.notifications.keys) == Set(desired.map(\.id)))
    }

    // MARK: - RefreshCoordinator, with a gateway that returns repeats

    @Test func coordinatorCommitsFetchesThatRepeatEveryKindOfID() async throws {
        let gateway = ScriptedGateway { previous, now in
            DuplicateIDFixture.snapshot(duplicating: DuplicateIDFixture.Kind.allCases,
                                        generation: (previous?.generation ?? 0) + 1, fetchedAt: now)
        }
        let (coordinator, store) = try makeCoordinator(gateway: gateway, clock: TestClock(now))

        let first = await coordinator.run(trigger: .manual)
        #expect(first == .fresh(at: now))
        let second = await coordinator.run(trigger: .manual) // diffs a repeated snapshot against a repeated one
        #expect(second == .fresh(at: now))

        #expect(await coordinator.committedSnapshot?.generation == 2)
        guard case .loaded(let glance) = await store.loadGlance() else { Issue.record("expected a glance"); return }
        #expect(glance.generation == 2)
    }

    /// A snapshot written before CS-07 can already hold repeats. The next refresh diffs against it.
    @Test func coordinatorDiffsAgainstAPersistedSnapshotWithARepeatedCourse() async throws {
        let initial = DuplicateIDFixture.snapshot(duplicating: .course, generation: 1)
        let gateway = ScriptedGateway { previous, now in
            DuplicateIDFixture.base(generation: (previous?.generation ?? 0) + 1, fetchedAt: now)
        }
        let (coordinator, _) = try makeCoordinator(gateway: gateway, clock: TestClock(now), initialSnapshot: initial)
        let events = await coordinator.events()
        let inbox = EventInbox()
        let consumer = Task { await drain(events, into: inbox) }

        #expect(await coordinator.run(trigger: .manual) == .fresh(at: now))

        #expect(await eventually {
            await inbox.events.contains { if case .committed = $0 { true } else { false } }
        })
        let digest = await inbox.events.compactMap { event -> ChangeDigest? in
            if case .committed(_, let digest) = event { digest } else { nil }
        }.first
        #expect(digest?.courseScoreChanges.isEmpty == true, "Biology is compared with the first occurrence, which did not move")
        await coordinator.shutdown()
        _ = await consumer.value
    }
}
