import Foundation
import Testing
@testable import TallyDomain

/// EB-20 (compliance-us §3; NY 527-a(f) [U6]; Cal. B&P 17602(h) [U4]): the two renewal reminders,
/// 40 and 20 days before the renewal date, and their cancellation. Covers the brief's three asks:
/// the scheduling dates (`plan`), the auto-renew-off cancellation (`diff`), and (together with
/// `SchoolRevokedRetentionTests`) the expiry rule for the sibling feature in this package.
@Suite("RenewalReminderPlan (EB-20): scheduling dates and cancellation")
struct RenewalReminderPlanTests {
    static let products = SubscriptionProducts(bundleID: "dev.tally-app.tally")
    static let student = products.studentAnnual
    /// 2026-09-21T14:13:20Z.
    static let now = Date(timeIntervalSince1970: 1_790_000_000)
    static let day: TimeInterval = 24 * 60 * 60

    static func at(_ offset: TimeInterval) -> Date { now.addingTimeInterval(offset) }

    static func fact(_ productID: String = student, verified: Bool = true, expires: TimeInterval = 60 * day,
                     ownership: SubscriptionFacts.Ownership = .purchased,
                     renewal: SubscriptionFacts.RenewalState? = .subscribed, willAutoRenew: Bool = true) -> SubscriptionFacts {
        SubscriptionFacts(productID: productID, isVerified: verified, expirationDate: at(expires),
                          ownership: ownership, renewalState: renewal, willAutoRenew: willAutoRenew)
    }

    // MARK: - plan: the scheduling dates

    @Test func fortyAndTwentyDaysBeforeTheRenewalDate() {
        let renewalDate = Self.at(60 * Self.day)
        let reminders = RenewalReminderPlan.plan([Self.fact(expires: 60 * Self.day)], role: .student, products: Self.products,
                                                  holding: .purchase, now: Self.now)
        #expect(reminders.map(\.daysBeforeRenewal) == [40, 20])
        #expect(reminders.map(\.fireDate) == [renewalDate.addingTimeInterval(-40 * Self.day), renewalDate.addingTimeInterval(-20 * Self.day)])
        #expect(Set(reminders.map(\.id)).count == 2, "the two reminders must have distinct, stable ids")
    }

    @Test func aReminderWhoseDateHasAlreadyPassedIsDropped() {
        // The renewal is 25 days out: the 40-day reminder's date is in the past, the 20-day one is not.
        let reminders = RenewalReminderPlan.plan([Self.fact(expires: 25 * Self.day)], role: .student, products: Self.products,
                                                  holding: .purchase, now: Self.now)
        #expect(reminders.map(\.daysBeforeRenewal) == [20])
    }

    @Test func noFactAtAllPlansNothing() {
        #expect(RenewalReminderPlan.plan([], role: .student, products: Self.products, holding: .purchase, now: Self.now).isEmpty)
    }

    @Test func notVerifiedPlansNothing() {
        let facts = [Self.fact(verified: false)]
        #expect(RenewalReminderPlan.plan(facts, role: .student, products: Self.products, holding: .purchase, now: Self.now).isEmpty)
    }

    @Test func aLapsedOrRetryingSubscriptionPlansNothing() {
        for state: SubscriptionFacts.RenewalState in [.expired, .inBillingRetryPeriod, .inGracePeriod, .revoked] {
            let facts = [Self.fact(renewal: state)]
            #expect(RenewalReminderPlan.plan(facts, role: .student, products: Self.products, holding: .purchase, now: Self.now).isEmpty,
                    "renewal state \(state) must plan nothing")
        }
    }

    @Test func autoRenewOffPlansNothing() {
        let facts = [Self.fact(willAutoRenew: false)]
        #expect(RenewalReminderPlan.plan(facts, role: .student, products: Self.products, holding: .purchase, now: Self.now).isEmpty)
    }

    @Test func aSchoolAssignedSeatPlansNothing() {
        // The school, not the student, manages that purchase (M3-B3's own rule) — even though the
        // fact itself is a verified, auto-renewing, currently-subscribed one.
        let facts = [Self.fact(ownership: .assigned)]
        #expect(RenewalReminderPlan.plan(facts, role: .student, products: Self.products, holding: .schoolSeat, now: Self.now).isEmpty)
    }

    @Test func noCountedEntitlementPlansNothing() {
        #expect(RenewalReminderPlan.plan([Self.fact()], role: .student, products: Self.products, holding: .none, now: Self.now).isEmpty)
    }

    @Test func aDifferentRolesFactIsIgnored() {
        let facts = [Self.fact(Self.products.parentAnnual)]
        #expect(RenewalReminderPlan.plan(facts, role: .student, products: Self.products, holding: .purchase, now: Self.now).isEmpty)
    }

    @Test func theLatestExpiryAmongSeveralCountedFactsWins() {
        let facts = [Self.fact(expires: 60 * Self.day), Self.fact(expires: 90 * Self.day)]
        let reminders = RenewalReminderPlan.plan(facts, role: .student, products: Self.products, holding: .purchase, now: Self.now)
        #expect(reminders.first?.fireDate == Self.at(90 * Self.day - 40 * Self.day))
    }

    // MARK: - diff: the auto-renew-off cancellation

    @Test func bothReminderIdentifiersAreScheduledWhenNonePending() {
        let desired = RenewalReminderPlan.plan([Self.fact(expires: 60 * Self.day)], role: .student, products: Self.products,
                                                holding: .purchase, now: Self.now)
        let diff = RenewalReminderPlan.diff(desired: desired, pending: [], role: .student)
        let desiredIDs: Set<String> = Set(desired.map { $0.id })
        let scheduledIDs: Set<String> = Set(diff.toSchedule.map { $0.id })
        #expect(scheduledIDs == desiredIDs)
        #expect(diff.toCancel.isEmpty)
    }

    @Test func anAlreadyPendingReminderIsNeitherScheduledNorCancelled() {
        let desired = RenewalReminderPlan.plan([Self.fact(expires: 60 * Self.day)], role: .student, products: Self.products,
                                                holding: .purchase, now: Self.now)
        let pendingIDs: Set<String> = Set(desired.map { $0.id })
        let diff = RenewalReminderPlan.diff(desired: desired, pending: pendingIDs, role: .student)
        #expect(diff.toSchedule.isEmpty)
        #expect(diff.toCancel.isEmpty)
    }

    @Test func turningAutoRenewOffCancelsBothPendingReminders() {
        let allIDs = RenewalReminderPlan.allIdentifiers(role: .student)
        // Auto-renew is now off: `plan` returns nothing, no matter what was pending before.
        let diff = RenewalReminderPlan.diff(desired: [], pending: allIDs, role: .student)
        #expect(diff.toCancel == allIDs)
        #expect(diff.toSchedule.isEmpty)
    }

    @Test func diffNeverTouchesAnotherRolesIdentifiers() {
        let studentIDs = RenewalReminderPlan.allIdentifiers(role: .student)
        let parentIDs = RenewalReminderPlan.allIdentifiers(role: .parent)
        #expect(studentIDs.isDisjoint(with: parentIDs))
        // The parent's own pending reminders must survive a student-only reconcile with nothing desired.
        let diff = RenewalReminderPlan.diff(desired: [], pending: parentIDs, role: .student)
        #expect(diff.toCancel.isEmpty)
    }

    @Test func diffCancelsOnlyWhatIsBothManagedAndPending() {
        let allIDs = RenewalReminderPlan.allIdentifiers(role: .student)
        let oneID = allIDs.sorted().first!
        let diff = RenewalReminderPlan.diff(desired: [], pending: [oneID], role: .student)
        #expect(diff.toCancel == [oneID])
    }
}
