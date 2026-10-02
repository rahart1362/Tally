import Foundation
import Observation
import TallyDomain
import TallyStrings

/// PAY-08, PAY-10, PAY-11: the App Store's own sheets and Restore Purchases, for Settings →
/// Subscription, the school-revoked notice and the Sign out & erase confirmation. Each action sets
/// the flag its system sheet is bound to (`manageSubscriptionsSheet`, `offerCodeRedemption`,
/// `refundRequestSheet`): the views attach the sheets, so the triggers are testable without them.
/// Tally never cancels or refunds anything itself: Apple's sheets do.
@MainActor
@Observable
final class SubscriptionActionsModel {
    /// Explicit and nonisolated (plan 06 A2), like every model in this module.
    nonisolated deinit {}

    nonisolated enum Notice: Equatable, Sendable {
        /// Request a Refund found no Tally purchase on this Apple Account.
        case noRefund
        case nothingToRestore
        case restoreFailed
    }

    /// Manage Subscription (`AppStore.showManageSubscriptions`, as a SwiftUI sheet).
    var presentsManage = false
    /// Redeem Code (`offerCodeRedemption`).
    var presentsRedeem = false
    /// Request a Refund (`refundRequestSheet`) for `refundTransactionID`.
    var presentsRefund = false
    private(set) var refundTransactionID: UInt64?
    private(set) var notice: Notice?
    private(set) var isWorking = false
    @ObservationIgnored let subscription: SubscriptionModel
    @ObservationIgnored private let storefront: any SubscriptionStorefront
    @ObservationIgnored private let role = SubscriptionRole.student

    init(subscription: SubscriptionModel, storefront: any SubscriptionStorefront) {
        self.subscription = subscription
        self.storefront = storefront
    }

    /// One of Apple's sheets is up.
    var isPresentingSheet: Bool {
        presentsManage || presentsRedeem || presentsRefund
    }

    func manage() {
        notice = nil
        presentsManage = true
    }

    func redeem() {
        notice = nil
        presentsRedeem = true
    }

    /// Finds the purchase to refund, then presents Apple's refund sheet for it.
    func requestRefund() async {
        guard !isWorking else { return }
        notice = nil
        isWorking = true
        let transaction = await storefront.refundableTransaction(for: role)
        isWorking = false
        guard let transaction else {
            notice = .noRefund
            return
        }
        refundTransactionID = transaction
        presentsRefund = true
    }

    /// Restore Purchases: the App Store syncs, then the engine re-verifies.
    func restore() async {
        guard !isWorking else { return }
        notice = nil
        isWorking = true
        let answered = await storefront.restorePurchases()
        await subscription.engine?.foreground()
        isWorking = false
        if subscription.accountState?.isActiveEntitlement != true {
            notice = answered ? .nothingToRestore : .restoreFailed
        }
    }

    /// One of Apple's sheets closed (a cancellation, a refund, a redeemed code): the engine re-verifies.
    func sheetClosed() async {
        await subscription.engine?.foreground()
    }
}

/// Settings → Subscription's words for the account's state (the Apple Account's, not the session's:
/// in sample mode a purchase still shows as active).
nonisolated enum SubscriptionStatusText {
    /// M3-B3: `holding` picks the entitled wording; `nil` (not yet known) and `.purchase` read the
    /// same, today's "Active until %@" (PAY-08's original text).
    static func status(_ state: EntitlementState?, holding: SubscriptionHolding? = nil, isPurchasePending: Bool) -> String {
        if isPurchasePending, state?.isActiveEntitlement != true {
            return String(localized: L10n.Subscription.statusPending())
        }
        switch state {
        case nil:
            return String(localized: L10n.Subscription.statusChecking())
        case .demo?, .preview?:
            return String(localized: L10n.Subscription.statusNotSubscribed())
        case .entitled(let until)?:
            let date = until.formatted(date: .abbreviated, time: .omitted)
            // MUTATION-CM-UI-05 (temporary, reverted after the CI mutation run)
            return holding == .purchase ? String(localized: L10n.Subscription.statusSchool(until: date))
                                        : String(localized: L10n.Subscription.statusActive(until: date))
        case .lapsed(let since)?:
            return String(localized: L10n.Subscription.statusEnded(since.formatted(date: .abbreviated, time: .omitted)))
        }
    }
}
