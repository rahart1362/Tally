#if DEBUG
import Foundation
import StoreKit
import StoreKitTest
import Testing
import TallyDomain
@testable import Tally
@testable import TallyFeatures

/// DEBUG only: StoreKit Testing serves the hosted Debug runs (and their sanitizer runs); the Release
/// perf build has no use for it.
///
/// PAY-01 and PAY-03 (M3-B1) over the real StoreKit, through StoreKit Testing: an `SKTestSession`
/// over the repository's `Products.storekit` (bundled into this test target), the real
/// `StoreKitEntitlementSource` and a real `SubscriptionEngine` with enforcement turned on by
/// injection. Each scenario acts in the test session (renewal and expiry: at one second a day),
/// waits until StoreKit's own view, the one the engine reads, shows the change (StoreKit Testing
/// applies it out of process, and its session sees it first), then runs **one** foreground
/// (`SubscriptionEngine.foreground()`), after which the policy's state must have moved.
///
/// Serialized: one `SKTestSession` configures the whole process's StoreKit test environment.
///
/// `@MainActor`, like the test session's own use from a test: `SKTestSession` is a StoreKitTest
/// class with no isolation guarantees of its own, so it stays on one actor.
///
/// **Where it runs: wherever StoreKit Testing serves a subscription at all.** On a simulator the
/// suite first asks for the one subscription of a control configuration (`StoreKitProbe`, below)
/// and is skipped, with that reason, only when StoreKit Testing serves none of it; on a device it
/// always runs. A runtime that serves the control but not `Products.storekit`'s two products fails
/// `productsLoad`, which names what was served: a fault of this repository's file is never skipped.
/// Linux's `check_storekit_products.py` checks the file's content everywhere.
@Suite("PAY-01, PAY-03: StoreKit Testing moves the entitlement within one foreground", .serialized,
       .timeLimit(.minutes(3)),
       .enabled("StoreKit Testing serves no subscription of the control configuration on this simulator runtime") {
           await StoreKitProbe.servesSubscriptions()
       })
@MainActor
struct SubscriptionStoreKitTests {
    static let products = SubscriptionProducts(bundleID: "dev.tally-app.tally")

    private final class BundleToken {}

    /// One scenario's StoreKit Testing session (no transactions, no dialogs, every setting from the
    /// file) and its engine.
    @MainActor
    struct Stage {
        let session: SKTestSession
        let engine: SubscriptionEngine
        let gate: EntitlementGate

        static func make() async throws -> Stage {
            let url = try #require(Bundle(for: BundleToken.self).url(forResource: "Products", withExtension: "storekit"),
                                   "Products.storekit is not in the test bundle (project.yml)")
            let session = try SKTestSession(contentsOf: url)
            session.resetToDefaultState()
            session.disableDialogs = true
            session.clearTransactions()
            // The scenario starts once StoreKit Testing serves both products, or after 10 s (then
            // `productsLoad` and every purchase fail on their own): a new session can answer with an
            // empty list for a moment (`StoreKitProbe.servedProductIDs`).
            _ = await StoreKitProbe.servedProductIDs(products.all, within: .seconds(10))
            let gate = EntitlementGate(isEnforced: true)
            let engine = SubscriptionEngine(source: StoreKitEntitlementSource(products: products), gate: gate,
                                            products: products)
            await engine.start()
            await engine.settle()
            return Stage(session: session, engine: engine, gate: gate)
        }

        func end() async {
            await engine.stop()
            session.clearTransactions()
            session.resetToDefaultState()
        }

        /// The latest test-session transaction of Tally Annual matching `predicate`.
        func transaction(_ predicate: (SKTestTransaction) -> Bool = { _ in true }) -> SKTestTransaction? {
            session.allTransactions().last { $0.productIdentifier == products.studentAnnual && predicate($0) }
        }

        /// Waits (up to `timeout`) until StoreKit's own view shows `condition` for Tally Annual's
        /// latest verified transaction (`Transaction.latest(for:)`, which the engine reads at its next
        /// foreground). Not the test session's view: in run 36956766992 the session showed a renewal,
        /// an expiry, a refund and a resolved purchase while StoreKit's view did not yet. Never the
        /// app's state: that moves only through the one foreground.
        func storeKitShows(timeout: Duration = .seconds(30), _ condition: (Transaction) async -> Bool) async -> Bool {
            let deadline = ContinuousClock.now + timeout
            while ContinuousClock.now < deadline {
                if case .verified(let transaction)? = await Transaction.latest(for: products.studentAnnual),
                   await condition(transaction) {
                    return true
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            return false
        }

        /// One second of the session is one day, so the one-month trial ends after about 30 s and
        /// renews into the paid year, or expires when auto-renewal is off: the renewal and expiry
        /// scenarios then reach StoreKit's view even if the session's forced renewal or expiry does
        /// not (in run 36956766992 neither had when the engine read it, 0.3 s after the session showed
        /// it; RevenueCat's suites use this rate rather than either). Raw value 6 is
        /// `oneSecondIsOneDay`, deprecated in favour of a renaming RevenueCat found not to behave the same.
        func accelerateTime() {
            guard let rate = SKTestSession.TimeRate(rawValue: 6) else {
                Issue.record("SKTestSession.TimeRate has no raw value 6 (oneSecondIsOneDay)")
                return
            }
            session.timeRate = rate
        }

        /// A purchase of Tally Annual that entitled, after one foreground.
        func purchased() async throws -> Date {
            #expect(await engine.purchase(.student) == .purchased)
            await engine.foreground()
            let state = await gate.current
            guard case .entitled(let until) = state else {
                throw StageError.notEntitled(String(describing: state))
            }
            return until
        }
    }

    enum StageError: Error {
        case notEntitled(String)
    }

    @Test("PAY-01: StoreKit Testing loads both products as configured")
    func productsLoad() async throws {
        let stage = try await Stage.make()
        let loaded = try await Product.products(for: Self.products.all)
        // On failure the console line itself shows which IDs StoreKit Testing served.
        #expect(loaded.map(\.id).sorted() == Self.products.all.sorted())
        let student = try #require(loaded.first { $0.id == Self.products.studentAnnual },
                                   "StoreKit Testing served \(loaded.map(\.id)) on iOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        let parent = try #require(loaded.first { $0.id == Self.products.parentAnnual })
        #expect(student.type == .autoRenewable && parent.type == .autoRenewable)
        #expect(student.price == Decimal(string: "9.99"))
        #expect(parent.price == Decimal(string: "4.99"))
        #expect(!student.isFamilyShareable && !parent.isFamilyShareable, "Family Sharing is off")
        let studentInfo = try #require(student.subscription)
        let parentInfo = try #require(parent.subscription)
        #expect(studentInfo.subscriptionPeriod.value == 1 && studentInfo.subscriptionPeriod.unit == .year)
        #expect(parentInfo.subscriptionPeriod.value == 1 && parentInfo.subscriptionPeriod.unit == .year)
        let trial = try #require(studentInfo.introductoryOffer)
        #expect(trial.paymentMode == .freeTrial && trial.period.value == 1 && trial.period.unit == .month)
        #expect(studentInfo.winBackOffers.count == 1)
        #expect(parentInfo.introductoryOffer == nil)
        #expect(studentInfo.subscriptionGroupID != parentInfo.subscriptionGroupID, "two subscription groups")
        await stage.end()
    }

    @Test("Purchase: granted before it returns (then finished); the trial entitles; the parent role stays locked")
    func purchase() async throws {
        let stage = try await Stage.make()
        #expect(await stage.gate.current == .preview)
        #expect(await stage.engine.purchase(.student) == .purchased)
        #expect(await stage.gate.current?.isActiveEntitlement == true, "the purchase returned before it was granted")
        var unfinished = 0
        for await result in Transaction.unfinished where result.unsafePayloadValue.productID == Self.products.studentAnnual {
            unfinished += 1
        }
        #expect(unfinished == 0, "the granted purchase was not finished")
        await stage.engine.foreground()
        let state = await stage.gate.current
        guard case .entitled(let until) = state else {
            Issue.record("not entitled after the purchase: \(String(describing: state))")
            await stage.end()
            return
        }
        #expect(until > Date(), "the trial ends in the future")
        let facts = await StoreKitEntitlementSource(products: Self.products).currentFacts()
        #expect(facts.contains { $0.isVerified && $0.productID == Self.products.studentAnnual })
        #expect(EntitlementPolicy.accountState(facts, role: .parent, products: Self.products, now: Date()) == .preview,
                "a student plan never unlocks the parent role")
        await stage.end()
    }

    @Test("Renewal (StoreKit Testing's accelerated time): the expiry moves later within one foreground")
    func renewal() async throws {
        let stage = try await Stage.make()
        stage.accelerateTime()
        let first = try await stage.purchased()
        // The forced renewal, once StoreKit's view shows it; failing that, the trial's own renewal
        // into the paid year about 30 s after the purchase.
        try? stage.session.forceRenewalOfSubscription(productIdentifier: Self.products.studentAnnual)
        #expect(await stage.storeKitShows(timeout: .seconds(90)) { ($0.expirationDate ?? .distantPast) > first },
                "StoreKit never showed the renewal")
        await stage.engine.foreground()
        let state = await stage.gate.current
        guard case .entitled(let renewed) = state else {
            Issue.record("not entitled after the renewal: \(String(describing: state))")
            await stage.end()
            return
        }
        #expect(renewed > first, "the renewed expiry \(renewed) is not after the trial's \(first)")
        await stage.end()
    }

    @Test("Expiry: lapsed within one foreground")
    func expiry() async throws {
        let stage = try await Stage.make()
        stage.accelerateTime()
        _ = try await stage.purchased()
        let trial = try #require(stage.transaction())
        // Auto-renewal off: the trial ends about 30 s after the purchase, with no renewal. The test
        // session's forced expiry, if StoreKit's view ever takes it, only brings that forward.
        try stage.session.disableAutoRenewForTransaction(identifier: trial.identifier)
        try? stage.session.expireSubscription(productIdentifier: Self.products.studentAnnual)
        #expect(await stage.storeKitShows(timeout: .seconds(90)) { transaction in
            guard let expiry = transaction.expirationDate, expiry <= Date() else { return false }
            return await transaction.subscriptionStatus?.state == .expired
        }, "StoreKit never showed the expiry")
        await stage.engine.foreground()
        let state = await stage.gate.current
        guard case .lapsed = state else {
            Issue.record("not lapsed after the expiry: \(String(describing: state))")
            await stage.end()
            return
        }
        await stage.end()
    }

    @Test("Refund: the revocation lapses within one foreground")
    func refund() async throws {
        let stage = try await Stage.make()
        _ = try await stage.purchased()
        let refunded = try #require(stage.transaction())
        try stage.session.refundTransaction(identifier: refunded.identifier)
        #expect(await stage.storeKitShows { $0.revocationDate != nil }, "StoreKit never showed the refund")
        await stage.engine.foreground()
        let state = await stage.gate.current
        guard case .lapsed(let since) = state else {
            Issue.record("not lapsed after the refund: \(String(describing: state))")
            await stage.end()
            return
        }
        #expect(since <= Date().addingTimeInterval(60), "lapsed since the revocation")
        await stage.end()
    }

    @Test("Ask to Buy: pending, then the approval is granted through Transaction.updates, with no foreground")
    func askToBuy() async throws {
        let stage = try await Stage.make()
        stage.session.askToBuyEnabled = true
        #expect(await stage.engine.purchase(.student) == .pending)
        await stage.engine.foreground()
        #expect(await stage.gate.current == .preview, "nothing is granted while the purchase waits")
        let pending = try #require(stage.transaction { $0.pendingAskToBuyConfirmation })
        try stage.session.approveAskToBuyTransaction(identifier: pending.identifier)
        #expect(await stage.storeKitShows { _ in true }, "StoreKit never showed the approved purchase")
        // PAY-03: "Ask to Buy pending → granted via `updates`": the listener grants it, no foreground.
        let deadline = ContinuousClock.now + .seconds(30)
        while await stage.gate.current?.isActiveEntitlement != true, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        let state = await stage.gate.current
        guard case .entitled = state else {
            Issue.record("the approval was not granted through Transaction.updates: \(String(describing: state))")
            await stage.end()
            return
        }
        await stage.end()
    }

    @Test("Interrupted purchase: nothing until the issue is resolved, then entitled within one foreground")
    func interruptedPurchase() async throws {
        let stage = try await Stage.make()
        stage.session.interruptedPurchasesEnabled = true
        let outcome = await stage.engine.purchase(.student)
        #expect(outcome != .purchased, "an interrupted purchase completed at once: \(outcome)")
        await stage.engine.foreground()
        #expect(await stage.gate.current == .preview)
        stage.session.interruptedPurchasesEnabled = false
        let interrupted = try #require(stage.transaction { $0.hasPurchaseIssue })
        try stage.session.resolveIssueForTransaction(identifier: interrupted.identifier)
        #expect(await stage.storeKitShows { ($0.expirationDate ?? .distantPast) > Date() && $0.revocationDate == nil },
                "StoreKit never showed the purchase once its issue was resolved")
        await stage.engine.foreground()
        let state = await stage.gate.current
        guard case .entitled = state else {
            Issue.record("not entitled after the issue was resolved: \(String(describing: state))")
            await stage.end()
            return
        }
        await stage.end()
    }
}

/// Whether StoreKit Testing serves subscriptions on this runtime at all, asked with a control
/// configuration (`StoreKitProbe.storekit`, in this test target's folder): one plain auto-renewable
/// subscription with no offers, in the shape Xcode saves a version 4 file, sharing nothing with
/// `Products.storekit`. Outside `SubscriptionStoreKitTests`, whose `@Suite` trait calls it: a trait
/// that names its own suite's members is a circular reference (run 36946834779's build failure).
///
/// Run 36943065198 (iPhone 17 Pro, iOS 26.5) did not serve Tally Annual from `Products.storekit`'s
/// first version (every purchase was `.unavailable`; the parent product was never asked for), and
/// run 36951037662 (the same runtime) did not serve this control either, so it skipped the suite.
/// In both, the host app's own subscription engine had connected to StoreKit at app init, before
/// any `SKTestSession` existed; the composition root no longer gives it StoreKit in a process that
/// hosts these tests (`AppEnvironment.entitlementSource`, pinned by `StoreKitTestHostTests`). Run
/// 36954768450 (that fix in, the same runtime) still skipped the suite, asking for the control
/// once while the run was planned; hence the probe's patience. A file StoreKit Testing does not
/// accept still fails `productsLoad`, never a skip.
enum StoreKitProbe {
    static let productID = "dev.tally-app.tally.storekit-probe"

    private final class BundleToken {}

    /// True on a device, and when the control's subscription is served within `patience`. Also true
    /// when the control is missing from the test bundle, so a packaging fault runs (and fails) the
    /// suite instead of skipping it. False only when StoreKit Testing cannot open the control or
    /// serves none of it. Swift Testing asks this while it plans the run, moments after the app's
    /// launch, hence the patience.
    @MainActor
    static func servesSubscriptions(patience: Duration = .seconds(20)) async -> Bool {
        #if targetEnvironment(simulator)
        guard let url = Bundle(for: BundleToken.self).url(forResource: "StoreKitProbe", withExtension: "storekit") else {
            return true
        }
        guard let session = try? SKTestSession(contentsOf: url) else { return false }
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        let served = await servedProductIDs([productID], within: patience)
        session.clearTransactions()
        session.resetToDefaultState()
        return served.contains(productID)
        #else
        return true
        #endif
    }

    /// Which of `ids` StoreKit Testing serves, asked again every half second until it serves all of
    /// them or `patience` runs out. StoreKit Testing can answer with an empty list for a few seconds
    /// after a session is set up (RevenueCat's StoreKit tests wait, and retry an empty fixture lookup,
    /// for the same reason). Never an assertion: the caller's own expectations decide.
    static func servedProductIDs(_ ids: [String], within patience: Duration) async -> Set<String> {
        let deadline = ContinuousClock.now + patience
        while true {
            let served = Set(((try? await Product.products(for: ids)) ?? []).map(\.id))
            if served.isSuperset(of: ids) || ContinuousClock.now >= deadline { return served }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }
}

/// PAY-03: a process that hosts TallyAppTests leaves StoreKit to the StoreKit Testing suite, whose
/// `SKTestSession` must come before the process's first StoreKit connection (`StoreKitProbe`).
@Suite("PAY-03: the test host leaves StoreKit to the StoreKit Testing suite")
struct StoreKitTestHostTests {
    @Test("This process's engine gets no StoreKit source; an app process gets StoreKit")
    func testHostGetsNoStoreKit() {
        let products = SubscriptionProducts(bundleID: "dev.tally-app.tally")
        #expect(ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil,
                "XCTest no longer marks the process that hosts the tests")
        #expect(AppEnvironment.entitlementSource(products: products) is NoEntitlementSource)
        #expect(AppEnvironment.entitlementSource(products: products, environment: [:]) is StoreKitEntitlementSource)
    }
}
#endif
