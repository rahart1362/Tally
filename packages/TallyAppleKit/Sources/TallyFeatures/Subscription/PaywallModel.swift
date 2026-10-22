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
        // EB-21: a direct purchase or trial start (never a restore or a redeemed code, which never
        // call this method) -- the shared `SubscriptionModel` carries the one-shot signal so either
        // presenter (the Home's sheet, Settings → Subscription's own) shows the retainable
        // confirmation once the paywall has closed.
        if case .purchased = outcome { subscription.recordDirectPurchase() }
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
        case .month: String(localized: L10n.Subscription.months(period.value))
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

    /// "2 weeks free, then $9.99/year" (EB-19), only with an eligible free trial.
    static func trial(_ offer: SubscriptionOffer) -> String? {
        guard let trial = offer.freeTrial else { return nil }
        return String(localized: L10n.Subscription.trial(period(trial), then: price(offer)))
    }

    // MARK: - EB-18: the renewal disclosure, clear and conspicuous next to the purchase button

    /// EB-18: `now` plus the trial's length, in Gregorian/UTC calendar math so the result does not
    /// depend on the device's own calendar or time zone -- a pure function so the date math is
    /// unit-testable apart from the view (never `Date()`/`Calendar.current` in a view body,
    /// `scripts/ci/check_view_bodies.py`). `nil` with no trial.
    static func trialEndDate(_ offer: SubscriptionOffer, now: Date) -> Date? {
        guard let trial = offer.freeTrial else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let component: Calendar.Component
        switch trial.unit {
        case .day: component = .day
        case .week: component = .weekOfYear
        case .month: component = .month
        case .year: component = .year
        }
        return calendar.date(byAdding: component, value: trial.value, to: now)
    }

    /// `trialEndDate`, formatted the same way Settings → Subscription formats a renewal date
    /// (`.formatted(date: .abbreviated, time: .omitted)`, the device's own locale and calendar for
    /// display -- only the math above is pinned to UTC/Gregorian).
    static func trialEndDateText(_ offer: SubscriptionOffer, now: Date) -> String? {
        trialEndDate(offer, now: now).map { $0.formatted(date: .abbreviated, time: .omitted) }
    }

    /// "Your free trial ends Nov 21, 2026. Unless you cancel at least 24 hours before, you're then
    /// charged $9.99/year." `nil` without an eligible trial.
    static func trialEndsThenCharged(_ offer: SubscriptionOffer, now: Date) -> String? {
        guard let date = trialEndDateText(offer, now: now) else { return nil }
        return String(localized: L10n.Subscription.trialEndsThenCharged(date, then: price(offer)))
    }

    /// "Renews automatically at $9.99/year until you cancel. Cancel anytime: …" -- replaces the old
    /// footnote-size, secondary-colour `subscription.paywall.renewal` (EB-18).
    static func renewalAutoCancel(_ offer: SubscriptionOffer) -> String {
        String(localized: L10n.Subscription.renewalAutoCancel(price(offer)))
    }
}
