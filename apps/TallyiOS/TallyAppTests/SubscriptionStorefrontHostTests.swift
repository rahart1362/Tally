#if DEBUG
import Foundation
import Testing
import TallyDomain
@testable import Tally
@testable import TallyFeatures

/// M3-B2: the paywall's App Store follows the engine's rule (M3-B1 report §2 D12): in a Debug process
/// that hosts TallyAppTests it is `UnavailableStorefront`, so nothing touches StoreKit before the
/// StoreKit Testing suite does; any app process gets StoreKit. DEBUG only: the rule's test-host branch
/// is compiled only there.
@Suite("M3-B2: the paywall's App Store in the test host and in the app")
struct SubscriptionStorefrontHostTests {
    @Test("This process gets no StoreKit storefront; an app process gets StoreKit's")
    func testHostGetsNoStorefront() {
        let products = SubscriptionProducts(bundleID: "dev.tally-app.tally")
        #expect(ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil)
        #expect(AppEnvironment.storefront(products: products) is UnavailableStorefront)
        #expect(AppEnvironment.storefront(products: products, environment: [:]) is StoreKitStorefront)
    }
}
#endif
