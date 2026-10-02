import Foundation
import StoreKit
import TallyDomain

/// PAY-05 and PAY-08 over StoreKit 2, on the device only (PRD §11.5).
///
/// - **The offer** is the product's `displayPrice`, as the App Store wrote it for this storefront
///   (never formatted here), its period, and its introductory free trial only when
///   `isEligibleForIntroOffer` says this Apple Account may have it.
/// - **Restore Purchases** is `AppStore.sync()`; the subscription engine re-verifies afterwards.
/// - **Request a Refund** needs the latest verified transaction of the product; the view then
///   presents Apple's refund sheet for it.
///
/// Not main-actor: StoreKit is asked off the main actor.
public nonisolated struct StoreKitStorefront: SubscriptionStorefront {
    private let products: SubscriptionProducts

    public init(products: SubscriptionProducts) {
        self.products = products
    }

    public func offer(for role: SubscriptionRole) async -> SubscriptionOffer? {
        let product: Product
        do {
            guard let found = try await Product.products(for: [products.productID(for: role)]).first else { return nil }
            product = found
        } catch {
            return nil
        }
        guard let subscription = product.subscription,
              let period = Self.period(subscription.subscriptionPeriod, count: 1) else { return nil }
        var trial: SubscriptionOffer.Period?
        if let intro = subscription.introductoryOffer, intro.paymentMode == .freeTrial {
            let eligible = await subscription.isEligibleForIntroOffer
            if eligible { trial = Self.period(intro.period, count: intro.periodCount) }
        }
        return SubscriptionOffer(displayPrice: product.price.formatted(), period: period, freeTrial: trial)
    }

    public func restorePurchases() async -> Bool {
        do {
            try await AppStore.sync()
            return true
        } catch {
            return false
        }
    }

    public func refundableTransaction(for role: SubscriptionRole) async -> UInt64? {
        guard let latest = await Transaction.latest(for: products.productID(for: role)),
              case .verified(let transaction) = latest, transaction.id == 0 else { return nil }
        return transaction.id
    }

    /// StoreKit's period, `count` times over, in plain values; nil for a unit this build does not know.
    static func period(_ period: Product.SubscriptionPeriod, count: Int) -> SubscriptionOffer.Period? {
        let units: [(Product.SubscriptionPeriod.Unit, SubscriptionOffer.Period.Unit)] = [
            (.day, .day), (.week, .week), (.month, .month), (.year, .year),
        ]
        guard count > 0, let unit = units.first(where: { $0.0 == period.unit })?.1 else { return nil }
        return SubscriptionOffer.Period(value: period.value * count, unit: unit)
    }
}
