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
        // L10N-04 round 2 (gate-2 verdict L6): reserve the floating tab bar's own footprint at
        // the bottom, so "Ver planes" cannot land in its zone regardless of how tall the locked
        // body text runs (`TallySpacing.tabBarClearance`) — Spanish's longer
        // `subscription.locked.body` pushed the button under the tab bar at AX5 on the smallest
        // iPhone, and the tour's tap on it then never opened the paywall (L6 evidence).
        .safeAreaPadding(.bottom, TallySpacing.tabBarClearance)
        // ux-fp2 D04 follow-up: with the banner compact, the card scrolls at AX5 (it is reachable
        // now), and scrolled it passed under the toolbar's Settings button (Audit tour run
        // 37827539573); the screens' own D01 chrome hides it under an opaque bar instead.
        //
        // D25 (round 2): every lockable tab (`HomeShellView.swift`) sets its `.navigationTitle`
        // outside this card with the system's default `.large` display mode, same as its own
        // screen when unlocked — but this card used the plain, inline-title chrome, whose bar
        // background is `.visible` at rest. `ScreenChrome.swift`'s own R4 note documents exactly
        // this failure mode for a large title ("iOS 26 drew it over the tab roots' native large
        // titles … left an empty band"): `.visible` paints an opaque bar over the still-expanded
        // large title text, which is why the std captures showed a title-sized empty band with no
        // text, while the parent-mode AX5 legs (inline titles there) were unaffected. The
        // large-title variant's `.automatic` background — the same fix R4 already applied to
        // every unlocked tab root — stays clear until content scrolls under it, so the title
        // shows.
        .tallyLargeTitleScreenChrome()
    }
}

/// PAY-07 (PRD §11.2 "On lapse"): above the signed-in Home's tabs while refresh is locked (no trial
/// or subscription, a lapse included): "Subscribe to refresh — showing saved data from <time>", and
/// See Plans. The Dashboard stays readable under it. Nothing shows while refresh is allowed.
///
/// ux-fp2 D04 (S1): the banner does not scroll, and at AX5 it filled the whole smallest iPhone (its
/// words in a column beside See Plans, "4:33 P / M" under the tab bar), so the locked card under it
/// could not be reached. It is pinned chrome, so it is drawn at most at
/// `TallyReflow.pinnedChromeMaximumSize`, and from AX1 up See Plans goes under the words (the shared
/// row rule, `TallyReflowStack`), which then take the banner's full width: about a quarter of the
/// smallest iPhone's screen at AX5, with every word shown.
struct SubscriptionRefreshBanner: View {
    let appModel: AppModel
    let home: HomeModel

    var body: some View {
        if appModel.locks(.refresh) {
            SubscriptionRefreshBannerContent(savedDataText: savedDataText) {
                appModel.showPaywall(for: .lockedFeature)
            }
            .tallyPinnedChromeTextSize()
        }
    }

    private var savedDataText: String {
        guard let saved = home.freshness.showing else { return String(localized: L10n.Subscription.bannerNoDate()) }
        return String(localized: L10n.Subscription.bannerSavedFrom(Self.savedAtText(saved)))
    }

    /// UX1-34: without the year on a near date. `.formatted(date: .abbreviated, time: .shortened)`
    /// always includes the year ("from Oct 14, 2026 at 12:00 PM"), even hours out; every other
    /// near date in the app omits it (`DashboardText`'s "Busy stretch", UX1-13).
    private static func savedAtText(_ saved: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        let base = Date.FormatStyle(locale: TallyLocale.effective, calendar: calendar, timeZone: calendar.timeZone)
            .month(.abbreviated).day().hour().minute()
        return calendar.isDate(saved, equalTo: Date(), toGranularity: .year)
            ? saved.formatted(base)
            : saved.formatted(base.year())
    }
}

/// The banner's layout, under its Dynamic Type cap (so the size it reads is the capped one).
private struct SubscriptionRefreshBannerContent: View {
    let savedDataText: String
    let onSeePlans: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    /// UX1-34: hides this action while the selected tab is already showing `LockedFeatureCard`'s
    /// own "See Plans", about 200 pt below -- two identical actions on one screen. Set by
    /// `HomeShellView`, which is the only place that knows the selected tab.
    @Environment(\.isCurrentTabLocked) private var isCurrentTabLocked

    var body: some View {
        TallyReflowStack(spacing: TallySpacing.md) {
            HStack(alignment: typeSize.isAccessibilitySize ? .firstTextBaseline : .center, spacing: TallySpacing.md) {
                Image(systemName: "arrow.clockwise.circle")
                    .accessibilityHidden(true)
                Text(verbatim: savedDataText)
                    .font(TallyTypography.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("subscription.refreshBanner")
            }
            if !isCurrentTabLocked {
                TallyReflowSpacer(minLength: 0)
                Button(action: onSeePlans) {
                    // The HIG's 44 pt minimum on the label, so the hit area grows with it: on the Button
                    // itself the frame grew the layout box only, and once the banner was capped at AX2
                    // the target measured 33 pt at AX5 (Audit tour run 37827539573, `lockedTab-card`).
                    Text(L10n.Subscription.seePlans())
                        .font(TallyTypography.footnote.weight(.semibold))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("subscription.refreshBanner.seePlans")
            }
        }
        .foregroundStyle(TallyColor.textPrimary)
        .padding(.horizontal, TallySpacing.screenMargin)
        .padding(.vertical, TallySpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TallyColor.bgCard)
    }
}

/// PAY-06: asks `AppModel` for the first-sync paywall whenever what it waits for changes: its turn,
/// the Dashboard's full projection, the account's state and the lock. The Home shell presents it
/// (`AppModel.paywall`, in its one sheet).
struct FirstSyncPaywallTrigger: ViewModifier {
    let home: HomeModel
    @Environment(AppModel.self) private var appModel: AppModel?

    func body(content: Content) -> some View {
        content
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

/// The Home shell's one sheet (`HomeShellView.presentedSheet`): Settings, the paywall, or (EB-21)
/// the retainable purchase confirmation right after a direct purchase or trial start.
nonisolated enum HomeSheet: Identifiable, Equatable, Sendable {
    case settings
    case paywall(PaywallRequest)
    case purchaseConfirmation

    var id: String {
        switch self {
        case .settings: "settings"
        case .paywall(let request): request.id.uuidString
        case .purchaseConfirmation: "purchaseConfirmation"
        }
    }
}

nonisolated struct FirstSyncPaywallCue: Equatable, Sendable {
    var isDue: Bool
    var homeIsLoaded: Bool
    var accountState: EntitlementState?
    var isLocked: Bool
}
