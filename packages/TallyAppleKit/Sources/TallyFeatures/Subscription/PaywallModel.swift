import Foundation
import Observation
import TallyDomain
import TallyStrings

/// PAY-06: one request to show the paywall, and why (`AppModel.paywall`, or Settings' own).
public nonisolated struct PaywallRequest: Identifiable, Sendable, Equatable {
    public let id = UUID()
    public let trigger: PaywallTrigger

    public init(trigger: PaywallTrigger) {
        self.trigger = trigger
    }
}

/// PAY-05: one paywall's state: the App Store's offer, what the paywall says (`PaywallContent`, with
/// plan 08 G-6's variant for a school whose grades are not in Canvas), and the purchase or restore in
/// flight. Every App Store call runs off the main actor (the engine, the storefront); this model only
/// mirrors their answers. The purchase goes through `SubscriptionEngine.purchase`, which grants it
/// before StoreKit's transaction is finished (PAY-03).
@MainActor
@Observable
final class PaywallModel {
    /// Explicit and nonisolated (plan 06 A2): an implicit deinit in this default-`MainActor` module is
    /// main-actor isolated, which aborts iOS 26.0-26.3 runtimes (swiftlang/swift#88036).
    nonisolated deinit {}

    nonisolated enum Phase: Equatable, Sendable {
        case loading
        case ready(SubscriptionOffer)
        /// The App Store returned no product (offline, or nothing configured).
        case unavailable
    }

    /// What the paywall says after an action.
    nonisolated enum Notice: Equatable, Sendable {
        /// Ask to Buy: waiting for a parent's approval.
        case pending
        /// The purchase failed, could not be verified, or the product could not be loaded.
        case failed
        case nothingToRestore
        case restoreFailed
    }

    private(set) var phase: Phase = .loading
    private(set) var content: PaywallContent
    private(set) var notice: Notice?
    /// A purchase or a restore is in flight (the buttons wait).
    private(set) var isWorking = false
    let trigger: PaywallTrigger
    @ObservationIgnored let subscription: SubscriptionModel
    @ObservationIgnored private let storefront: any SubscriptionStorefront
    @ObservationIgnored private let school: SchoolGradeSummary
    @ObservationIgnored private let role = SubscriptionRole.student

    init(trigger: PaywallTrigger, school: SchoolGradeSummary, subscription: SubscriptionModel,
         storefront: any SubscriptionStorefront) {
        self.trigger = trigger
        self.school = school
        self.subscription = subscription
        self.storefront = storefront
        content = PaywallContent(school: school, isEligibleForTrial: false)
    }

    /// The trial or subscription is active on this Apple Account: a purchase, a restore, a redeemed
    /// code or an approved Ask to Buy. The paywall closes.
    var isComplete: Bool {
        subscription.accountState?.isActiveEntitlement == true
    }

    /// The purchase button works once the offer is on screen and nothing else is in flight.
    var canPurchase: Bool {
        guard !isWorking, case .ready = phase else { return false }
        return true
    }

    /// The offer, from the App Store (`.task`; again from "Try Again").
    func load() async {
        phase = .loading
        guard let offer = await storefront.offer(for: role) else {
            phase = .unavailable
            return
        }
        content = PaywallContent(school: school, isEligibleForTrial: offer.freeTrial != nil)
        phase = .ready(offer)
    }

    /// The purchase button.
    func purchase() async {
        guard !isWorking, case .ready = phase else { return }
        guard let engine = subscription.engine else {
            notice = .failed
            return
        }
        isWorking = true
        notice = nil
        let outcome = await engine.purchase(role)
        isWorking = false
        notice = Self.notice(after: outcome)
    }

    /// What the paywall says after a purchase ended this way (nothing when it worked or was cancelled).
    nonisolated static func notice(after outcome: SubscriptionPurchaseOutcome) -> Notice? {
        switch outcome {
        case .purchased, .cancelled: nil
        case .pending: .pending
        case .unverified, .unavailable, .failed: .failed
        }
    }

    /// Restore Purchases: the App Store syncs, then the engine re-verifies.
    func restore() async {
        guard !isWorking else { return }
        isWorking = true
        notice = nil
        let answered = await storefront.restorePurchases()
        await subscription.engine?.foreground()
        isWorking = false
        if !isComplete { notice = answered ? .nothingToRestore : .restoreFailed }
    }

    /// Redeem Code's sheet closed. StoreKit grants a redeemed code through `Transaction.updates`; the
    /// engine also re-verifies now, so the paywall closes without waiting for it.
    func codeRedemptionEnded() async {
        await subscription.engine?.foreground()
    }
}

/// How an offer reads (PAY-05): the App Store's price text placed in catalog sentences, never
/// reformatted. "$9.99/year" is the most prominent price.
nonisolated enum SubscriptionOfferText {
    /// "1 year", "1 month".
    static func period(_ period: SubscriptionOffer.Period) -> String {
        switch period.unit {
        case .day: String(localized: L10n.Subscription.days(period.value))
        case .week: String(localized: L10n.Subscription.weeks(period.value))
        case .month: String(localized: L10n.Subscription.days(period.value))
        case .year: String(localized: L10n.Subscription.years(period.value))
        }
    }

    /// "$9.99/year" (any other period: "$9.99 every 6 months").
    static func price(_ offer: SubscriptionOffer) -> String {
        offer.period.isOneYear
            ? String(localized: L10n.Subscription.pricePerYear(offer.displayPrice))
            : String(localized: L10n.Subscription.priceEvery(offer.displayPrice, period(offer.period)))
    }

    /// VoiceOver's reading of `price` ("$9.99 per year").
    static func spokenPrice(_ offer: SubscriptionOffer) -> String {
        offer.period.isOneYear
            ? String(localized: L10n.Subscription.pricePerYearSpoken(offer.displayPrice))
            : String(localized: L10n.Subscription.priceEvery(offer.displayPrice, period(offer.period)))
    }

    /// "Subscription length: 1 year".
    static func duration(_ offer: SubscriptionOffer) -> String {
        String(localized: L10n.Subscription.duration(period(offer.period)))
    }

    /// "1 month free, then $9.99/year", only with an eligible free trial.
    static func trial(_ offer: SubscriptionOffer) -> String? {
        guard let trial = offer.freeTrial else { return nil }
        return String(localized: L10n.Subscription.trial(period(trial), then: price(offer)))
    }
}
