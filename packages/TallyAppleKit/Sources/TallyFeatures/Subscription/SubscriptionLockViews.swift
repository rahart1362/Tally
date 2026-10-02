import SwiftUI
import TallyDesignSystem
import TallyDomain
import TallyStrings

/// PAY-06 (d), PAY-07: a tab that needs the trial or subscription (Courses, Calendar, To-Do,
/// Insights; PRD §11.2) shows `LockedFeatureCard` in place of its screen while `AppModel` says the
/// full app is locked. The screen is not built at all then. Nothing is locked in sample mode, before
/// sign-in, or before the launch's first entitlement state (`AppModel.locks`).
struct SubscriptionLock: ViewModifier {
    @Environment(AppModel.self) private var appModel: AppModel?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let appModel, appModel.locks(.fullApp) {
            LockedFeatureCard(onSeePlans: { appModel.showPaywall(for: .lockedFeature) })
        } else {
            content
        }
    }
}

/// PAY-06 (d): the inline card of a locked tab. It names no grade feature, so it suits every school
/// (plan 08 G-6). "See Plans" asks for the paywall as a locked feature.
struct LockedFeatureCard: View {
    let onSeePlans: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: TallySpacing.lg) {
                Image(systemName: "lock.fill")
                    .font(TallyTypography.screenTitle)
                    .foregroundStyle(TallyColor.accent)
                    .accessibilityHidden(true)
                Text(L10n.Subscription.lockedTitle())
                    .font(TallyTypography.sectionHeader)
                    .foregroundStyle(TallyColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("subscription.locked.title")
                Text(L10n.Subscription.lockedBody())
                    .font(TallyTypography.body)
                    .foregroundStyle(TallyColor.textSecondary)
                Button(String(localized: L10n.Subscription.seePlans()), action: onSeePlans)
                    .buttonStyle(.tallyPrimary)
                    .accessibilityIdentifier("subscription.locked.seePlans")
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(TallySpacing.xl)
            .frame(maxWidth: .infinity)
            .background(TallyColor.bgCard, in: RoundedRectangle(cornerRadius: TallyRadius.card, style: .continuous))
            .padding(TallySpacing.screenMargin)
        }
        .background(TallyColor.bgCanvas)
    }
}

/// PAY-07 (PRD §11.2 "On lapse"): above the signed-in Home's tabs while refresh is locked (no trial
/// or subscription, a lapse included): "Subscribe to refresh — showing saved data from <time>", and
/// See Plans. The Dashboard stays readable under it. Nothing shows while refresh is allowed.
struct SubscriptionRefreshBanner: View {
    let appModel: AppModel
    let home: HomeModel

    var body: some View {
        if appModel.locks(.refresh) {
            HStack(spacing: TallySpacing.md) {
                Image(systemName: "arrow.clockwise.circle")
                    .accessibilityHidden(true)
                Text(verbatim: savedDataText)
                    .font(TallyTypography.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("subscription.refreshBanner")
                Spacer(minLength: 0)
                Button(String(localized: L10n.Subscription.seePlans())) {
                    appModel.showPaywall(for: .lockedFeature)
                }
                .font(TallyTypography.footnote.weight(.semibold))
                .frame(minHeight: 44) // the HIG's minimum target
                .accessibilityIdentifier("subscription.refreshBanner.seePlans")
            }
            .foregroundStyle(TallyColor.textPrimary)
            .padding(.horizontal, TallySpacing.screenMargin)
            .padding(.vertical, TallySpacing.xs)
            .frame(maxWidth: .infinity)
            .background(TallyColor.bgCard)
        }
    }

    private var savedDataText: String {
        guard let saved = home.freshness.showing else { return String(localized: L10n.Subscription.bannerNoDate()) }
        return String(localized: L10n.Subscription.bannerSavedFrom(saved.formatted(date: .abbreviated, time: .shortened)))
    }
}

/// PAY-06: the Home's paywall sheet (`AppModel.paywall`): once after this sign-in's first sync has
/// rendered the Dashboard, and for a locked feature. The paywall's G-6 variant follows the Dashboard's
/// school summary.
struct HomePaywallPresenter: ViewModifier {
    let home: HomeModel
    @Environment(AppModel.self) private var appModel: AppModel?

    func body(content: Content) -> some View {
        content
            .sheet(item: Binding(get: { appModel?.paywall }, set: { request in
                if request == nil { appModel?.dismissPaywall() }
            })) { request in
                if let appModel {
                    PaywallView(model: PaywallModel(trigger: request.trigger, school: home.dashboard.hero.school,
                                                    subscription: appModel.subscription, storefront: appModel.storefront))
                }
            }
            .onChange(of: cue, initial: true) { _, cue in
                appModel?.showFirstSyncPaywallIfDue(homeIsLoaded: cue.homeIsLoaded)
            }
    }

    /// What the first-sync paywall waits for: its turn, the Dashboard's full projection, the
    /// account's state and the lock.
    private var cue: FirstSyncPaywallCue {
        FirstSyncPaywallCue(isDue: appModel?.isFirstSyncPaywallDue ?? false, homeIsLoaded: home.phase == .loaded,
                            accountState: appModel?.subscription.accountState,
                            isLocked: (appModel?.lock.isLocked ?? false) || (appModel?.lock.showsPrivacyCover ?? false))
    }
}

nonisolated struct FirstSyncPaywallCue: Equatable, Sendable {
    var isDue: Bool
    var homeIsLoaded: Bool
    var accountState: EntitlementState?
    var isLocked: Bool
}
