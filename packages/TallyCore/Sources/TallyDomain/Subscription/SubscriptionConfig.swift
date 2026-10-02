import Foundation

/// The subscription engine's tunables, each named once (architecture.md §3.1; the implementation
/// brief's "`TallyConfig` for every constant"). They live beside the engine rather than in
/// `TallyConfig`, so the work packages running beside M3-B1 never edit one file together.
public enum SubscriptionConfig {
    /// **The enforcement switch** (PAY-07; M3-B1 brief). While it is `false`, every gate answers
    /// "allowed": nothing is locked, no reminder is withdrawn, no background refresh is
    /// unscheduled, whatever StoreKit says. It stays `false` on `main` until M3-B2 ships the
    /// paywall: nobody can buy yet, so enforcing now would lock every simulator flow and every UI
    /// test. **M3-B2 flips this one value to `true`.** Tests turn enforcement on by injection
    /// (`SubscriptionGate(isEnforced:)`, `EntitlementGate(isEnforced:)`, `EntitlementAccess.covers`).
    public static let isGatingEnforced = false

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
}
