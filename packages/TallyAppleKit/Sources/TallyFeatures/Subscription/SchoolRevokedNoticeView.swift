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
///
/// EB-26 adds "Erase Saved Data" (confirmed, `AppModel.eraseSavedData()`) and a footnote about the
/// automatic expiry (`SubscriptionConfig.schoolRevokedRetentionDays`); everything above is unchanged.
struct SchoolRevokedNoticeView: View {
    let appModel: AppModel
    @State private var actions: SubscriptionActionsModel
    @State private var confirmsErase = false
    /// UX2-06: `ScreenPalette.color(_:scheme:contrast:)` needs both explicitly -- it resolves the
    /// Any/Dark/High-Contrast swatch itself rather than through an asset-catalog `Color` that
    /// would read the environment on its own.
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    init(appModel: AppModel) {
        self.appModel = appModel
        _actions = State(initialValue: SubscriptionActionsModel(subscription: appModel.subscription,
                                                                 storefront: appModel.storefront))
    }

    var body: some View {
        // UX2-04/UX2-09: the icon/title/centring this screen built by hand (a bare `ScrollView`
        // with no toolbar, so scrolled text ran under the status bar at AX5 -- the D01 class of
        // defect) are now the shared `TallyNoticeLayout`, which also carries UX2-04's opaque
        // status-bar band and the `screenMargin` sides this screen's own `TallySpacing.xl` padding
        // used instead.
        TallyNoticeLayout(systemImage: "building.columns",
                          title: Text(L10n.Subscription.schoolOffTitle()),
                          titleIdentifier: "schoolOff.title") {
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
        } actions: {
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
                // UX2-06: "Continue with Saved Data" measured 3.20:1 (system blue on this
                // screen's canvas) and 20.3 pt tall -- a plain text button with no tint and no
                // explicit frame. `accent` (7.24:1) and a real 44 pt target, the same fix as
                // Erase below.
                Button(String(localized: L10n.Subscription.schoolOffContinue())) {
                    appModel.dismissSchoolRevokedNotice()
                }
                .foregroundStyle(TallyColor.accent)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityIdentifier("schoolOff.continue")
                // EB-26: reuses Sign Out & Erase's purge path without signing out (M3-B3: a
                // school seat has no cancel/refund sentence above, but it is still this
                // student's own saved copy to erase).
                //
                // UX2-06: "Erase Saved Data" measured 3.24:1 (system red) and 20.3 pt tall --
                // `ScreenPalette.danger` (5.22:1 light, 8.78:1 dark; `Courses/ScreenComponents.
                // swift`) and the same 44 pt target as Continue. The full-screen cover starts a
                // fresh environment (D30), so a plain `role: .destructive` button here draws the
                // system's own red rather than the app's.
                Button(String(localized: L10n.Subscription.eraseSavedData())) {
                    confirmsErase = true
                }
                .foregroundStyle(ScreenPalette.color(ScreenPalette.danger, scheme: colorScheme, contrast: contrast))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityIdentifier("schoolOff.eraseSavedData")
            }
            // EB-26: the owner-chosen automatic expiry, so the notice says what happens if the
            // student never comes back to tap Erase Saved Data themselves.
            Text(L10n.Subscription.schoolOffAutoEraseNotice(
                String(localized: L10n.Subscription.days(SubscriptionConfig.schoolRevokedRetentionDays))))
                .font(TallyTypography.footnote)
                .foregroundStyle(TallyColor.textSecondary)
                .accessibilityIdentifier("schoolOff.autoEraseNotice")
        }
        .modifier(SubscriptionSheets(actions: actions))
        .tallyDestructiveConfirmation(
            String(localized: L10n.Subscription.eraseSavedDataConfirmTitle()), isPresented: $confirmsErase,
            message: String(localized: L10n.Subscription.eraseSavedDataConfirmMessage()),
            actions: [
                TallyConfirmationAction(String(localized: L10n.Subscription.eraseSavedData()), role: .destructive,
                                        accessibilityIdentifier: "schoolOff.eraseSavedDataConfirm.erase") {
                    appModel.eraseSavedData()
                },
                TallyConfirmationAction(String(localized: L10n.Settings.cancel()), role: .cancel,
                                        accessibilityIdentifier: "schoolOff.eraseSavedDataConfirm.cancel") {},
            ],
            accessibilityIdentifier: "schoolOff.eraseSavedDataConfirm")
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
