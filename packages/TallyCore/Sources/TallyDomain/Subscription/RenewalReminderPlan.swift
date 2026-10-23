import Foundation

/// EB-20 (compliance-us §3: "On-device renewal reminders"; NY 527-a(f) [U6]; Cal. B&P 17602(h)
/// [U4]). Pure: from StoreKit's own facts, says which of the two reminders (40 and 20 days before
/// the renewal date) are due, and what a later re-plan must cancel. Never a price (StoreKit's own
/// products format those, `L10n+Subscription.swift`'s own rule) and never a grade — this type
/// carries neither.
public enum RenewalReminderPlan {
    /// One reminder's identifier and fire date.
    public struct Reminder: Sendable, Equatable {
        public let id: String
        public let fireDate: Date
        public let daysBeforeRenewal: Int

        public init(id: String, fireDate: Date, daysBeforeRenewal: Int) {
            self.id = id
            self.fireDate = fireDate
            self.daysBeforeRenewal = daysBeforeRenewal
        }
    }

    /// What a reconcile pass does: schedule these, cancel those (`SubscriptionEngine`, off the
    /// main actor). A pure diff, apart from any platform or I/O, so it is tested without one.
    public struct Diff: Sendable, Equatable {
        public let toSchedule: [Reminder]
        public let toCancel: Set<String>
    }

    /// How many days before the renewal date each reminder fires (NY 527-a(f)'s 15-45 day window;
    /// Cal. B&P 17602(h)'s annual-reminder duty).
    public static let daysBefore = [40, 20]

    /// The reminders due for `role`'s subscription right now, from the counted facts StoreKit
    /// verified this launch (the same counting rule `EntitlementPolicy` uses: verified, this
    /// role's exact product, not upgraded). Empty whenever there is nothing to remind about: no
    /// counted fact is actively `.subscribed`, `willAutoRenew` is false, the renewal date has
    /// already passed, or `holding` is `.schoolSeat` — the school, not the student, manages that
    /// purchase (M3-B3's own rule for Manage Subscription and Request a Refund; the same holds
    /// here: a reminder to cancel would be meaningless to the student holding a seat they cannot
    /// cancel).
    public static func plan(_ facts: [SubscriptionFacts], role: SubscriptionRole, products: SubscriptionProducts,
                            holding: SubscriptionHolding, now: Date) -> [Reminder] {
        guard holding == .purchase, let renewalDate = renewalDate(facts, role: role, products: products) else { return [] }
        return daysBefore.compactMap { days in
            let fireDate = renewalDate.addingTimeInterval(-Double(days) * 24 * 60 * 60)
            guard fireDate > now else { return nil }
            return Reminder(id: identifier(role: role, daysBefore: days), fireDate: fireDate, daysBeforeRenewal: days)
        }
    }

    /// The identifiers `plan` could ever produce for `role` — what turning auto-renew off (or
    /// losing the entitlement) must cancel, whether or not they are currently pending.
    public static func allIdentifiers(role: SubscriptionRole) -> Set<String> {
        Set(daysBefore.map { identifier(role: role, daysBefore: $0) })
    }

    /// `desired` against what the platform actually has pending: everything this role manages
    /// that is pending but no longer desired is cancelled; everything desired that is not already
    /// pending is scheduled. (A desired reminder that IS already pending is left alone — re-adding
    /// an unchanged request is harmless but pointless, and this keeps the diff a true "what to do"
    /// list.) EB-20's "cancelled when auto-renew turns off": an empty `desired` cancels every
    /// identifier `allIdentifiers` lists that is still pending, which is exactly what happens once
    /// `plan` next returns nothing for this role.
    public static func diff(desired: [Reminder], pending: Set<String>, role: SubscriptionRole) -> Diff {
        let managed = allIdentifiers(role: role)
        let desiredIDs = Set(desired.map(\.id))
        let toCancel = managed.intersection(pending).subtracting(desiredIDs)
        let toSchedule = desired.filter { !pending.contains($0.id) }
        return Diff(toSchedule: toSchedule, toCancel: toCancel)
    }

    /// The namespace every renewal reminder's identifier lives in. These are planned from
    /// StoreKit's facts and reconciled only here (`SubscriptionEngine`), so
    /// `NotificationReconciler`, which plans from a Canvas snapshot and treats every other pending
    /// identifier as stale, leaves this namespace alone (`owns`).
    public static let identifierPrefix = "tally.subscription."

    /// Whether `id` is one of the renewal reminders' identifiers (`identifierPrefix`).
    public static func owns(_ id: String) -> Bool {
        id.hasPrefix(identifierPrefix)
    }

    private static func identifier(role: SubscriptionRole, daysBefore: Int) -> String {
        "\(identifierPrefix)\(role.rawValue).renewalReminder.\(daysBefore)"
    }

    /// The latest expiry among the counted, currently-`.subscribed`, auto-renewing facts for
    /// `role` — the one date StoreKit itself says this subscription will next renew.
    private static func renewalDate(_ facts: [SubscriptionFacts], role: SubscriptionRole,
                                    products: SubscriptionProducts) -> Date? {
        let productID = products.productID(for: role)
        let active = facts.filter { fact in
            fact.isVerified && fact.productID == productID && !fact.isUpgraded && fact.ownership == .purchased
                && fact.renewalState == .subscribed && fact.willAutoRenew
        }
        return active.compactMap(\.expirationDate).max()
    }
}
