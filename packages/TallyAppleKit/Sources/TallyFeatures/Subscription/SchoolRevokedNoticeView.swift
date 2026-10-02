import StoreKit
import SwiftUI
import TallyDesignSystem
import TallyDomain
import TallyStrings

/// PAY-10 (PRD §11.4, pricing-licensing.md §5.4): the school turned off Tally's access to Canvas
/// while the student has a trial or subscription. A full-screen notice: what happened, that the
/// saved data stays readable, and Apple's two ways out, Manage Subscription and Request a Refund
/// (Tally cannot refund; Apple decides). "Continue with Saved Data" closes it. `RootView` presents
/// it over the signed-in Home (never over the app lock) while `AppModel.showsSchoolRevokedNotice`.
struct SchoolRevokedNoticeView: View {
    let appModel: AppModel
    @State private var actions: SubscriptionActionsModel

    init(appModel: AppModel) {
        self.appModel = appModel
        _actions = State(initialValue: SubscriptionActionsModel(subscription: appModel.subscription,
                                                                 storefront: appModel.storefront))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: TallySpacing.xl) {
                Image(systemName: "building.columns")
                    .font(TallyTypography.screenTitle)
                    .foregroundStyle(TallyColor.accent)
                    .accessibilityHidden(true)
                Text(L10n.Subscription.schoolOffTitle())
                    .font(TallyTypography.sectionHeader)
                    .foregroundStyle(TallyColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("schoolOff.title")
                // M3-B3: a school-assigned seat has no cancel/refund sentence or buttons — the
                // school, not the student, holds that purchase.
                Text(isSchoolSeat ? L10n.Subscription.schoolOffBodySeat() : L10n.Subscription.schoolOffBody())
                    .font(TallyTypography.body)
                    .foregroundStyle(TallyColor.textSecondary)
                if let notice = actions.notice {
                    Text(SubscriptionActionsText.text(notice))
                        .font(TallyTypography.footnote)
                        .foregroundStyle(TallyColor.textSecondary)
                        .accessibilityIdentifier("schoolOff.notice")
                }
                VStack(spacing: TallySpacing.md) {
                    if !isSchoolSeat {
                        Button(String(localized: L10n.Subscription.manage())) { actions.manage() }
                            .buttonStyle(.tallyPrimary)
                            .accessibilityIdentifier("schoolOff.manage")
                        Button(String(localized: L10n.Subscription.requestRefund())) {
                            Task { await actions.requestRefund() }
                        }
                        .buttonStyle(.tallySecondary)
                        .disabled(actions.isWorking)
                        .accessibilityIdentifier("schoolOff.refund")
                    }
                    Button(String(localized: L10n.Subscription.schoolOffContinue())) {
                        appModel.dismissSchoolRevokedNotice()
                    }
                    .accessibilityIdentifier("schoolOff.continue")
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(TallySpacing.xl)
            .frame(maxWidth: .infinity)
        }
        .background(TallyColor.bgCanvas)
        .modifier(SubscriptionSheets(actions: actions))
    }

    /// M3-B3: `false` (today's purchase UI) before StoreKit has answered this launch.
    private var isSchoolSeat: Bool {
        appModel.subscription.isSchoolSeat
    }
}

/// PAY-10: presents the notice full screen while `AppModel.showsSchoolRevokedNotice`; closing it is
/// "Continue with Saved Data". A clear view of its own behind the Home (`RootView`), so this
/// presentation and the Home's sheet never share a presenter.
struct SchoolRevokedNoticePresenter: View {
    let appModel: AppModel

    var body: some View {
        Color.clear
            .fullScreenCover(isPresented: Binding(get: { appModel.showsSchoolRevokedNotice }, set: { isPresented in
                if !isPresented { appModel.dismissSchoolRevokedNotice() }
            })) {
                SchoolRevokedNoticeView(appModel: appModel)
            }
    }
}

/// Apple's own sheets, bound to `SubscriptionActionsModel` (PAY-08, PAY-10): Manage Subscription,
/// Redeem Code and Request a Refund. When one closes, the engine re-verifies (a cancellation, a refund
/// or a redeemed code shows at once). The completions are `@Sendable` (no actor), so they are safe
/// whichever thread StoreKit calls them on.
struct SubscriptionSheets: ViewModifier {
    @Bindable var actions: SubscriptionActionsModel

    func body(content: Content) -> some View {
        content
            .manageSubscriptionsSheet(isPresented: $actions.presentsManage)
            .offerCodeRedemption(isPresented: $actions.presentsRedeem, onCompletion: { @Sendable _ in })
            .refundRequestSheet(for: actions.refundTransactionID ?? 0, isPresented: $actions.presentsRefund,
                                onDismiss: { @Sendable _ in })
            .onChange(of: actions.isPresentingSheet) { _, isPresenting in
                if !isPresenting { Task { await actions.sheetClosed() } }
            }
    }
}

/// What an action said, in words.
nonisolated enum SubscriptionActionsText {
    static func text(_ notice: SubscriptionActionsModel.Notice) -> LocalizedStringResource {
        switch notice {
        case .noRefund: L10n.Subscription.noRefund()
        case .nothingToRestore: L10n.Subscription.nothingToRestore()
        case .restoreFailed: L10n.Subscription.restoreFailed()
        }
    }
}
