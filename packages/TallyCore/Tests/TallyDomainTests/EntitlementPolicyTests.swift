import Foundation
import Testing
@testable import TallyDomain

/// PAY-02 (pricing-licensing.md §6): `EntitlementPolicy` over plain values. One case per rule and
/// boundary: sample mode, the first sync, verification, refunds and revocation, boundary times, the
/// offline grace, the billing grace period and billing retry, roles, upgrades, ownership, and clock
/// skew. Every value is synthetic.
@Suite("EntitlementPolicy (PAY-02): plain values in, one state out")
struct EntitlementPolicyTests {
    static let products = SubscriptionProducts(bundleID: "dev.tally-app.tally")
    static let student = products.studentAnnual
    static let parent = products.parentAnnual
    /// 2026-09-21T14:13:20Z.
    static let now = Date(timeIntervalSince1970: 1_790_000_000)
    static let day: TimeInterval = 24 * 60 * 60
    static let grace = SubscriptionConfig.offlineGracePeriod.timeInterval

    static func at(_ offset: TimeInterval) -> Date { now.addingTimeInterval(offset) }

    static func fact(_ productID: String = student, verified: Bool = true, expires: TimeInterval? = 30 * day,
                     revoked: TimeInterval? = nil, upgraded: Bool = false,
                     ownership: SubscriptionFacts.Ownership = .purchased, renewal: SubscriptionFacts.RenewalState? = nil,
                     graceEnds: TimeInterval? = nil, signed: TimeInterval? = nil) -> SubscriptionFacts {
        SubscriptionFacts(productID: productID, isVerified: verified, expirationDate: expires.map(at),
                          revocationDate: revoked.map(at), isUpgraded: upgraded, ownership: ownership,
                          renewalState: renewal, gracePeriodExpirationDate: graceEnds.map(at), signedDate: signed.map(at))
    }

    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let facts: [SubscriptionFacts]
        var role: SubscriptionRole = .student
        var firstSyncSucceeded = true
        var isSampleMode = false
        let expected: EntitlementState
        var testDescription: String { name }
    }

    static let cases: [Case] = [
        // Sample mode and the first sync
        Case(name: "sample mode is .demo, even with an active subscription", facts: [fact()], isSampleMode: true,
             expected: .demo),
        Case(name: "no transaction before the first sync: .preview", facts: [], firstSyncSucceeded: false, expected: .preview),
        Case(name: "no transaction after the first sync: .preview (never subscribed)", facts: [], expected: .preview),
        Case(name: "an active subscription before the first sync is entitled", facts: [fact()], firstSyncSucceeded: false,
             expected: .entitled(until: at(30 * day))),

        // Verification
        Case(name: "a verified active subscription is entitled to its expiry", facts: [fact()],
             expected: .entitled(until: at(30 * day))),
        Case(name: "unverified input never entitles", facts: [fact(verified: false)], expected: .preview),
        Case(name: "an unverified refund is ignored, not a lapse", facts: [fact(verified: false, revoked: -day)],
             expected: .preview),
        Case(name: "an unverified transaction beside a verified one changes nothing",
             facts: [fact(expires: 5 * day), fact(verified: false, expires: 300 * day)], expected: .entitled(until: at(5 * day))),

        // Refunds and revocation
        Case(name: "a refund lapses at its revocation date", facts: [fact(revoked: -2 * day)],
             expected: .lapsed(since: at(-2 * day))),
        Case(name: "a refund before the first sync is .preview (the first sync stays free)",
             facts: [fact(revoked: -2 * day)], firstSyncSucceeded: false, expected: .preview),
        Case(name: "a revocation dated after the device's now still lapses", facts: [fact(revoked: 60)],
             expected: .lapsed(since: at(60))),
        Case(name: "renewal state revoked without a revocation date lapses now",
             facts: [fact(expires: 20 * day, renewal: .revoked)], expected: .lapsed(since: now)),

        // Boundary times: a settled expiry ends access exactly at the expiry
        Case(name: "settled expiry exactly at now: lapsed", facts: [fact(expires: 0, renewal: .expired)],
             expected: .lapsed(since: now)),
        Case(name: "settled expiry one second after now: entitled", facts: [fact(expires: 1, renewal: .expired)],
             expected: .entitled(until: at(1))),
        Case(name: "subscribed, expiring one second after now: entitled", facts: [fact(expires: 1, renewal: .subscribed)],
             expected: .entitled(until: at(1))),

        // The offline grace: StoreKit cannot say whether it renewed
        Case(name: "unknown renewal, expired one second ago: entitled within the offline grace",
             facts: [fact(expires: -1)], expected: .entitled(until: at(-1))),
        Case(name: "unknown renewal, one second inside the grace: entitled",
             facts: [fact(expires: -(grace - 1))], expected: .entitled(until: at(-(grace - 1)))),
        Case(name: "unknown renewal, exactly the grace after expiry: lapsed (fails closed)",
             facts: [fact(expires: -grace)], expected: .lapsed(since: at(-grace))),
        Case(name: "subscribed status over a stale expired transaction: entitled within the grace",
             facts: [fact(expires: -day, renewal: .subscribed)], expected: .entitled(until: at(-day))),

        // Billing: grace period and retry
        Case(name: "billing grace period: entitled until the grace period ends",
             facts: [fact(expires: -day, renewal: .inGracePeriod, graceEnds: 15 * day)], expected: .entitled(until: at(15 * day))),
        Case(name: "grace period past its end and the offline grace: lapsed at its end",
             facts: [fact(expires: -20 * day, renewal: .inGracePeriod, graceEnds: -10 * day)],
             expected: .lapsed(since: at(-10 * day))),
        Case(name: "grace period with no verified end: the expiry and the offline grace",
             facts: [fact(expires: -day, renewal: .inGracePeriod)], expected: .entitled(until: at(-day))),
        Case(name: "billing retry: lapsed since the expiry, no offline grace",
             facts: [fact(expires: -60, renewal: .inBillingRetryPeriod)], expected: .lapsed(since: at(-60))),
        Case(name: "renewal state expired: lapsed at once, no offline grace", facts: [fact(expires: -60, renewal: .expired)],
             expected: .lapsed(since: at(-60))),

        // Roles: a parent plan never unlocks the student role, and the reverse
        Case(name: "a parent plan never unlocks the student role", facts: [fact(parent)], expected: .preview),
        Case(name: "a student plan never unlocks the parent role", facts: [fact(student)], role: .parent,
             expected: .preview),
        Case(name: "holding both, the parent role sees the parent plan's expiry",
             facts: [fact(student, expires: 300 * day), fact(parent, expires: 40 * day)], role: .parent,
             expected: .entitled(until: at(40 * day))),
        Case(name: "a lapsed parent plan does not lapse the student role",
             facts: [fact(parent, revoked: -day)], expected: .preview),

        // What does not count
        Case(name: "an upgraded transaction is ignored", facts: [fact(upgraded: true)], expected: .preview),
        Case(name: "family sharing is off: a shared transaction is ignored", facts: [fact(ownership: .familyShared)],
             expected: .preview),
        Case(name: "any other ownership is ignored (fails closed)", facts: [fact(ownership: .other)], expected: .preview),
        Case(name: "an unknown product is ignored", facts: [fact("dev.tally-app.tally.monthly")], expected: .preview),
        Case(name: "a transaction with no expiry entitles nothing", facts: [fact(expires: nil)], expected: .preview),

        // Several transactions
        Case(name: "the latest end wins", facts: [fact(expires: 10 * day), fact(expires: 375 * day), fact(expires: -5 * day)],
             expected: .entitled(until: at(375 * day))),
        Case(name: "an active renewal beside a refunded earlier period is entitled",
             facts: [fact(revoked: -100 * day), fact(expires: 200 * day)], expected: .entitled(until: at(200 * day))),
        Case(name: "two lapses: the latest one is reported", facts: [fact(revoked: -9 * day), fact(expires: -30 * day, renewal: .expired)],
             expected: .lapsed(since: at(-9 * day))),

        // Clock skew: the newest App Store signed date is a time the App Store reached
        Case(name: "clock set back: a signed date after the expiry ends access",
             facts: [fact(expires: 10 * day, renewal: .expired, signed: 11 * day)], expected: .lapsed(since: at(10 * day))),
        Case(name: "clock set back past the offline grace: lapsed",
             facts: [fact(expires: 2 * day, signed: 6 * day)], expected: .lapsed(since: at(2 * day))),
        Case(name: "a device clock a little behind the App Store keeps an active subscription",
             facts: [fact(expires: 30 * day, renewal: .subscribed, signed: 90)], expected: .entitled(until: at(30 * day))),
        Case(name: "an unverified signed date never moves the clock",
             facts: [fact(expires: 2 * day, renewal: .expired), fact(verified: false, expires: 1, signed: 400 * day)],
             expected: .entitled(until: at(2 * day))),
        Case(name: "the other role's signed date never moves this role's clock",
             facts: [fact(expires: 2 * day, renewal: .expired), fact(parent, expires: 300 * day, signed: 30 * day)],
             expected: .entitled(until: at(2 * day))),
    ]

    @Test("One case per rule and boundary", arguments: cases)
    func evaluate(_ testCase: Case) {
        let state = EntitlementPolicy.evaluate(testCase.facts, role: testCase.role, products: Self.products,
                                               firstSyncSucceeded: testCase.firstSyncSucceeded,
                                               isSampleMode: testCase.isSampleMode, now: Self.now)
        #expect(state == testCase.expected)
    }

    @Test("The case table covers at least 20 cases (pricing-licensing.md PAY-02)")
    func enoughCases() {
        #expect(Self.cases.count >= 20)
    }

    @Test("The order of the transactions never changes the answer")
    func orderIndependent() {
        let facts = [Self.fact(revoked: -100 * Self.day), Self.fact(expires: 200 * Self.day),
                     Self.fact(Self.parent, expires: 50 * Self.day), Self.fact(verified: false, expires: 999 * Self.day),
                     Self.fact(expires: -2 * Self.day, renewal: .expired)]
        let forward = EntitlementPolicy.evaluate(facts, role: .student, products: Self.products, firstSyncSucceeded: true,
                                                 isSampleMode: false, now: Self.now)
        let backward = EntitlementPolicy.evaluate(facts.reversed(), role: .student, products: Self.products,
                                                  firstSyncSucceeded: true, isSampleMode: false, now: Self.now)
        #expect(forward == backward && forward == .entitled(until: Self.at(200 * Self.day)))
    }

    @Test("The account's state (what the gate decides with) lapses whatever the session; inSession applies rules 1 and 7")
    func accountStateAndSession() {
        let refunded = [Self.fact(revoked: -2 * Self.day)]
        let account = EntitlementPolicy.accountState(refunded, role: .student, products: Self.products, now: Self.now)
        #expect(account == .lapsed(since: Self.at(-2 * Self.day)))
        #expect(account.inSession(isSampleMode: false, firstSyncSucceeded: true) == account)
        #expect(account.inSession(isSampleMode: false, firstSyncSucceeded: false) == .preview)
        #expect(account.inSession(isSampleMode: true, firstSyncSucceeded: true) == .demo)
        let entitled = EntitlementState.entitled(until: Self.at(Self.day))
        #expect(entitled.inSession(isSampleMode: false, firstSyncSucceeded: false) == entitled)
        #expect(EntitlementState.preview.inSession(isSampleMode: false, firstSyncSucceeded: true) == .preview)
    }

    @Test("A shorter offline grace is honoured (the constant is the only source)")
    func offlineGraceIsAParameter() {
        let state = EntitlementPolicy.evaluate([Self.fact(expires: -2 * Self.day)], role: .student, products: Self.products,
                                               firstSyncSucceeded: true, isSampleMode: false, now: Self.now,
                                               offlineGrace: .seconds(24 * 60 * 60))
        #expect(state == .lapsed(since: Self.at(-2 * Self.day)))
        #expect(SubscriptionConfig.offlineGracePeriod == .seconds(3 * 24 * 60 * 60))
    }
}

/// PAY-01: the product IDs derive from the bundle ID, and only an exact ID maps to a role.
@Suite("SubscriptionProducts (PAY-01): IDs from the bundle ID")
struct SubscriptionProductsTests {
    @Test("<bundle-id>.annual and <bundle-id>.parent.annual")
    func productIDs() {
        let products = SubscriptionProducts(bundleID: "dev.tally-app.tally")
        #expect(products.studentAnnual == "dev.tally-app.tally.annual")
        #expect(products.parentAnnual == "dev.tally-app.tally.parent.annual")
        #expect(products.all == [products.studentAnnual, products.parentAnnual])
        #expect(products.productID(for: .student) == products.studentAnnual)
        #expect(products.productID(for: .parent) == products.parentAnnual)
    }

    @Test("Roles by exact ID: the parent ID also ends in .annual, and unknown IDs have no role")
    func rolesByExactID() {
        let products = SubscriptionProducts(bundleID: "dev.tally-app.tally")
        #expect(products.role(of: "dev.tally-app.tally.annual") == .student)
        #expect(products.role(of: "dev.tally-app.tally.parent.annual") == .parent)
        #expect(products.role(of: "com.example.tally.annual") == nil)
        #expect(products.role(of: "dev.tally-app.tally.annual.extra") == nil)
        #expect(products.role(of: "") == nil)
    }
}
