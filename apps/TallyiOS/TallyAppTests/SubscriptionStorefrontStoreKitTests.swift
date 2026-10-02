#if DEBUG
import Foundation
import StoreKit
import StoreKitTest
import Testing
import TallyDomain
@testable import TallyFeatures

/// M3-B2 (PAY-05, PAY-08) over the real StoreKit, through StoreKit Testing, as a scenario of M3-B1's
/// suite (its `Stage`, its serialization and its probe, so it runs wherever that suite runs: on CI,
/// the iOS 26.2 floor). The paywall's offer is `Product.displayPrice` as StoreKit wrote it, the
/// subscription's year, and the one-month free trial while the Apple Account is eligible; Request a
/// Refund finds the purchase's transaction.
extension SubscriptionStoreKitTests {
    @Test("PAY-05, PAY-08: the storefront's offer is StoreKit's own displayPrice, a year and the trial; a purchase can be refunded")
    func storefrontOffer() async throws {
        let stage = try await Stage.make()
        let storefront = StoreKitStorefront(products: Self.products)
        let offer = try #require(await storefront.offer(for: .student), "StoreKit Testing returned no offer")
        let product = try #require(try await Product.products(for: [Self.products.studentAnnual]).first)
        #expect(offer.displayPrice == product.displayPrice, "the price is not the App Store's own text")
        #expect(offer.period == SubscriptionOffer.Period(value: 1, unit: .year))
        #expect(offer.freeTrial == SubscriptionOffer.Period(value: 1, unit: .month), "a new Apple Account is offered the trial")
        #expect(await storefront.refundableTransaction(for: .student) == nil, "a refund with nothing bought")
        _ = try await stage.purchased()
        #expect(await storefront.refundableTransaction(for: .student) != nil, "the purchase has no transaction to refund")
        await stage.end()
    }
}
#endif
