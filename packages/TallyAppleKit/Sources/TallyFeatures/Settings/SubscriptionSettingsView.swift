import StoreKit
import SwiftUI
import TallyDesignSystem
import TallyDomain
import TallyStrings
import UIKit

/// PAY-08, PAY-09: Settings → Subscription, reachable at all times, sample mode included, so App Review
/// can see and buy the subscription (PRD §11.3). It states the plan and the Apple Account's state, and
/// offers See Plans (the paywall), Restore Purchases, Redeem Code, Manage Subscription and Request a
/// Refund, the last three through Apple's own sheets (`SubscriptionSheets`).
///
/// In sample mode, See Plans first says that Tally works only at schools where it is enabled:
/// "[Check My School] [Continue]" (`PaywallPlacement.needsInterstitial`). Check My School leaves the
/// sample data for Welcome; Continue shows the paywall. Sample mode never shows the paywall by itself.
///
/// FEAT-2: when `AppModel.notEnabledSchoolName` holds a name (the student already searched a
/// school and it came back not enabled), the interstitial instead names it and offers "Ask My
/// School" (reusing `SchoolNotEnabledView`'s own string) in place of "Check My School" — the
/// action still leaves the sample data, but now lands on that school's own page
/// (`AppModel.checkMySchool()`). With no stored name this is unchanged: the App-Review path.
struct SubscriptionSettingsView: View {
    let appModel: AppModel
    /// The Dashboard's school summary: the paywall's G-6 variant.
    let school: SchoolGradeSummary
    /// "Check My School"/"Ask My School": Settings closes and the sample data ends.
    let onCheckMySchool: () -> Void
    @State private var actions: SubscriptionActionsModel
    /// The paywall, or (EB-21) the retainable confirmation -- one piece of local state so the two
    /// can never both claim the one sheet below.
    @State private var sheet: SubscriptionSettingsSheet?
    @State private var showsInterstitial = false
    /// EB-20: the banner's "Open Settings" action.
    @Environment(\.openURL) private var openURL

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
                } else if !isSchoolSeat {
                    // EB-21: re-findable afterwards -- the same retainable confirmation the
                    // paywall showed once, right after the purchase.
                    Button(String(localized: L10n.Subscription.viewPurchaseConfirmation())) { sheet = .confirmation }
                        .accessibilityIdentifier("subscription.viewConfirmation")
                }
            } footer: {
                Text(isSchoolSeat ? L10n.Subscription.settingsFooterSchool() : L10n.Subscription.settingsFooter())
                    .tallySectionText()
            }
            // EB-20: shown only while a renewal reminder is due and notifications are not
            // authorized yet (never asked, or denied) — the same iOS permission Settings' own
            // Reminders section manages, so its "Turn On Reminders"/"Open Settings" actions
            // (`RemindersViewCopy`) cover this banner too; there is nothing subscription-specific
            // to ask the system for.
            if let permission = renewalReminderBannerPermission {
                Section {
                    Text(L10n.Subscription.renewalReminderBannerBody())
                        .font(TallyTypography.body)
                        .foregroundStyle(TallyColor.textPrimary)
                        .accessibilityIdentifier("subscription.renewalReminderBanner.text")
                    if permission == .notDetermined {
                        Button(String(localized: RemindersViewCopy.turnOn)) { appModel.reminders.requestPermission() }
                            .disabled(appModel.reminders.isRequesting)
                            .accessibilityIdentifier("subscription.renewalReminderBanner.turnOn")
                    } else {
                        Button(String(localized: RemindersViewCopy.openSettings)) {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                        }
                        .accessibilityIdentifier("subscription.renewalReminderBanner.openSettings")
                    }
                }
                .accessibilityIdentifier("subscription.renewalReminderBanner")
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
        .tallyFormScreenChrome()
        // D07: `TallyColor.textSecondary` for every `LabeledContent` value on this screen (Plan,
        // Status), in place of the system secondary grey.
        .labeledContentStyle(.tallySecondaryValue)
        .navigationTitle(Text(L10n.Subscription.settingsTitle()))
        .navigationBarTitleDisplayMode(.inline)
        .modifier(SubscriptionSheets(actions: actions))
        .alert(String(localized: L10n.Subscription.interstitialTitle()), isPresented: $showsInterstitial) {
            switch interstitialState {
            case .generic:
                // Unchanged: the App-Review path (SampleInterstitialStateTests.noStoredNameIsGeneric).
                Button(String(localized: L10n.Subscription.checkMySchool()), action: onCheckMySchool)
            case .named:
                // FEAT-2: reuses SchoolNotEnabledView's own "Ask My School" string verbatim; the
                // action (onCheckMySchool) now lands on that school's page, not a blank Welcome.
                Button(String(localized: L10n.Onboarding.SchoolSearch.askMySchool()), action: onCheckMySchool)
                    .accessibilityIdentifier("subscription.interstitial.askMySchool")
            }
            Button(String(localized: L10n.Subscription.continueToPlans())) {
                sheet = .paywall(PaywallRequest(trigger: .settings))
            }
            .accessibilityIdentifier(interstitialState.isNamed ? "subscription.interstitial.continue" : "")
            // UX2-17 (owner-approved 2026-10-24): after a mis-tap on See Plans, the only ways out
            // were Check My School or Continue -> paywall -> Not Now. The key already exists
            // (`SchoolRevokedNoticeView.swift` uses it for its own Cancel).
            Button(String(localized: L10n.Settings.cancel()), role: .cancel) {}
                .accessibilityIdentifier("subscription.interstitial.cancel")
        } message: {
            switch interstitialState {
            case .generic:
                Text(L10n.Subscription.interstitialMessage())
            case .named(let schoolName):
                Text(L10n.Subscription.interstitialMessageNamedSchool(school: schoolName))
            }
        }
        // The paywall (or, EB-21, the confirmation after it) from a view of its own, apart from
        // Apple's sheets above (two presentations on one view can close each other: run
        // 36976774341) -- `presentedSheet` below is the one binding for both, the same fix
        // `HomeShellView.presentedSheet` uses for its own three.
        .background {
            Color.clear
                .sheet(item: presentedSheet) { current in
                    // D30: a `.sheet` starts a fresh environment (HomeShellView's own sheet needs
                    // the same explicit `.tint` for the same reason), so the TabView's tint does
                    // not reach this sheet either.
                    switch current {
                    case .paywall(let request):
                        PaywallView(model: PaywallModel(trigger: request.trigger, school: school, subscription: appModel.subscription,
                                                        storefront: appModel.storefront))
                            .tint(TallyColor.accent)
                    case .confirmation:
                        PurchaseConfirmationView(subscription: appModel.subscription, storefront: appModel.storefront)
                            .tint(TallyColor.accent)
                    }
                }
        }
    }

    /// EB-21: the local sheet (the paywall), or, once a direct purchase or trial start just
    /// completed and nothing local is up, the retainable confirmation.
    private var presentedSheet: Binding<SubscriptionSettingsSheet?> {
        Binding(get: {
            if let sheet { return sheet }
            return appModel.subscription.justPurchased ? .confirmation : nil
        }, set: { newValue in
            guard newValue == nil else { return }
            if sheet != nil {
                sheet = nil
            } else {
                appModel.subscription.acknowledgeDirectPurchase()
            }
        })
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

    /// EB-20: `nil` unless a renewal reminder is actually due (`SubscriptionModel.hasUpcomingRenewalReminder`)
    /// and notifications are not authorized — never shown once allowed, and never shown for nothing
    /// (no subscription, auto-renew off, or a school seat, all of which make `hasUpcomingRenewalReminder`
    /// false).
    private var renewalReminderBannerPermission: ReminderPermission? {
        guard appModel.subscription.hasUpcomingRenewalReminder else { return nil }
        let permission = appModel.reminders.permission
        guard permission == .notDetermined || permission == .denied else { return nil }
        return permission
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
            sheet = .paywall(PaywallRequest(trigger: .settings))
        }
    }

    /// FEAT-2: which of the interstitial's two states this presentation is in, straight from the
    /// stored preference — never re-decided mid-presentation, so a write that lands while the
    /// alert is up (there is none today) could not flip it under the student.
    private var interstitialState: SampleInterstitialState {
        SampleInterstitialState(notEnabledSchoolName: appModel.notEnabledSchoolName)
    }
}

/// EB-21: `SubscriptionSettingsView`'s one sheet -- the paywall, or the retainable purchase
/// confirmation right after a direct purchase or trial start (same reasoning as `HomeSheet`,
/// `SubscriptionLockViews.swift`: one presenter so neither can close the other).
nonisolated enum SubscriptionSettingsSheet: Identifiable, Equatable, Sendable {
    case paywall(PaywallRequest)
    case confirmation

    var id: String {
        switch self {
        case .paywall(let request): request.id.uuidString
        case .confirmation: "confirmation"
        }
    }
}

/// FEAT-2: the sample-mode interstitial's two states, as a pure value so they are unit-testable
/// apart from the view (`SampleInterstitialStateTests`). `.generic` is today's copy, unchanged — the
/// App-Review path, when nothing was ever searched or the stored name was blank/whitespace-only.
/// `nonisolated` (the `WelcomeRoute`/`RootRoute` pattern): a plain value with no actor-isolated
/// state, so it opts out of `TallyFeatures`' module-wide `@MainActor` default and can be
/// constructed and compared from the test target's own nonisolated test functions.
nonisolated enum SampleInterstitialState: Equatable, Sendable {
    case generic
    case named(String)

    init(notEnabledSchoolName: String?) {
        guard let name = notEnabledSchoolName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            self = .generic
            return
        }
        self = .named(name)
    }

    var isNamed: Bool {
        switch self {
        case .generic: false
        case .named: true
        }
    }
}
