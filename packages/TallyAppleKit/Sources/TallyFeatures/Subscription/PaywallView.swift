import StoreKit
import SwiftUI
import TallyDesignSystem
import TallyDomain
import TallyStrings

/// PAY-05: the paywall, as a sheet. Its parts, each with an accessibility identifier the UI tests
/// assert:
/// - the name ("Tally Annual") and the subscription's length;
/// - what's included (plan 08 G-6: no grade claim for a school whose grades are not in Canvas);
/// - **"$9.99/year" as the most prominent price**: the App Store's `displayPrice`, never formatted
///   here; then, only when this Apple Account is eligible, "1 month free, then $9.99/year"; and the
///   auto-renewal note;
/// - the purchase button, Restore Purchases, Redeem Code (Apple's sheet), and the Terms of Use and
///   Privacy Policy links;
/// - "Not Now".
///
/// Every text is a Dynamic Type style and the content scrolls, so it works at the largest
/// accessibility size (AX5); VoiceOver reads the price as "$9.99 per year". It closes by itself once
/// the trial or subscription is active (a purchase, a restore, a redeemed code or an approved Ask to
/// Buy). Presented by the Home (`HomeShellView`'s one sheet) and by Settings → Subscription.
struct PaywallView: View {
    @State private var model: PaywallModel
    @State private var presentsRedeem = false
    @Environment(\.dismiss) private var dismiss

    init(model: PaywallModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: TallySpacing.xxl) {
                    PaywallHeader(model: model)
                    PaywallFeatures(features: model.content.features)
                    PaywallOffer(model: model)
                    PaywallActions(model: model, onRedeem: { presentsRedeem = true })
                    PaywallLegalLinks()
                }
                .padding(.horizontal, TallySpacing.screenMargin)
                .padding(.vertical, TallySpacing.xl)
                .frame(maxWidth: .infinity)
            }
            .background(TallyColor.bgCanvas)
            .accessibilityIdentifier("paywall.root")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: L10n.Subscription.notNow())) { dismiss() }
                        .accessibilityIdentifier("paywall.close")
                }
            }
        }
        .task { await model.load() }
        .onChange(of: model.isComplete) { _, isComplete in
            if isComplete { dismiss() }
        }
        // Apple's Redeem Code sheet. A redeemed code is granted through `Transaction.updates`; when the
        // sheet closes the engine also re-verifies. The completion is `@Sendable` (no actor), so it is
        // safe whichever thread StoreKit calls it on.
        .offerCodeRedemption(isPresented: $presentsRedeem, onCompletion: { @Sendable _ in })
        .onChange(of: presentsRedeem) { _, isPresented in
            if !isPresented { Task { await model.codeRedemptionEnded() } }
        }
    }
}

/// The mark, the name and the length.
private struct PaywallHeader: View {
    let model: PaywallModel

    var body: some View {
        VStack(spacing: TallySpacing.md) {
            TMark(size: 56)
                .padding(TallySpacing.sm)
                .background(TallyColor.bgBrand, in: RoundedRectangle(cornerRadius: TallyRadius.tile, style: .continuous))
            Text(L10n.Subscription.name())
                .font(TallyTypography.sectionHeader)
                .foregroundStyle(TallyColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("paywall.name")
            if case .ready(let offer) = model.phase {
                Text(verbatim: SubscriptionOfferText.duration(offer))
                    .font(TallyTypography.subheadline)
                    .foregroundStyle(TallyColor.textSecondary)
                    .accessibilityIdentifier("paywall.duration")
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// What's included, in `PaywallContent`'s order.
private struct PaywallFeatures: View {
    let features: [PaywallContent.Feature]

    var body: some View {
        VStack(alignment: .leading, spacing: TallySpacing.md) {
            Text(L10n.Subscription.includedHeader())
                .font(TallyTypography.cardTitle)
                .foregroundStyle(TallyColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            ForEach(features, id: \.self) { feature in
                HStack(alignment: .firstTextBaseline, spacing: TallySpacing.md) {
                    Image(systemName: Self.symbol(feature))
                        .foregroundStyle(TallyColor.accent)
                        .accessibilityHidden(true)
                    Text(Self.text(feature))
                        .font(TallyTypography.body)
                        .foregroundStyle(TallyColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("paywall.feature.\(feature.rawValue)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func text(_ feature: PaywallContent.Feature) -> LocalizedStringResource {
        switch feature {
        case .grades: L10n.Subscription.featureGrades()
        case .dueDates: L10n.Subscription.featureDueDates()
        case .reminders: L10n.Subscription.featureReminders()
        case .insights: L10n.Subscription.featureInsights()
        case .workload: L10n.Subscription.featureWorkload()
        case .privacy: L10n.Subscription.featurePrivacy()
        }
    }

    static func symbol(_ feature: PaywallContent.Feature) -> String {
        switch feature {
        case .grades: "graduationcap"
        case .dueDates: "calendar"
        case .reminders: "bell"
        case .insights, .workload: "chart.xyaxis.line"
        case .privacy: "lock.shield"
        }
    }
}

/// The price block: "$9.99/year" (the most prominent price), the trial line when eligible, the
/// renewal note. While the App Store answers, a progress indicator; with no answer, Try Again.
private struct PaywallOffer: View {
    let model: PaywallModel

    var body: some View {
        VStack(spacing: TallySpacing.sm) {
            switch model.phase {
            case .loading:
                ProgressView {
                    Text(L10n.Subscription.loading())
                }
                .accessibilityIdentifier("paywall.loading")
            case .unavailable:
                Text(L10n.Subscription.unavailable())
                    .font(TallyTypography.body)
                    .foregroundStyle(TallyColor.textSecondary)
                    .accessibilityIdentifier("paywall.unavailable")
                Button(String(localized: L10n.Subscription.tryAgain())) {
                    Task { await model.load() }
                }
                .buttonStyle(.tallySecondary)
                .accessibilityIdentifier("paywall.tryAgain")
            case .ready(let offer):
                Text(verbatim: SubscriptionOfferText.price(offer))
                    .font(TallyTypography.screenTitle)
                    .foregroundStyle(TallyColor.textPrimary)
                    .accessibilityLabel(Text(verbatim: SubscriptionOfferText.spokenPrice(offer)))
                    .accessibilityIdentifier("paywall.price")
                if model.content.showsTrial, let trial = SubscriptionOfferText.trial(offer) {
                    Text(verbatim: trial)
                        .font(TallyTypography.body)
                        .foregroundStyle(TallyColor.textPrimary)
                        .accessibilityIdentifier("paywall.trial")
                }
                Text(L10n.Subscription.renewal())
                    .font(TallyTypography.footnote)
                    .foregroundStyle(TallyColor.textSecondary)
                    .accessibilityIdentifier("paywall.renewal")
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The purchase button, Restore Purchases and Redeem Code, and what an action said.
private struct PaywallActions: View {
    let model: PaywallModel
    let onRedeem: () -> Void

    var body: some View {
        VStack(spacing: TallySpacing.md) {
            if let notice = model.notice {
                Text(Self.text(notice))
                    .font(TallyTypography.footnote)
                    .foregroundStyle(TallyColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("paywall.notice")
            }
            Button {
                Task { await model.purchase() }
            } label: {
                Text(model.content.action == .startFreeTrial ? L10n.Subscription.startFreeTrial() : L10n.Subscription.subscribe())
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.tallyPrimary)
            .disabled(!model.canPurchase)
            .accessibilityIdentifier("paywall.purchase")
            Button(String(localized: L10n.Subscription.restorePurchases())) {
                Task { await model.restore() }
            }
            .disabled(model.isWorking)
            .accessibilityIdentifier("paywall.restore")
            Button(String(localized: L10n.Subscription.redeemCode()), action: onRedeem)
                .accessibilityIdentifier("paywall.redeem")
        }
        .font(TallyTypography.body)
    }

    static func text(_ notice: PaywallModel.Notice) -> LocalizedStringResource {
        switch notice {
        case .pending: L10n.Subscription.pending()
        case .failed: L10n.Subscription.failed()
        case .nothingToRestore: L10n.Subscription.nothingToRestore()
        case .restoreFailed: L10n.Subscription.restoreFailed()
        }
    }
}

/// Terms of Use and Privacy Policy, side by side, or stacked when they do not fit (AX5).
private struct PaywallLegalLinks: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: TallySpacing.xl) { links }
            VStack(spacing: TallySpacing.md) { links }
        }
        .font(TallyTypography.footnote)
    }

    @ViewBuilder
    private var links: some View {
        if let terms = SubscriptionLinks.termsOfUse, terms.path.isEmpty {
            Link(destination: terms) {
                Text(L10n.Subscription.termsOfUse())
            }
            .accessibilityIdentifier("paywall.terms")
        }
        if let privacy = SubscriptionLinks.privacyPolicy {
            Link(destination: privacy) {
                Text(L10n.Subscription.privacyPolicy())
            }
            .accessibilityIdentifier("paywall.privacy")
        }
    }
}

/// The paywall's legal links on Tally's owned domain (`TallyOrgDomainInfo`, GO-LIVE GL-02).
enum SubscriptionLinks {
    static var termsOfUse: URL? { url(path: SubscriptionConfig.termsOfUsePath) }
    static var privacyPolicy: URL? { url(path: SubscriptionConfig.privacyPolicyPath) }

    private static func url(path: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = TallyOrgDomainInfo.current
        components.path = path
        return components.url
    }
}
