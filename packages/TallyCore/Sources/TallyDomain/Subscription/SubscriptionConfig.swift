import Foundation

/// The subscription engine's tunables, each named once (architecture.md §3.1; the implementation
/// brief's "`TallyConfig` for every constant"). They live beside the engine rather than in
/// `TallyConfig`, so the work packages running beside M3-B1 never edit one file together.
public enum SubscriptionConfig {
    /// **The enforcement switch** (PAY-07). On since M3-B2 shipped the paywall (PAY-05), Settings →
    /// Subscription (PAY-08) and the locked-feature cards (PAY-06): the gates refuse what PRD §11.2
    /// puts behind the trial or subscription (refresh after the free first sync, the full app,
    /// reminders, background refresh, the widgets' and intents' data). Were it `false`, every gate
    /// would answer "allowed" whatever StoreKit says. Tests choose either by injection
    /// (`SubscriptionGate(isEnforced:)`, `EntitlementGate(isEnforced:)`, `EntitlementAccess.covers`);
    /// UI tests that run signed-in flows get a test-only entitlement (`SubscriptionTestHooks`, DEBUG
    /// and `TALLY_TEST_HOOKS` builds only).
    public static let isGatingEnforced = true

    /// PAY-04: how long after the last verified expiry a surface that cannot ask StoreKit keeps
    /// access (the widgets and intents through the glance, background refresh, a launch before
    /// StoreKit answers), so a renewal the device has not seen yet never locks a subscriber out.
    /// Then access fails closed. The same allowance applies when StoreKit cannot say whether the
    /// subscription renewed (its renewal state is unknown, e.g. offline). PRD §11.5: "a short
    /// named grace period"; pricing-licensing.md PAY-04: 3 days.
    public static let offlineGracePeriod: Duration = .seconds(3 * 24 * 60 * 60)

    /// PAY-01: Tally Annual's product ID is `<bundle-id>` followed by this (group "Tally").
    public static let studentAnnualSuffix = ".annual"
    /// PAY-01, PRD §11.9: Tally Parent's product ID is `<bundle-id>` followed by this (group
    /// "Tally Parent", its own subscription group).
    public static let parentAnnualSuffix = ".parent.annual"

    /// PAY-07: how long a gate decision may wait, at launch, for the first entitlement state (the
    /// Keychain record, read off the main actor at app init) before it fails closed. The read takes
    /// milliseconds; this only bounds a launch where it never arrives.
    public static let launchResolutionTimeout: Duration = .seconds(5)

    /// PAY-07 (perf-app-runtime.md §2.4 B6): a background refresh is requested no sooner than this
    /// after the request (`TallyConfig.bgEarliestBegin`, re-exported so the engine names one value).
    public static let backgroundRefreshEarliestBegin: Duration = TallyConfig.bgEarliestBegin

    /// PAY-05 (GO-LIVE GTM-07): the paywall's Terms of Use and Privacy Policy, as paths on Tally's
    /// owned domain (`Identity.xcconfig`'s `TALLY_ORG_DOMAIN`). The site serves `/privacy`; the
    /// Terms of Use page is the owner's to publish there (Apple's standard EULA or Tally's own).
    public static let termsOfUsePath = "/terms"
    public static let privacyPolicyPath = "/privacy"
}
