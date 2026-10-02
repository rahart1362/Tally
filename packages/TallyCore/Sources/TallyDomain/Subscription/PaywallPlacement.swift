import Foundation

/// What asks for the paywall (PAY-06; PRD §11.3, pricing-licensing.md §5.3).
public enum PaywallTrigger: String, Sendable, Equatable, CaseIterable {
    /// The first successful sync has rendered the student's real Dashboard: Tally's one proactive
    /// offer, once per sign-in.
    case firstSyncFinished
    /// The student tapped a locked feature: a locked tab's card, or "Subscribe to refresh".
    case lockedFeature
    /// Settings → Subscription: reachable at all times, in sample mode too, so App Review can see and
    /// buy the subscription (PAY-09).
    case settings
}

/// Where the app is when a trigger fires: plain values the app reads from its own state.
public struct PaywallContext: Sendable, Equatable {
    /// Which root the app shows.
    public enum Session: String, Sendable, Equatable, CaseIterable {
        /// No account and no sample data: Welcome, school search, "not available at your school",
        /// the sign-in hand-off and the first sync (before, during and after a failure).
        case signedOut
        /// "Explore with Sample Data".
        case sample
        /// A signed-in account's Home, after its first successful sync.
        case signedIn
    }

    public var session: Session
    /// The app lock (or its privacy cover) is up.
    public var isLocked: Bool
    /// The account's Canvas sign-in expired and the student is being asked to sign in again
    /// (ADR 0001's reconnect).
    public var isReconnecting: Bool
    /// The account's entitlement as the gate decides with it; nil before the launch's first state
    /// (the Keychain record, then StoreKit), when nothing may be decided yet.
    public var accountState: EntitlementState?
    public var now: Date
    /// The gating table (`SubscriptionConfig.isGatingEnforced` unless a test injects otherwise).
    public var gate: SubscriptionGate

    public init(session: Session, isLocked: Bool, isReconnecting: Bool, accountState: EntitlementState?, now: Date,
                gate: SubscriptionGate = SubscriptionGate()) {
        self.session = session
        self.isLocked = isLocked
        self.isReconnecting = isReconnecting
        self.accountState = accountState
        self.now = now
        self.gate = gate
    }
}

/// PAY-06 (GL-01, PRD §11.3 and §11.4) as one pure rule: when Tally may put the paywall on screen.
///
/// - **Never before sign-in**, on "not available at your school", during the first sync or after it
///   failed: Tally offers a purchase only once the school's Canvas has connected and synced
///   (`session == .signedIn` exists only after a successful first sync). Never while the app lock
///   or its cover is up, and never during a Canvas reconnect.
/// - **By itself only once**, after the first successful sync rendered the Dashboard
///   (`firstSyncFinished`; the app consumes it), and only when there is something to buy: the
///   full app is locked in the account's state (a preview or a lapse). After that, only from a
///   locked feature the student tapped (`lockedFeature`), under the same conditions.
/// - **Sample mode never shows it by itself**: everything is open there (`.demo`). Settings →
///   Subscription shows it on request on the Home (sample data or an account), first behind the
///   sample-mode interstitial (`needsInterstitial`, PAY-09).
public enum PaywallPlacement {
    public static func shows(_ trigger: PaywallTrigger, in context: PaywallContext) -> Bool {
        guard !context.isLocked else { return false }
        switch trigger {
        case .settings:
            return context.session != .signedOut
        case .firstSyncFinished, .lockedFeature:
            guard context.session == .signedIn, !context.isReconnecting, let state = context.accountState else { return false }
            return !context.gate.allows(.fullApp, in: state, at: context.now)
        }
    }

    /// PAY-09: in sample mode, Settings → Subscription first says that Tally works only at schools
    /// where it is enabled ("[Check my school] [Continue]"), then shows the paywall.
    public static func needsInterstitial(_ trigger: PaywallTrigger, in context: PaywallContext) -> Bool {
        trigger == .settings && context.session == .sample
    }
}
