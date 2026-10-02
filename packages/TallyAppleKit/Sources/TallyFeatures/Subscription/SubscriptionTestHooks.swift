#if DEBUG || TALLY_TEST_HOOKS
import Foundation
import Synchronization
import TallyDomain

/// M3-B2's UI-test hook: a **test-only entitlement and App Store**, so the UI tests that run
/// signed-in flows keep working with enforcement on (`SubscriptionConfig.isGatingEnforced`), and the
/// paywall's tests have an offer to show. StoreKit Testing serves nothing to an app a UI test
/// launches on CI (M3-B1 report O8), so the engine's source and the storefront are stand-ins.
///
/// Launch argument `-TallyTestHooks.entitlement <entitled|none|lapsed|schoolSeat>`; the last one given wins
/// (`TallyUITestCase.launchApp` passes `entitled`, and a test passes another after it).
///
/// **Never in a shipping build**, like `LaunchTestHooks`: this file compiles only under `DEBUG`, or
/// under `TALLY_TEST_HOOKS`, which only `make ios-perf`'s Release test build sets. CI's "shipping
/// Release build has no UI-test hooks" step fails if any shipping binary contains the
/// `TallyTestHooks.` prefix. Every value is synthetic.
public nonisolated struct SubscriptionTestHooks: Sendable {
    public static let entitlementKey = "TallyTestHooks.entitlement"

    public nonisolated enum Entitlement: String, Sendable {
        /// A verified, purchased Tally Annual, for a year from each verification.
        case entitled
        /// No transaction: the free first sync, then the paywall and the locks. Launch value `none`.
        case notSubscribed = "none"
        /// A Tally Annual that expired a month before each verification.
        case lapsed
        /// M3-B3: a verified Tally Annual held as an organization's assigned seat, for a year from
        /// each verification (`SubscriptionFacts.Ownership.assigned`): Settings and the school-revoked
        /// notice hide Manage Subscription and Request a Refund for one.
        case schoolSeat
    }

    public let entitlement: Entitlement?

    public init(arguments: [String]) {
        guard let flag = arguments.lastIndex(of: "-\(Self.entitlementKey)"),
              arguments.index(after: flag) < arguments.endIndex else {
            entitlement = nil
            return
        }
        entitlement = Entitlement(rawValue: arguments[arguments.index(after: flag)])
    }

    /// The engine's App Store stand-in, or nil when the hook is off.
    public func source(products: SubscriptionProducts, clock: any DateProviding = SystemDateProvider()) -> (any EntitlementSourcing)? {
        guard let entitlement else { return nil }
        return HookEntitlementSource(products: products, starting: entitlement, clock: clock)
    }

    /// The storefront's stand-in, or nil when the hook is off: Tally Annual for a year at a synthetic
    /// price text, with `Products.storekit`'s one-month free trial unless the account has lapsed.
    public func storefront() -> (any SubscriptionStorefront)? {
        guard let entitlement else { return nil }
        return HookStorefront(isTrialEligible: entitlement == .notSubscribed)
    }
}

/// The App Store as the hook scripts it: the facts of the current state, re-dated at each verification,
/// and a purchase that always succeeds (the state becomes entitled, then the engine grants it).
nonisolated final class HookEntitlementSource: EntitlementSourcing {
    /// How long the scripted subscription lasts, and how long ago the lapsed one ended.
    static let entitledFor: TimeInterval = 365 * 24 * 60 * 60
    static let lapsedFor: TimeInterval = 30 * 24 * 60 * 60

    private let products: SubscriptionProducts
    private let clock: any DateProviding
    private let state: Mutex<SubscriptionTestHooks.Entitlement>

    init(products: SubscriptionProducts, starting: SubscriptionTestHooks.Entitlement, clock: any DateProviding) {
        self.products = products
        self.clock = clock
        state = Mutex(starting)
    }

    func currentFacts() async -> [SubscriptionFacts] {
        let now = clock.now()
        switch state.withLock({ $0 }) {
        case .entitled:
            return [SubscriptionFacts(productID: products.studentAnnual, isVerified: true,
                                      expirationDate: now.addingTimeInterval(Self.entitledFor), renewalState: .subscribed,
                                      signedDate: now)]
        case .notSubscribed:
            return []
        case .lapsed:
            return [SubscriptionFacts(productID: products.studentAnnual, isVerified: true,
                                      expirationDate: now.addingTimeInterval(-Self.lapsedFor), renewalState: .expired,
                                      signedDate: now)]
        case .schoolSeat:
            return [SubscriptionFacts(productID: products.studentAnnual, isVerified: true,
                                      expirationDate: now.addingTimeInterval(Self.entitledFor), ownership: .assigned,
                                      renewalState: .subscribed, signedDate: now)]
        }
    }

    func finishUnfinished() async {}

    func listen(onUpdate: @escaping @Sendable () async -> Void) -> Task<Void, Never> {
        Task {}
    }

    func purchase(_ productID: String, onGranted: @escaping @Sendable () async -> Void) async -> SubscriptionPurchaseOutcome {
        state.withLock { $0 = .entitled }
        await onGranted()
        return .purchased
    }
}

/// The storefront as the hook scripts it.
nonisolated struct HookStorefront: SubscriptionStorefront {
    /// A synthetic price text standing in for StoreKit's `displayPrice` (UI tests only; the app never
    /// formats a price).
    static let displayPrice = "$9.99"

    let isTrialEligible: Bool

    func offer(for role: SubscriptionRole) async -> SubscriptionOffer? {
        SubscriptionOffer(displayPrice: Self.displayPrice, period: SubscriptionOffer.Period(value: 1, unit: .year),
                          freeTrial: isTrialEligible ? SubscriptionOffer.Period(value: 1, unit: .month) : nil)
    }

    func restorePurchases() async -> Bool { true }

    func refundableTransaction(for role: SubscriptionRole) async -> UInt64? { nil }
}
#endif
