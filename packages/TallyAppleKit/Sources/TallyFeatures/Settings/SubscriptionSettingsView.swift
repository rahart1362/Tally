import StoreKit
import SwiftUI
import TallyDesignSystem
import TallyDomain
import TallyStrings

/// PAY-08, PAY-09: Settings → Subscription, reachable at all times, sample mode included, so App Review
/// can see and buy the subscription (PRD §11.3). It states the plan and the Apple Account's state, and
/// offers See Plans (the paywall), Restore Purchases, Redeem Code, Manage Subscription and Request a
/// Refund, the last three through Apple's own sheets (`SubscriptionSheets`).
///
/// In sample mode, See Plans first says that Tally works only at schools where it is enabled:
/// "[Check My School] [Continue]" (`PaywallPlacement.needsInterstitial`). Check My School leaves the
/// sample data for Welcome; Continue shows the paywall. Sample mode never shows the paywall by itself.
struct SubscriptionSettingsView: View {
    let appModel: AppModel
    /// The Dashboard's school summary: the paywall's G-6 variant.
    let school: SchoolGradeSummary
    /// "Check My School": Settings closes and the sample data ends.
    let onCheckMySchool: () -> Void
    @State private var actions: SubscriptionActionsModel
    @State private var paywall: PaywallRequest?
    @State private var showsInterstitial = false

    init(appModel: AppModel, school: SchoolGradeSummary, onCheckMySchool: @escaping () -> Void) {
        self.appModel = appModel
        self.school = school
        self.onCheckMySchool = onCheckMySchool
        _actions = State(initialValue: SubscriptionActionsModel(subscription: appModel.subscription,
                                                                 storefront: appModel.storefront))
    }

    var body: some View {
        Form {
            Section {
                LabeledContent(String(localized: L10n.Subscription.planLabel()), value: String(localized: L10n.Subscription.name()))
                LabeledContent(String(localized: L10n.Subscription.statusLabel()), value: statusText)
                    .accessibilityIdentifier("subscription.status")
                if !isActive {
                    Button(String(localized: L10n.Subscription.seePlans())) { seePlans() }
                        .accessibilityIdentifier("subscription.seePlans")
                }
            } footer: {
                Text(isSchoolSeat ? L10n.Subscription.settingsFooterSchool() : L10n.Subscription.settingsFooter())
            }
            Section {
                Button(String(localized: L10n.Subscription.restorePurchases())) {
                    Task { await actions.restore() }
                }
                .disabled(actions.isWorking)
                .accessibilityIdentifier("subscription.restore")
                Button(String(localized: L10n.Subscription.redeemCode())) { actions.redeem() }
                    .accessibilityIdentifier("subscription.redeem")
                // M3-B3: a school-assigned seat is the school's purchase, not the student's: Manage
                // Subscription and Request a Refund would open Apple's sheets for a purchase this
                // Apple Account does not hold.
                if !isSchoolSeat {
                    Button(String(localized: L10n.Subscription.manage())) { actions.manage() }
                        .accessibilityIdentifier("subscription.manage")
                    if hasPurchase {
                        Button(String(localized: L10n.Subscription.requestRefund())) {
                            Task { await actions.requestRefund() }
                        }
                        .disabled(actions.isWorking)
                        .accessibilityIdentifier("subscription.refund")
                    }
                }
                if let notice = actions.notice {
                    Text(SubscriptionActionsText.text(notice))
                        .font(TallyTypography.footnote)
                        .foregroundStyle(TallyColor.textSecondary)
                        .accessibilityIdentifier("subscription.notice")
                }
            }
        }
        // D01: content scrolled past the top stayed visible, blurred, under the inline title and
        // the status bar, even at rest.
        .tallyScreenChrome()
        .navigationTitle(Text(L10n.Subscription.settingsTitle()))
        .navigationBarTitleDisplayMode(.inline)
        .modifier(SubscriptionSheets(actions: actions))
        .alert(String(localized: L10n.Subscription.interstitialTitle()), isPresented: $showsInterstitial) {
            Button(String(localized: L10n.Subscription.checkMySchool()), action: onCheckMySchool)
            Button(String(localized: L10n.Subscription.continueToPlans())) {
                paywall = PaywallRequest(trigger: .settings)
            }
        } message: {
            Text(L10n.Subscription.interstitialMessage())
        }
        // The paywall from a view of its own, apart from Apple's sheets above (two presentations on one
        // view can close each other: run 36976774341).
        .background {
            Color.clear
                .sheet(item: $paywall) { request in
                    PaywallView(model: PaywallModel(trigger: request.trigger, school: school, subscription: appModel.subscription,
                                                    storefront: appModel.storefront))
                }
        }
    }

    private var statusText: String {
        SubscriptionStatusText.status(appModel.subscription.accountState, holding: appModel.subscription.holding,
                                      isPurchasePending: appModel.subscription.isPurchasePending)
    }

    private var isActive: Bool {
        appModel.subscription.accountState?.isActiveEntitlement == true
    }

    /// M3-B3: `false` (today's purchase UI) before StoreKit has answered this launch.
    private var isSchoolSeat: Bool {
        appModel.subscription.isSchoolSeat
    }

    /// A trial or subscription this Apple Account bought, current or ended: what a refund is about.
    private var hasPurchase: Bool {
        switch appModel.subscription.accountState {
        case .entitled?, .lapsed?: true
        case .demo?, .preview?, nil: false
        }
    }

    /// PAY-09: in sample mode the interstitial first; otherwise the paywall.
    private func seePlans() {
        let context = appModel.paywallContext()
        if PaywallPlacement.needsInterstitial(.settings, in: context) {
            showsInterstitial = true
        } else if PaywallPlacement.shows(.settings, in: context) {
            paywall = PaywallRequest(trigger: .settings)
        }
    }
}
