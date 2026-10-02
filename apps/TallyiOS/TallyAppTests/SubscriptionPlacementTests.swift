#if DEBUG
import Foundation
import Synchronization
import Testing
import TallyCanvasAPI
import TallyDomain
import TallyStore
import TallySync
import TallyTestSupport
@testable import TallyFeatures

/// DEBUG only, like `SubscriptionTestSupport`, whose rig it uses (with `AccountHarness`).
///
/// M3-B2 through `AppModel`, with M3-B1's real engine and gate over a scripted StoreKit: the paywall's
/// placement (PAY-06), the locks (PAY-07), the school-revoked notice's trigger (PAY-10), Sign out &
/// erase deleting the entitlement record (PAY-11, M3-B1 O2), and a first sync over a snapshot an
/// earlier sign-in left behind (M3-B1 O3). One guard per test, so a mutation run attributes each
/// failure. Serialized with the account-lifecycle suites: `AppModel.attach` and sign-out touch
/// process-wide state.
extension AccountLifecycleSuites {
    @Suite("M3-B2: paywall placement, locks, the school notice, erase and the free first sync", .timeLimit(.minutes(2)))
    @MainActor
    struct SubscriptionPlacementTests {
        typealias F = SubscriptionFixtures

        /// An app model over `harness`'s account environment, with `rig`'s gate and engine; the engine
        /// started and its first answer observed.
        private func makeModel(_ harness: AccountHarness, _ rig: SubscriptionRig) async throws -> AppModel {
            let model = AppModel(accountEnvironment: harness.environment.replacingEntitlement(rig.gate),
                                 subscription: SubscriptionModel(engine: rig.engine), storefront: ScriptedStorefront())
            model.subscription.start()
            #expect(try await HomeTestSupport.waitUntil { model.subscription.isVerifiedThisLaunch })
            return model
        }

        /// An app model with no account environment, `rig`'s engine started and observed.
        private func makeModel(_ rig: SubscriptionRig) async throws -> AppModel {
            let model = AppModel(subscription: SubscriptionModel(engine: rig.engine), storefront: ScriptedStorefront())
            model.subscription.start()
            #expect(try await HomeTestSupport.waitUntil { model.subscription.isVerifiedThisLaunch })
            return model
        }

        /// Sign-in through the first sync to the root switch, as the FirstSync page drives it; false
        /// when the first sync never finished.
        private func signInThroughFirstSync(_ model: AppModel, _ harness: AccountHarness) async throws -> Bool {
            model.bootstrap()
            model.signInSucceeded(harness.credential, target: AccountHarness.target)
            let firstSync = try #require(model.firstSync)
            firstSync.start()
            guard try await HomeTestSupport.waitUntil({ firstSync.isFinished || firstSync.failure != nil }),
                  firstSync.isFinished else { return false }
            model.finishFirstSync()
            return true
        }

        private func signOut(_ model: AppModel) async {
            model.signOut()
            await model.awaitTeardown()
        }

        @Test("PAY-06 (c), (d): after the first sync rendered the Dashboard, the paywall once; then only from a locked feature")
        func firstSyncPaywallOnce() async throws {
            let harness = try AccountHarness()
            let model = try await makeModel(harness, SubscriptionRig()) // no transaction: a preview
            #expect(try await signInThroughFirstSync(model, harness))
            #expect(model.isFirstSyncPaywallDue)
            model.showFirstSyncPaywallIfDue(homeIsLoaded: false)
            #expect(model.paywall == nil, "shown before the Dashboard rendered")
            #expect(model.isFirstSyncPaywallDue)

            model.showFirstSyncPaywallIfDue(homeIsLoaded: true)
            #expect(model.paywall?.trigger == .firstSyncFinished)
            #expect(!model.isFirstSyncPaywallDue)
            model.dismissPaywall()
            model.showFirstSyncPaywallIfDue(homeIsLoaded: true)
            #expect(model.paywall == nil, "shown a second time")

            #expect(model.locks(.fullApp), "the tabs are not locked without a trial or subscription")
            #expect(model.locks(.refresh))
            model.showPaywall(for: .lockedFeature)
            #expect(model.paywall?.trigger == .lockedFeature, "a locked feature did not ask for the paywall")
            model.dismissPaywall()
            await signOut(model)
            #expect(!model.isFirstSyncPaywallDue && model.paywall == nil)
        }

        @Test("PAY-06: an account entitled at its first sync sees no paywall, and nothing is locked")
        func entitledSkipsThePaywall() async throws {
            let harness = try AccountHarness()
            let model = try await makeModel(harness, SubscriptionRig(facts: [F.active()]))
            #expect(try await signInThroughFirstSync(model, harness))
            model.showFirstSyncPaywallIfDue(homeIsLoaded: true)
            #expect(model.paywall == nil, "an entitled student was asked to buy")
            #expect(!model.isFirstSyncPaywallDue, "the one chance was not used up")
            #expect(!model.locks(.fullApp) && !model.locks(.refresh))
            model.showPaywall(for: .lockedFeature)
            #expect(model.paywall == nil, "a locked feature asked an entitled student to buy")
            await signOut(model)
        }

        @Test("PAY-06 (a), PAY-09: never before sign-in; sample mode never by itself, and Settings goes through the interstitial")
        func signedOutAndSample() async throws {
            let model = try await makeModel(SubscriptionRig())
            model.bootstrap()
            model.showPaywall(for: .lockedFeature)
            #expect(model.paywall == nil, "the paywall before sign-in")
            #expect(!PaywallPlacement.shows(.settings, in: model.paywallContext()), "a purchase offered before sign-in")
            #expect(!model.locks(.fullApp))

            model.enterSample()
            #expect(!model.locks(.fullApp), "sample data is locked")
            model.showPaywall(for: .lockedFeature)
            #expect(model.paywall == nil, "sample mode showed the paywall by itself")
            #expect(PaywallPlacement.shows(.settings, in: model.paywallContext()))
            #expect(PaywallPlacement.needsInterstitial(.settings, in: model.paywallContext()), "no interstitial in sample mode")
            model.exitSample()
            await model.awaitTeardown()
        }

        @Test("Before the launch's first entitlement state nothing is locked and nothing is offered")
        func unknownStateLocksNothing() async {
            let model = AppModel(subscription: SubscriptionModel(engine: SubscriptionRig().engine), storefront: ScriptedStorefront())
            model.bootstrap()
            model.completeSignIn(AccountKey("m3b2-unknown-state"))
            #expect(model.subscription.accountState == nil)
            #expect(!model.locks(.fullApp), "a subscriber would see a locked card flash at launch")
            model.showPaywall(for: .lockedFeature)
            #expect(model.paywall == nil)
            await signOut(model)
        }

        @Test("M3-B1 O3: a sign-in over a snapshot an earlier sign-in left behind still gets its free first sync; then refresh needs the subscription")
        func firstSyncOverALeftoverSnapshot() async throws {
            let fetches = CallCounter()
            let harness = try AccountHarness(gateway: { account in
                FlagshipAccountGateway(account: account.accountKey, onFetch: { fetches.increment() })
            })
            try await harness.seedSignedInAccount() // what a purge that failed leaves behind
            let model = try await makeModel(harness, SubscriptionRig()) // a preview: every refresh but the first sync refused
            #expect(try await signInThroughFirstSync(model, harness), "the first sync waited for a refresh the gate refused")
            #expect(fetches.value == 1)
            let coordinator = try #require(await model.accountRuntime.coordinator())
            _ = await coordinator.run(trigger: .manual)
            #expect(fetches.value == 1, "after its first sync, the account refreshed with no subscription")
            await signOut(model)
        }

        @Test("PAY-11 (M3-B1 O2): Sign out & erase deletes the Keychain entitlement record")
        func signOutErasesTheRecord() async throws {
            let record = EntitlementRecord(studentUntil: F.now.addingTimeInterval(30 * F.day), verifiedAt: F.now)
            let rig = SubscriptionRig(facts: [F.active()], record: record)
            let model = try await makeModel(rig)
            #expect(await rig.records.load().record != nil)
            model.bootstrap()
            model.completeSignIn(AccountKey("m3b2-erase"))
            await signOut(model)
            #expect(await rig.records.load() == .notFound, "the entitlement record outlived Sign out & erase")
        }

        @Test("PAY-10: invalid_client while entitled shows the school-revoked notice; not without a subscription; closing it keeps it closed")
        func schoolRevokedNotice() async throws {
            for entitled in [true, false] {
                let rig = SubscriptionRig(facts: entitled ? [F.active()] : [])
                let model = try await makeModel(rig)
                let account = try await rig.unattachedAccount()
                let snapshot = try await FlagshipAccountGateway.flagship(account: account.harness.account)
                // Ungated, so the refresh reaches the (refusing) school whatever the subscription says.
                let coordinator = RefreshCoordinator(gateway: SchoolDisabledGateway(), store: account.store,
                                                     clock: FixedClock(now: F.now), initialSnapshot: snapshot)
                model.bootstrap()
                model.completeSignIn(account.harness.account)
                await model.attach(coordinator)
                #expect(!model.showsSchoolRevokedNotice)
                _ = await coordinator.run(trigger: .manual)
                let failed = try await HomeTestSupport.waitUntil {
                    if case .failed(.schoolDisabled, _) = model.refreshStatus.freshness { return true }
                    return false
                }
                #expect(failed, "the refresh did not fail with .schoolDisabled")
                #expect(model.showsSchoolRevokedNotice == entitled, "entitled: \(entitled)")
                model.dismissSchoolRevokedNotice()
                #expect(!model.showsSchoolRevokedNotice)
                model.detach()
                await coordinator.bumpEpochAndCancel()
                await signOut(model)
                await account.coordinator.bumpEpochAndCancel()
            }
        }
    }
}

/// The paywall's and Settings → Subscription's models (PAY-05, PAY-08) over M3-B1's engine and a
/// scripted storefront. The system sheets themselves are Apple's: these tests stop at their triggers.
@Suite("M3-B2: the paywall and Settings → Subscription models (PAY-05, PAY-08)", .timeLimit(.minutes(2)))
@MainActor
struct SubscriptionModelsTests {
    typealias F = SubscriptionFixtures

    static let offer = SubscriptionTestOffers.annual

    private func startedSubscription(_ rig: SubscriptionRig) async throws -> SubscriptionModel {
        let subscription = SubscriptionModel(engine: rig.engine)
        subscription.start()
        #expect(try await HomeTestSupport.waitUntil { subscription.isVerifiedThisLaunch })
        return subscription
    }

    @Test("PAY-05: the App Store's price text, placed as '$9.99/year' and never reformatted; the trial line only when eligible")
    func offerTexts() {
        #expect(SubscriptionOfferText.price(Self.offer) == "$9.99/year")
        #expect(SubscriptionOfferText.spokenPrice(Self.offer) == "$9.99 per year")
        #expect(SubscriptionOfferText.duration(Self.offer) == "Subscription length: 1 year")
        #expect(SubscriptionOfferText.trial(Self.offer) == "1 month free, then $9.99/year")
        let euro = SubscriptionOffer(displayPrice: "9,99 €", period: SubscriptionOffer.Period(value: 1, unit: .year), freeTrial: nil)
        #expect(SubscriptionOfferText.price(euro) == "9,99 €/year", "the App Store's text, as it is")
        #expect(SubscriptionOfferText.trial(euro) == nil)
        let halfYear = SubscriptionOffer(displayPrice: "$5.49", period: SubscriptionOffer.Period(value: 6, unit: .month), freeTrial: nil)
        #expect(SubscriptionOfferText.price(halfYear) == "$5.49 every 6 months")
    }

    @Test("PAY-05: the paywall loads the offer, follows the school (G-6) and the trial; purchase outcomes become notices")
    func paywallPurchase() async throws {
        let rig = SubscriptionRig()
        let subscription = try await startedSubscription(rig)
        let model = PaywallModel(trigger: .firstSyncFinished, school: .noneInCanvas, subscription: subscription,
                                 storefront: ScriptedStorefront(offer: Self.offer))
        #expect(model.phase == .loading && !model.canPurchase)
        await model.load()
        #expect(model.phase == .ready(Self.offer))
        #expect(model.content.variant == .noGradeClaims)
        #expect(model.content.action == .startFreeTrial && model.content.showsTrial)
        #expect(model.canPurchase)

        rig.source.setPurchase(.pending)
        await model.purchase()
        #expect(model.notice == .pending, "Ask to Buy said nothing")
        rig.source.setPurchase(.cancelled)
        await model.purchase()
        #expect(model.notice == nil)
        rig.source.setPurchase(.failed)
        await model.purchase()
        #expect(model.notice == .failed)
        #expect(!model.isComplete)
        rig.source.setPurchase(.purchased, factsAfter: [F.active()])
        await model.purchase()
        #expect(model.notice == nil)
        #expect(model.isComplete, "the purchase was granted, but the paywall would stay open")
    }

    @Test("PAY-05: with no answer from the App Store the paywall offers nothing to buy")
    func paywallUnavailable() async throws {
        let subscription = try await startedSubscription(SubscriptionRig())
        let model = PaywallModel(trigger: .settings, school: .allInCanvas, subscription: subscription,
                                 storefront: ScriptedStorefront(offer: nil))
        await model.load()
        #expect(model.phase == .unavailable)
        #expect(model.content.variant == .standard)
        await model.purchase()
        #expect(model.notice == nil && !model.canPurchase)
    }

    @Test("PAY-05, PAY-08: Restore Purchases asks the App Store, then the engine re-verifies; finding nothing says so")
    func restore() async throws {
        let rig = SubscriptionRig()
        let subscription = try await startedSubscription(rig)
        let storefront = ScriptedStorefront(offer: Self.offer)
        let model = PaywallModel(trigger: .lockedFeature, school: .allInCanvas, subscription: subscription, storefront: storefront)
        let reads = rig.source.reads
        await model.restore()
        #expect(storefront.restoreCalls == 1)
        #expect(rig.source.reads == reads + 1, "the engine did not re-verify after the restore")
        #expect(model.notice == .nothingToRestore)
        rig.source.setFacts([F.active()])
        await model.restore()
        #expect(model.notice == nil && model.isComplete)

        let unreachable = ScriptedStorefront(offer: Self.offer, restores: false)
        let lapsedRig = SubscriptionRig()
        let other = PaywallModel(trigger: .settings, school: .allInCanvas, subscription: try await startedSubscription(lapsedRig),
                                 storefront: unreachable)
        await other.restore()
        #expect(other.notice == .restoreFailed)
    }

    @Test("PAY-08, PAY-10, PAY-11: Manage Subscription, Redeem Code and Request a Refund fire their sheets' triggers")
    func actionTriggers() async throws {
        let rig = SubscriptionRig(facts: [F.active()])
        let subscription = try await startedSubscription(rig)
        let actions = SubscriptionActionsModel(subscription: subscription, storefront: ScriptedStorefront(offer: nil, refundable: 42))
        #expect(!actions.isPresentingSheet)
        actions.manage()
        #expect(actions.presentsManage)
        actions.presentsManage = false
        actions.redeem()
        #expect(actions.presentsRedeem)
        actions.presentsRedeem = false
        await actions.requestRefund()
        #expect(actions.refundTransactionID == 42 && actions.presentsRefund, "Request a Refund presented nothing")
        actions.presentsRefund = false
        let reads = rig.source.reads
        await actions.sheetClosed()
        #expect(rig.source.reads == reads + 1, "closing Apple's sheet did not re-verify")

        let nothing = SubscriptionActionsModel(subscription: subscription, storefront: ScriptedStorefront(offer: nil, refundable: nil))
        await nothing.requestRefund()
        #expect(nothing.notice == .noRefund && !nothing.presentsRefund)
    }

    @Test("Settings → Subscription's status, from the Apple Account's state")
    func statusText() {
        #expect(SubscriptionStatusText.status(nil, isPurchasePending: false) == "Checking")
        #expect(SubscriptionStatusText.status(.preview, isPurchasePending: false) == "Not subscribed")
        #expect(SubscriptionStatusText.status(.preview, isPurchasePending: true) == "Waiting for approval")
        let until = Date(timeIntervalSince1970: 1_822_000_000)
        #expect(SubscriptionStatusText.status(.entitled(until: until), isPurchasePending: true).hasPrefix("Active until "))
        #expect(SubscriptionStatusText.status(.lapsed(since: until), isPurchasePending: false).hasPrefix("Ended "))
    }

    @Test("M3-B3: a school seat reads 'Provided by your school'; a purchase, and the holding not yet known, read 'Active' (today's purchase UI)")
    func statusTextHolding() {
        let until = Date(timeIntervalSince1970: 1_822_000_000)
        let date = until.formatted(date: .abbreviated, time: .omitted)
        #expect(SubscriptionStatusText.status(.entitled(until: until), holding: .purchase, isPurchasePending: false)
            == "Active until \(date)")
        #expect(SubscriptionStatusText.status(.entitled(until: until), holding: nil, isPurchasePending: false)
            == "Active until \(date)", "unknown (before StoreKit answered) must read as a purchase, never as a seat")
        #expect(SubscriptionStatusText.status(.entitled(until: until), holding: .schoolSeat, isPurchasePending: false)
            == "Provided by your school until \(date)")
    }

    @Test("The UI-test hook: the last -TallyTestHooks.entitlement wins; its purchase entitles; no hook, no stand-in")
    func uiTestHook() async throws {
        let products = F.products
        #expect(SubscriptionTestHooks(arguments: ["-other", "x"]).entitlement == nil)
        #expect(SubscriptionTestHooks(arguments: []).source(products: products) == nil)
        let hooks = SubscriptionTestHooks(arguments: ["-TallyTestHooks.entitlement", "entitled", "-TallyTestHooks.entitlement", "none"])
        #expect(hooks.entitlement == .notSubscribed)
        let source = try #require(hooks.source(products: products, clock: TestClock(F.now)))
        #expect(await source.currentFacts().isEmpty)
        #expect(await source.purchase(products.studentAnnual, onGranted: {}) == .purchased)
        let facts = await source.currentFacts()
        #expect(EntitlementPolicy.accountState(facts, role: .student, products: products, now: F.now).entitledUntil != nil)
        #expect(await hooks.storefront()?.offer(for: .student)?.freeTrial == SubscriptionOffer.Period(value: 1, unit: .month))
        let lapsed = SubscriptionTestHooks(arguments: ["-TallyTestHooks.entitlement", "lapsed"])
        #expect(await lapsed.storefront()?.offer(for: .student)?.freeTrial == nil, "a lapsed account offered the trial")
        let lapsedFacts = await lapsed.source(products: products, clock: TestClock(F.now))?.currentFacts() ?? []
        #expect(EntitlementPolicy.accountState(lapsedFacts, role: .student, products: products, now: F.now).entitledUntil == nil)
    }

    @Test("M3-B3: the UI-test hook can express a school seat cheaply; its facts hold as .schoolSeat, not a trial")
    func uiTestHookSchoolSeat() async throws {
        let products = F.products
        let hooks = SubscriptionTestHooks(arguments: ["-TallyTestHooks.entitlement", "schoolSeat"])
        #expect(hooks.entitlement == .schoolSeat)
        let source = try #require(hooks.source(products: products, clock: TestClock(F.now)))
        let facts = await source.currentFacts()
        #expect(EntitlementPolicy.accountState(facts, role: .student, products: products, now: F.now).entitledUntil != nil)
        #expect(EntitlementPolicy.holding(facts, role: .student, products: products, now: F.now) == .schoolSeat)
        #expect(await hooks.storefront()?.offer(for: .student)?.freeTrial == nil, "a seat is not trial-eligible")
    }
}

/// Tally Annual as `Products.storekit` defines it: a year at a synthetic "$9.99", a one-month free trial.
enum SubscriptionTestOffers {
    static let annual = SubscriptionOffer(displayPrice: "$9.99", period: SubscriptionOffer.Period(value: 1, unit: .year),
                                          freeTrial: SubscriptionOffer.Period(value: 1, unit: .month))
}

/// A storefront the test scripts: its offer, whether Restore Purchases reaches the App Store, and the
/// transaction Request a Refund would name.
final class ScriptedStorefront: SubscriptionStorefront {
    private struct State {
        var offer: SubscriptionOffer?
        var restores: Bool
        var refundable: UInt64?
        var restoreCalls = 0
    }

    private let state: Mutex<State>

    init(offer: SubscriptionOffer? = SubscriptionTestOffers.annual, restores: Bool = true, refundable: UInt64? = nil) {
        state = Mutex(State(offer: offer, restores: restores, refundable: refundable))
    }

    var restoreCalls: Int { state.withLock { $0.restoreCalls } }

    func offer(for role: SubscriptionRole) async -> SubscriptionOffer? {
        state.withLock { $0.offer }
    }

    func restorePurchases() async -> Bool {
        state.withLock { state in
            state.restoreCalls += 1
            return state.restores
        }
    }

    func refundableTransaction(for role: SubscriptionRole) async -> UInt64? {
        state.withLock { $0.refundable }
    }
}

/// PAY-10: a school whose Canvas rejects Tally's client (`invalid_client`).
nonisolated struct SchoolDisabledGateway: CanvasGateway {
    func fetchSnapshot(previous: CanvasSnapshot?, now: Date) async throws -> CanvasSnapshot {
        throw RefreshFailure.schoolDisabled
    }
}
#endif
