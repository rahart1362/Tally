import Foundation

/// PAY-04: the last verified entitlement, kept in the Keychain (`AfterFirstUnlockThisDeviceOnly`,
/// `KeychainEntitlementStore`) so a launch can act before StoreKit answers and background work can
/// act without it. The glance mirrors the active role's expiry (`GlanceProjection.entitledUntil`)
/// for the widgets and intents. **An expiry per role and the device time it was verified: never a
/// receipt, a signed payload, a transaction ID or a price** (encryption.md §3.3).
public struct EntitlementRecord: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    /// The last verified `.entitled(until:)` of the student role; nil when the last verification
    /// found no entitlement (never subscribed, lapsed, refunded).
    public var studentUntil: Date?
    /// The same for the parent role (PRD §11.9).
    public var parentUntil: Date?
    /// The device time of that verification: a time this device has reached, so a clock set back
    /// afterwards cannot extend access.
    public var verifiedAt: Date

    public init(studentUntil: Date? = nil, parentUntil: Date? = nil, verifiedAt: Date) {
        schemaVersion = Self.currentSchemaVersion
        self.studentUntil = studentUntil
        self.parentUntil = parentUntil
        self.verifiedAt = verifiedAt
    }

    public func until(for role: SubscriptionRole) -> Date? {
        switch role {
        case .student: studentUntil
        case .parent: parentUntil
        }
    }

    /// This record after a verification found `state` for `role` at `verifiedAt`: the role's
    /// expiry is the entitlement's, or none. The other role's expiry is kept. `verifiedAt` is taken
    /// as measured, never as a high-water mark: a clock once set far ahead must not lock the
    /// offline paths out after it is corrected; the next verification heals it.
    public func recording(_ state: EntitlementState, for role: SubscriptionRole, verifiedAt: Date) -> EntitlementRecord {
        var next = self
        switch role {
        case .student: next.studentUntil = state.entitledUntil
        case .parent: next.parentUntil = state.entitledUntil
        }
        next.verifiedAt = verifiedAt
        return next
    }

    /// What a launch acts on before StoreKit answers, and background work without it: the role's
    /// expiry while it still covers `now` (`EntitlementAccess.covers`, enforced), else `.lapsed`
    /// from it; with no expiry, `.preview`. Fails closed after the grace period.
    public func state(for role: SubscriptionRole, now: Date,
                      offlineGrace: Duration = SubscriptionConfig.offlineGracePeriod) -> EntitlementState {
        guard let until = until(for: role) else { return .preview }
        let covers = EntitlementAccess.covers(entitledUntil: until, at: now, notBefore: verifiedAt, isEnforced: true,
                                              offlineGrace: offlineGrace)
        return covers ? .entitled(until: until) : .lapsed(since: until)
    }
}

/// PAY-04, PAY-07: the one access rule for surfaces with no StoreKit (the widgets and the intents,
/// through the glance's `entitledUntil`; background work, through `EntitlementRecord`). M3-D wires
/// the widgets' locked state and the intents to `covers`.
public enum EntitlementAccess {
    /// Whether a mirrored expiry still covers `moment`. **Fails closed:** no expiry, no access;
    /// access ends `offlineGrace` after the expiry. `notBefore` is a time this device has already
    /// reached (the glance's `asOf`, the record's `verifiedAt`): the later of it and `moment` counts,
    /// so a clock set back cannot extend access. Always true while gating is not enforced
    /// (`SubscriptionConfig.isGatingEnforced`).
    public static func covers(entitledUntil: Date?, at moment: Date, notBefore: Date? = nil,
                              isEnforced: Bool = SubscriptionConfig.isGatingEnforced,
                              offlineGrace: Duration = SubscriptionConfig.offlineGracePeriod) -> Bool {
        guard isEnforced else { return true }
        guard let ends = accessEnds(entitledUntil: entitledUntil, offlineGrace: offlineGrace) else { return false }
        let effective = notBefore.map { max($0, moment) } ?? moment
        return effective < ends
    }

    /// When `covers` turns false for an expiry (for a widget timeline's boundary), or nil without one.
    public static func accessEnds(entitledUntil: Date?,
                                  offlineGrace: Duration = SubscriptionConfig.offlineGracePeriod) -> Date? {
        entitledUntil?.addingTimeInterval(offlineGrace.timeInterval)
    }
}
