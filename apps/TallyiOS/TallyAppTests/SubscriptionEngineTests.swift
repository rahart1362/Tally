#if DEBUG
import Foundation
import Testing
import TallyDomain
import TallyStore
import TallySync
import TallyTestSupport
@testable import TallyFeatures

/// DEBUG only, like `SubscriptionTestSupport` (it uses `AccountHarness`).
///
/// M3-B1: the subscription engine over a scripted StoreKit (the real StoreKit runs in
/// `SubscriptionStoreKitTests`), with enforcement turned on by injection: the launch's order
/// (record, then StoreKit), the record (PAY-04), granting before finishing (PAY-03), and the lapse
/// (PAY-07). One guard per test, so a CI mutation run attributes each failure.
///
/// Serialized with the account-lifecycle suites: the lapse tests run reminders passes through
/// `ReminderPipeline`'s process-wide queue.
extension AccountLifecycleSuites {
    @Suite("M3-B1: the subscription engine (PAY-03, PAY-04, PAY-07)", .timeLimit(.minutes(2)))
    struct SubscriptionEngineTests {
        typealias F = SubscriptionFixtures

        // MARK: Launch and verification (PAY-03, PAY-04)

        @Test("Launch: the Keychain record's state reaches the gate before StoreKit answers")
        func launchRecordFirst() async throws {
            let until = F.now.addingTimeInterval(20 * F.day)
            let rig = SubscriptionRig(record: EntitlementRecord(studentUntil: until, verifiedAt: F.now))
            rig.source.holdReads()
            await rig.engine.start()
            #expect(await F.eventually { await rig.gate.current == .entitled(until: until) }, "the gate waited for StoreKit")
            #expect(rig.source.reads == 1, "StoreKit was asked, and is still answering")
            rig.source.release()
            await rig.engine.settle()
            #expect(await rig.gate.current == .preview, "StoreKit's answer (no transaction) replaced the record's")
        }

        @Test("Every verification writes the record: the expiry, and the time it was verified")
        func verificationWritesTheRecord() async {
            let rig = await SubscriptionRig(facts: [F.active()]).started()
            let record = await rig.records.load().record
            #expect(record?.studentUntil == F.active().expirationDate)
            #expect(record?.verifiedAt == F.now)
        }

        @Test("A verified lapse removes the record's expiry at once")
        func verifiedLapseClearsTheRecord() async {
            let rig = SubscriptionRig(facts: [F.refunded()],
                                      record: EntitlementRecord(studentUntil: F.now.addingTimeInterval(F.day), verifiedAt: F.now))
            await rig.engine.start()
            await rig.engine.settle()
            #expect(await rig.records.load().record?.studentUntil == nil)
            #expect(await rig.gate.current == .lapsed(since: F.now.addingTimeInterval(-120)))
        }

        @Test("Unverified transactions never entitle, at launch or through an update")
        func unverifiedNeverEntitles() async {
            let rig = await SubscriptionRig(facts: [F.active(verified: false)]).started()
            #expect(await rig.gate.current == .preview)
            await rig.source.deliverUpdate()
            #expect(await rig.gate.current == .preview)
            #expect(await rig.records.load().record?.studentUntil == nil)
        }

        @Test("An update is granted (recorded and gated) before the transactions are finished")
        func grantedBeforeFinished() async {
            let rig = await SubscriptionRig().started()
            rig.source.setFacts([F.active()])
            await rig.source.deliverUpdate()
            let until = F.active().expirationDate
            #expect(rig.source.finishes.last == .init(gateState: .entitled(until: until ?? F.now), recordedUntil: until))
        }

        @Test("The scene's foreground re-verifies with StoreKit")
        func foregroundReverifies() async {
            let rig = await SubscriptionRig(facts: [F.active()]).started()
            let reads = rig.source.reads
            rig.source.setFacts([F.expired()])
            await rig.engine.foreground()
            #expect(rig.source.reads == reads + 1)
            #expect(await rig.gate.current == .lapsed(since: F.now.addingTimeInterval(-60)))
        }

        @Test("start() runs once: one Transaction.updates listener")
        func startOnce() async {
            let rig = await SubscriptionRig().started()
            await rig.engine.start()
            await rig.engine.settle()
            #expect(rig.source.listens == 1)
        }

        @Test("Ask to Buy: pending until the approval arrives through Transaction.updates")
        func askToBuy() async {
            let rig = await SubscriptionRig().started()
            rig.source.setPurchase(.pending)
            let model = await MainActor.run { SubscriptionModel(engine: rig.engine) }
            await MainActor.run { model.start() }
            #expect(await rig.engine.purchase(.student) == .pending)
            #expect(await F.eventually { await MainActor.run { model.isPurchasePending } })
            rig.source.setFacts([F.active()])
            await rig.source.deliverUpdate()
            let until = F.active().expirationDate ?? F.now
            #expect(await F.eventually {
                await MainActor.run { !model.isPurchasePending && model.accountState == .entitled(until: until) }
            })
        }

        @Test("A verified purchase is granted before it returns")
        func purchaseGrants() async {
            let rig = await SubscriptionRig().started()
            rig.source.setPurchase(.purchased, factsAfter: [F.active()])
            #expect(await rig.engine.purchase(.student) == .purchased)
            #expect(await rig.gate.current == .entitled(until: F.active().expirationDate ?? F.now))
        }

        // MARK: The lapse (PAY-07), enforced by injection

        @Test("Lapse: 0 pending reminders and no background refresh scheduled; the snapshot stays readable")
        func lapseEndToEnd() async throws {
            let rig = await SubscriptionRig(facts: [F.active()]).started()
            let account = try await rig.attachedAccount()
            #expect(rig.scheduler.pending != nil, "entitled: the background refresh is requested")
            guard case .reconciled(let scheduled, _) = await account.reminderPass(), scheduled > 0 else {
                Issue.record("entitled: the pass scheduled nothing")
                return
            }

            rig.source.setFacts([F.expired()])
            await rig.engine.foreground()

            #expect(account.platform.pending.isEmpty, "\(account.platform.pending.count) reminders still pending")
            #expect(await rig.scheduler.isScheduled() == false, "a background refresh is still scheduled")
            #expect(await account.coordinator.committedSnapshot != nil, "the last snapshot stays readable")
            #expect(await rig.gate.allows(.savedSnapshot))
            #expect(await rig.gate.allows(.signOutAndErase))
        }

        @Test("Lapse withdraws the background refresh request")
        func lapseCancelsTheBackgroundRequest() async {
            let rig = await SubscriptionRig(facts: [F.active()]).started()
            #expect(rig.scheduler.schedules == 1 && rig.scheduler.cancels == 0)
            rig.source.setFacts([F.refunded()])
            await rig.engine.foreground()
            #expect(rig.scheduler.cancels == 1)
            #expect(rig.scheduler.pending == nil)
        }

        @Test("Lapse runs one reminders pass, which withdraws every pending reminder")
        func lapseWithdrawsReminders() async throws {
            let rig = await SubscriptionRig(facts: [F.active()]).started()
            let account = try await rig.attachedAccount()
            _ = await account.reminderPass()
            #expect(!account.platform.pending.isEmpty)
            rig.source.setFacts([F.refunded()])
            await rig.engine.foreground()
            #expect(account.platform.pending.isEmpty)
        }

        @Test("A pass while lapsed plans nothing and withdraws what is pending (.withdrawn)")
        func passWhileLapsedWithdraws() async throws {
            let rig = await SubscriptionRig(facts: [F.active()]).started()
            let account = try await rig.attachedAccount()
            _ = await account.reminderPass()
            let pending = account.platform.pending.count
            #expect(pending > 0)
            await rig.gate.update(.lapsed(since: F.now))
            #expect(await account.reminderPass() == .withdrawn(cancelled: pending))
            #expect(account.platform.pending.isEmpty)
            guard case .loaded(let ledger) = await SyncLedgerStore(
                root: account.harness.root, accountKey: account.harness.account,
                sealer: account.environment.sealer(for: account.harness.account)).load() else {
                Issue.record("no ledger")
                return
            }
            #expect(ledger.notifications.isEmpty, "the ledger forgets the withdrawn reminders")
        }

        @Test("A purchase after a lapse plans the reminders again and requests the background refresh")
        func purchaseRestores() async throws {
            let rig = await SubscriptionRig(facts: [F.expired()]).started()
            let account = try await rig.attachedAccount()
            #expect(rig.scheduler.pending == nil)
            rig.source.setPurchase(.purchased, factsAfter: [F.active()])
            #expect(await rig.engine.purchase(.student) == .purchased)
            #expect(rig.scheduler.pending != nil)
            #expect(!account.platform.pending.isEmpty, "the engine's pass planned the reminders again")
        }

        @Test("The glance mirrors the entitlement at once, and the widgets reload exactly when it changed")
        func glanceMirrorsAndReloads() async throws {
            let rig = await SubscriptionRig().started()
            let account = try await rig.attachedAccount()
            #expect(await account.glance()?.entitledUntil == nil)
            let reloadsBefore = account.reloads.value
            rig.source.setPurchase(.purchased, factsAfter: [F.active()])
            _ = await rig.engine.purchase(.student)
            #expect(await account.glance()?.entitledUntil == F.active().expirationDate)
            #expect(account.reloads.value == reloadsBefore + 1)
            await rig.engine.foreground() // the same answer: no rewrite, no reload
            #expect(account.reloads.value == reloadsBefore + 1)
        }

        @Test("Not enforced (main until M3-B2): a lapse withdraws nothing and unschedules nothing")
        func notEnforcedNeverWithdraws() async throws {
            let rig = await SubscriptionRig(enforced: false, facts: [F.active()]).started()
            let account = try await rig.attachedAccount()
            _ = await account.reminderPass()
            let pending = account.platform.pending.count
            rig.source.setFacts([F.refunded()])
            await rig.engine.foreground()
            #expect(account.platform.pending.count == pending)
            #expect(rig.scheduler.pending != nil)
            #expect(await rig.gate.current == .lapsed(since: F.now.addingTimeInterval(-120)), "the state is still true")
            #expect(await account.glance()?.entitledUntil == nil, "and the glance still mirrors it")
        }

        @Test("Sign-out detaches the account: no later effect reaches it")
        func detachedAccountGetsNoEffects() async throws {
            let rig = await SubscriptionRig(facts: [F.active()]).started()
            let account = try await rig.attachedAccount()
            _ = await account.reminderPass()
            let pending = account.platform.pending.count
            await rig.engine.accountDetached()
            rig.source.setFacts([F.refunded()])
            await rig.engine.foreground()
            #expect(account.platform.pending.count == pending, "a pass reached a detached account")
        }

        // MARK: The gate reaches every coordinator and pass

        @Test("AccountSessionFactory gives the account's coordinator the environment's gate")
        func factoryCoordinatorIsGated() async throws {
            let gate = EntitlementGate(isEnforced: true, clock: TestClock(F.now), state: .lapsed(since: F.now))
            let fetches = CallCounter()
            let harness = try AccountHarness(gateway: { account in
                FlagshipAccountGateway(account: account.accountKey, onFetch: { fetches.increment() })
            })
            try await harness.seedSignedInAccount()
            let base = harness.environment
            let environment = AccountEnvironment(
                storeRoot: base.storeRoot, credentialStore: base.credentialStore, keyring: base.keyring,
                lockPreferences: base.lockPreferences, transport: base.transport, notifications: base.notifications,
                clock: base.clock, gatewayOverride: base.gatewayOverride, entitlement: gate)
            let coordinator = await AccountSessionFactory.coordinator(for: harness.record, root: harness.root,
                                                                      environment: environment)
            #expect(await coordinator.committedSnapshot != nil, "the seeded snapshot")
            _ = await coordinator.run(trigger: .manual)
            #expect(fetches.value == 0, "a lapsed account refreshed")
            await coordinator.bumpEpochAndCancel()
        }

        // MARK: The observable (M3-B2 draws it)

        @Test("AppModel.subscription mirrors the engine; subscriptionState is the session's")
        @MainActor
        func appModelExposesTheState() async throws {
            let rig = SubscriptionRig(facts: [F.refunded()])
            let model = AppModel(subscription: SubscriptionModel(engine: rig.engine))
            model.subscription.start()
            #expect(try await HomeTestSupport.waitUntil { model.subscription.isVerifiedThisLaunch })
            #expect(model.subscription.accountState == .lapsed(since: F.now.addingTimeInterval(-120)))
            #expect(model.subscription.isEnforced)
            model.bootstrap() // Welcome: no first sync yet, so the lapse reads as a preview
            #expect(model.subscriptionState == .preview)
            model.enterSample()
            #expect(model.subscriptionState == .demo)
            #expect(model.subscription.allows(.fullApp, isSampleMode: true, firstSyncSucceeded: false))
            #expect(!model.subscription.allows(.fullApp, isSampleMode: false, firstSyncSucceeded: true))
        }
    }
}
#endif
