import Foundation
import TallyDomain

/// PAY-05: what the paywall shows of a product, as plain values. **Every price is the App Store's
/// own text** (`Product.displayPrice`, already in the storefront's currency and format): the app
/// places it in a sentence and never formats, converts or computes a price.
public nonisolated struct SubscriptionOffer: Sendable, Equatable {
    /// A length of time (StoreKit's `Product.SubscriptionPeriod`).
    public struct Period: Sendable, Equatable {
        public enum Unit: String, Sendable, Equatable, CaseIterable {
            case day, week, month, year
        }

        public var value: Int
        public var unit: Unit

        public init(value: Int, unit: Unit) {
            self.value = value
            self.unit = unit
        }

        /// One year: the period whose price reads "$9.99/year".
        public var isOneYear: Bool { value == 1 && unit == .year }
    }

    /// The price of one period, as the App Store wrote it ("$9.99").
    public var displayPrice: String
    /// How long one period lasts.
    public var period: Period
    /// The introductory free trial's length, only when this Apple Account is eligible for it.
    public var freeTrial: Period?

    public init(displayPrice: String, period: Period, freeTrial: Period?) {
        self.displayPrice = displayPrice
        self.period = period
        self.freeTrial = freeTrial
    }
}

/// PAY-05 and PAY-08: the App Store as the paywall and Settings → Subscription use it, as a port.
/// The composition root injects `StoreKitStorefront`; tests and previews get `UnavailableStorefront`.
/// Purchases go through the subscription engine (`SubscriptionEngine.purchase`), which grants before
/// StoreKit's transaction is finished; the system sheets (Manage Subscription, Request a Refund,
/// Redeem Code) are SwiftUI modifiers the views attach.
public nonisolated protocol SubscriptionStorefront: Sendable {
    /// `role`'s offer, or nil when the App Store returned no product (offline, not configured).
    func offer(for role: SubscriptionRole) async -> SubscriptionOffer?
    /// Restore Purchases (`AppStore.sync()`): true when the App Store answered. The engine then
    /// re-verifies.
    func restorePurchases() async -> Bool
    /// The latest verified transaction of `role`'s product (`Transaction.ID`), for Request a Refund;
    /// nil when there is none.
    func refundableTransaction(for role: SubscriptionRole) async -> UInt64?
}

/// No App Store: no offer, nothing restored, nothing to refund. The default when the composition
/// root injects nothing (tests and previews), and in a Debug process that hosts TallyAppTests, whose
/// first StoreKit connection must be the StoreKit Testing suite's (M3-B1 report §2 D12).
public nonisolated struct UnavailableStorefront: SubscriptionStorefront {
    public init() {}
    public func offer(for role: SubscriptionRole) async -> SubscriptionOffer? { nil }
    public func restorePurchases() async -> Bool { false }
    public func refundableTransaction(for role: SubscriptionRole) async -> UInt64? { nil }
}
