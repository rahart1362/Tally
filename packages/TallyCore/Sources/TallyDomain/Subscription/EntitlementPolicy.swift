import Foundation

/// One App Store transaction for a Tally product, as plain values (PAY-02): what the StoreKit
/// adapter reads from a `VerificationResult<Transaction>` and, when StoreKit can say, the
/// subscription's status. Never a receipt, a signed payload, a transaction ID or a price.
public struct SubscriptionFacts: Sendable, Equatable {
    /// Who holds the transaction (StoreKit's `ownershipType`).
    public enum Ownership: String, Sendable, Equatable, CaseIterable {
        /// Bought with this Apple Account.
        case purchased
        /// Shared through Family Sharing, which is off for every Tally plan (PRD §11.1).
        case familyShared
        /// Any other way StoreKit reports (an organization's seat, a type this build does not
        /// know): never entitles (fail closed; school-paid seats are backlog BL-15).
        case other
    }

    /// The subscription's renewal state (StoreKit's `Product.SubscriptionInfo.RenewalState`).
    public enum RenewalState: String, Sendable, Equatable, CaseIterable {
        case subscribed
        case expired
        case inBillingRetryPeriod
        case inGracePeriod
        case revoked
    }

    public var productID: String
    /// `VerificationResult.verified`: StoreKit checked the App Store's signature. **An
    /// unverified transaction never entitles** (PRD §11.5), and never lapses anyone either: it is
    /// ignored as if absent.
    public var isVerified: Bool
    public var expirationDate: Date?
    /// Set when the App Store refunded or revoked the transaction.
    public var revocationDate: Date?
    /// A higher-level subscription in the same group replaced this one.
    public var isUpgraded: Bool
    public var ownership: Ownership
    /// The subscription's renewal state, or `nil` when StoreKit could not say (offline, or the
    /// status could not be verified).
    public var renewalState: RenewalState?
    /// The end of a billing grace period, from verified renewal info (`inGracePeriod` only).
    public var gracePeriodExpirationDate: Date?
    /// When the App Store signed this transaction or its renewal info: a time the App Store had
    /// reached, so the device's clock cannot be earlier (PAY-02 clock skew).
    public var signedDate: Date?

    public init(productID: String, isVerified: Bool, expirationDate: Date?, revocationDate: Date? = nil,
                isUpgraded: Bool = false, ownership: Ownership = .purchased, renewalState: RenewalState? = nil,
                gracePeriodExpirationDate: Date? = nil, signedDate: Date? = nil) {
        self.productID = productID
        self.isVerified = isVerified
        self.expirationDate = expirationDate
        self.revocationDate = revocationDate
        self.isUpgraded = isUpgraded
        self.ownership = ownership
        self.renewalState = renewalState
        self.gracePeriodExpirationDate = gracePeriodExpirationDate
        self.signedDate = signedDate
    }
}

/// What a role may do now (PAY-02; PRD §11.2).
public enum EntitlementState: Sendable, Equatable {
    /// "Explore with Sample Data": every feature, on fictional data (always free).
    case demo
    /// Signed in with no trial or subscription: the free sign-in and one-time first-sync preview
    /// (PRD §11.2). A lapsed subscriber who signs in again gets the first sync too (pricing R9).
    case preview
    /// A verified trial or subscription, to `until` (the expiry, or the end of a billing grace
    /// period). Surfaces without StoreKit keep access `SubscriptionConfig.offlineGracePeriod`
    /// past it (`SubscriptionGate`, `EntitlementAccess`).
    case entitled(until: Date)
    /// The trial or subscription ended at `since` (expired, refunded or revoked): the last
    /// snapshot stays readable, nothing refreshes (PRD §11.2 "On lapse").
    case lapsed(since: Date)

    /// The expiry of an entitlement, else nil.
    public var entitledUntil: Date? {
        if case .entitled(let until) = self { return until }
        return nil
    }
}

/// PAY-02: who is entitled to what, from plain values, with no StoreKit, clock or I/O of its own.
///
/// **Rules** (pricing-licensing.md §6 PAY-02; PRD §11.5):
/// 1. Sample mode is `.demo`, whatever StoreKit holds.
/// 2. Only a transaction that is **verified**, for **this role's product** (exact ID), **not
///    upgraded** and **purchased** counts. Anything else is ignored, as if absent: unverified input
///    never entitles; a parent plan never unlocks the student role, or the reverse.
/// 3. A refund or revocation ends access at once: `.lapsed(since: revocationDate)`.
/// 4. A billing grace period entitles to its end (`gracePeriodExpirationDate`).
/// 5. A renewal state that settles the question (`expired`, `inBillingRetryPeriod`, `revoked`)
///    ends access at the expiry. When StoreKit says `subscribed` or `inGracePeriod`, or cannot
///    say, access lasts `offlineGrace` past the expiry, so a renewal that has not reached the
///    device yet does not lock a subscriber out; then it fails closed.
/// 6. Clock skew: time is the later of `now` and the newest App Store signed date among the
///    counted transactions, so a device clock set back cannot extend access.
/// 7. The latest end wins across several transactions. With none entitling: `.lapsed` once the
///    first sync has succeeded (the student has seen their data), else `.preview`.
public enum EntitlementPolicy {
    public static func evaluate(_ facts: [SubscriptionFacts], role: SubscriptionRole, products: SubscriptionProducts,
                                firstSyncSucceeded: Bool, isSampleMode: Bool, now: Date,
                                offlineGrace: Duration = SubscriptionConfig.offlineGracePeriod) -> EntitlementState {
        if isSampleMode { return .demo }
        let productID = products.productID(for: role)
        let counted = facts.filter { fact in
            fact.isVerified && fact.productID == productID && !fact.isUpgraded && fact.ownership == .purchased
        }
        let effectiveNow = counted.compactMap(\.signedDate).reduce(now) { max($0, $1) }
        var entitledUntil: Date?
        var lapsedSince: Date?
        for fact in counted {
            switch access(of: fact, at: effectiveNow, offlineGrace: offlineGrace) {
            case .entitled(let end): entitledUntil = max(entitledUntil ?? end, end)
            case .ended(let end): lapsedSince = max(lapsedSince ?? end, end)
            case .nothing: break
            }
        }
        if let entitledUntil { return .entitled(until: entitledUntil) }
        if let lapsedSince, firstSyncSucceeded { return .lapsed(since: lapsedSince) }
        return .preview
    }

    private enum Access {
        case entitled(Date)
        case ended(Date)
        case nothing
    }

    private static func access(of fact: SubscriptionFacts, at now: Date, offlineGrace: Duration) -> Access {
        if let revoked = fact.revocationDate { return .ended(revoked) }
        // An auto-renewable subscription always has an expiry; a transaction without one grants
        // nothing here (fail closed).
        guard let expiration = fact.expirationDate else { return .nothing }
        if fact.renewalState == .revoked { return .ended(min(expiration, now)) }
        var end = expiration
        if fact.renewalState == .inGracePeriod, let graceEnd = fact.gracePeriodExpirationDate {
            end = max(end, graceEnd)
        }
        let settled = fact.renewalState == .expired || fact.renewalState == .inBillingRetryPeriod
        let lastsUntil = settled ? end : end.addingTimeInterval(offlineGrace.timeInterval)
        return now < lastsUntil ? .entitled(end) : .ended(end)
    }
}
