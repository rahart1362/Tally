import Foundation
import Observation
import SwiftUI
import TallyDesignSystem
import TallyDomain
import TallyStrings

/// EB-21 (Cal. B&P 17602(a)(3) [U4]; NY 527-a [U6]; Minn. 325G.57 [U7]): the retainable purchase
/// confirmation, shown once right after a direct purchase or trial start
/// (`SubscriptionModel.justPurchased`, set by `PaywallModel.purchase()` -- never after a restore or
/// a redeemed code) and re-findable afterwards from Settings → Subscription's own "View Purchase
/// Confirmation" row (`SubscriptionSettingsView`).
///
/// Every fact -- the plan, the amount and period, the renewal date and how to cancel -- is read
/// fresh from the current entitlement and the App Store's own offer, never stored on its own: there
/// is nothing here to go stale, and nothing new to keep secret-free (rule 7).
struct PurchaseConfirmationView: View {
    @State private var model: PurchaseConfirmationModel
    @Environment(\.dismiss) private var dismiss

    init(subscription: SubscriptionModel, storefront: any SubscriptionStorefront) {
        _model = State(initialValue: PurchaseConfirmationModel(subscription: subscription, storefront: storefront))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: TallySpacing.xl) {
                    // `TallyTypography.stateSymbol`: the same large-symbol scale as an empty or
                    // error state's icon (`TallyUnavailableView`), so the size is a named token
                    // rather than a one-off magic number.
                    Image(systemName: "checkmark.circle.fill")
                        .font(TallyTypography.stateSymbol)
                        .foregroundStyle(TallyColor.accent)
                        .accessibilityHidden(true)
                    Text(L10n.Subscription.confirmationTitle())
                        .font(TallyTypography.sectionHeader)
                        .foregroundStyle(TallyColor.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("confirmation.title")
                    VStack(alignment: .leading, spacing: TallySpacing.sm) {
                        LabeledContent(String(localized: L10n.Subscription.planLabel()), value: model.planName)
                            .accessibilityIdentifier("confirmation.plan")
                        if let amount = model.amountText {
                            LabeledContent(String(localized: L10n.Subscription.confirmationAmountLabel()), value: amount)
                                .accessibilityIdentifier("confirmation.amount")
                        }
                        if let renews = model.renewsDateText {
                            LabeledContent(String(localized: L10n.Subscription.confirmationRenewsLabel()), value: renews)
                                .accessibilityIdentifier("confirmation.renews")
                        }
                    }
                    .labeledContentStyle(.tallySecondaryValue)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let detail = model.renewalDetailText {
                        Text(verbatim: detail)
                            .font(TallyTypography.body)
                            .foregroundStyle(TallyColor.textPrimary)
                            .accessibilityIdentifier("confirmation.renewalDetail")
                    }
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, TallySpacing.screenMargin)
                .padding(.vertical, TallySpacing.xl)
                .frame(maxWidth: .infinity)
            }
            .background(TallyColor.bgCanvas)
            .tallyScreenChrome()
            .accessibilityIdentifier("confirmation.root")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: L10n.Subscription.confirmationDone())) { dismiss() }
                        .accessibilityIdentifier("confirmation.done")
                }
            }
        }
        .task { await model.load() }
    }
}

/// EB-21: the confirmation's facts, read fresh each time it opens -- never persisted (there is
/// nothing to go stale, and nothing new to keep secret-free).
@MainActor
@Observable
final class PurchaseConfirmationModel {
    /// Explicit and nonisolated (plan 06 A2), like every model in this module.
    nonisolated deinit {}

    @ObservationIgnored let subscription: SubscriptionModel
    @ObservationIgnored private let storefront: any SubscriptionStorefront
    @ObservationIgnored private let role = SubscriptionRole.student
    private(set) var offer: SubscriptionOffer?

    init(subscription: SubscriptionModel, storefront: any SubscriptionStorefront) {
        self.subscription = subscription
        self.storefront = storefront
    }

    /// The App Store's own offer, for the amount and the renewal disclosure's price. A purchase
    /// already granted the entitlement (`SubscriptionModel.recordDirectPurchase()` only follows a
    /// `.purchased` outcome), so loading here is read-only: nothing this screen does can fail the
    /// purchase itself.
    func load() async {
        offer = await storefront.offer(for: role)
    }

    var planName: String { String(localized: L10n.Subscription.name()) }

    /// "$9.99/year", once the offer has loaded.
    var amountText: String? {
        offer.map(SubscriptionOfferText.price)
    }

    /// The current entitlement's renewal date, formatted the same way Settings → Subscription
    /// formats one. `nil` before StoreKit's first answer this launch, or for a school-assigned
    /// seat's own wording (`SubscriptionSettingsView` does not offer this screen for one).
    var renewsDateText: String? {
        guard case .entitled(let until) = subscription.accountState else { return nil }
        return until.formatted(date: .abbreviated, time: .omitted)
    }

    /// "Renews automatically at $9.99/year until you cancel. Cancel anytime: …" -- the same
    /// EB-18 sentence the paywall shows, reused rather than restated under a second key.
    var renewalDetailText: String? {
        offer.map(SubscriptionOfferText.renewalAutoCancel)
    }
}
