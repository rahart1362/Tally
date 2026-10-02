#if DEBUG
import Foundation
import StoreKit
import StoreKitTest
import Testing
import TallyDomain
@testable import TallyFeatures

/// DEBUG only: StoreKit Testing serves the hosted Debug runs (and their sanitizer runs); the Release
/// perf build has no use for it.
///
/// PAY-01 and PAY-03 (M3-B1) over the real StoreKit, through StoreKit Testing: an `SKTestSession`
/// over the repository's `Products.storekit` (bundled into this test target), the real
/// `StoreKitEntitlementSource` and a real `SubscriptionEngine` with enforcement turned on by
/// injection. Each scenario acts in the test session, waits until the session itself shows the
/// change (StoreKit Testing applies it out of process), then runs **one** foreground
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

        /// Waits (up to 30 s) until the test session itself shows `condition`: StoreKit Testing applies
        /// an action out of process. Never the app's state: that moves only through the one foreground.
        func sessionShows(_ condition: () -> Bool) async -> Bool {
            let deadline = ContinuousClock.now + .seconds(30)
            while !condition() {
                guard ContinuousClock.now < deadline else { return false }
                try? await Task.sleep(for: .milliseconds(20))
            }
            return true
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

    @Test("Renewal (StoreKit Testing's forced renewal): the expiry moves later within one foreground")
    func renewal() async throws {
        let stage = try await Stage.make()
        let first = try await stage.purchased()
        let before = stage.session.allTransactions().count
        try stage.session.forceRenewalOfSubscription(productIdentifier: Self.products.studentAnnual)
        #expect(await stage.sessionShows { stage.session.allTransactions().count > before }, "no renewal transaction")
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
        _ = try await stage.purchased()
        try stage.session.expireSubscription(productIdentifier: Self.products.studentAnnual)
        #expect(await stage.sessionShows { (stage.transaction()?.expirationDate ?? .distantFuture) <= Date() })
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
        #expect(await stage.sessionShows { stage.transaction { $0.identifier == refunded.identifier }?.cancelDate != nil })
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
        #expect(await stage.sessionShows { stage.transaction { $0.identifier == interrupted.identifier }?.hasPurchaseIssue == false })
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
/// first version (every purchase was `.unavailable`; the parent product was never asked for). That
/// version lacked the `_storeKitErrors` settings and gave its free trial a `numberOfPeriods`, unlike
/// every Xcode-saved version 4 file. The control separates the two possible causes: a runtime that
/// serves nothing (skipped) and a file StoreKit Testing does not accept (a failure).
enum StoreKitProbe {
    static let productID = "dev.tally-app.tally.storekit-probe"

    private final class BundleToken {}

    /// True on a device, and when the control's subscription is served. Also true when the control
    /// is missing from the test bundle, so a packaging fault runs (and fails) the suite instead of
    /// skipping it. False only when StoreKit Testing cannot open the control or serves none of it.
    @MainActor
    static func servesSubscriptions() async -> Bool {
        #if targetEnvironment(simulator)
        guard let url = Bundle(for: BundleToken.self).url(forResource: "StoreKitProbe", withExtension: "storekit") else {
            return true
        }
        guard let session = try? SKTestSession(contentsOf: url) else { return false }
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        let served = (try? await Product.products(for: [productID])) ?? []
        session.clearTransactions()
        session.resetToDefaultState()
        return served.contains { $0.id == productID }
        #else
        return true
        #endif
    }
}
#endif
