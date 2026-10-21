import Foundation
import Testing
@testable import TallyDomain

/// AGE-1 (engineering-backlog-us.md §2 EB-01–EB-04): every pure decision function, driven with
/// injected results only (EB-01(h)) — nothing here touches `DeclaredAgeRange`/`PermissionKit`.
@Suite("AGE-1: AgeCategory, AgeGate, AgeRequestPolicy, AgeRatingChangeDetector")
struct AgeAssuranceTests {
    // MARK: - AgeCategory.fromLowerBound (matrix.md §2's four categories)

    @Test("lowerBound nil (under the lowest gate, 13) is child")
    func nilLowerBoundIsChild() {
        #expect(AgeCategory.fromLowerBound(nil) == .child)
    }

    @Test(arguments: [
        (0, AgeCategory.child), (12, .child),
        (13, .youngerTeen), (15, .youngerTeen),
        (16, .olderTeen), (17, .olderTeen),
        (18, .adult), (40, .adult),
    ])
    func lowerBoundMapsToCategory(_ lowerBound: Int, _ expected: AgeCategory) {
        #expect(AgeCategory.fromLowerBound(lowerBound) == expected)
    }

    @Test("isMinor is true for child/youngerTeen/olderTeen and false for adult/unknown")
    func isMinor() {
        #expect(AgeCategory.child.isMinor)
        #expect(AgeCategory.youngerTeen.isMinor)
        #expect(AgeCategory.olderTeen.isMinor)
        #expect(!AgeCategory.adult.isMinor)
        #expect(!AgeCategory.unknown.isMinor)
    }

    // MARK: - AgeGate.decision (EB-01(e)/EB-02(b)/(f)/(g))

    @Test(arguments: [
        SignificantChangeConsentOutcome.notRequired, .granted, .unavailable,
    ])
    func theseConsentOutcomesAlwaysAllow(_ outcome: SignificantChangeConsentOutcome) {
        #expect(AgeGate.decision(for: outcome) == .allow)
    }

    @Test(arguments: [SignificantChangeConsentOutcome.pending, .denied])
    func theseConsentOutcomesRestrict(_ outcome: SignificantChangeConsentOutcome) {
        #expect(AgeGate.decision(for: outcome) == .restrictedPendingConsent)
    }

    @Test("EB-01(g): unavailable never blocks, even though it is not an explicit grant")
    func unavailableNeverBlocks() {
        #expect(AgeGate.decision(for: .unavailable) == .allow)
    }

    // MARK: - AgeRequestPolicy.trigger (EB-01(b), matrix.md §2 duty table)

    private func input(hasRequestedThisProcessLaunch: Bool = false, isFirstLaunchAfterInstall: Bool = false,
                        isFirstLaunchOfSignificantChangeVersion: Bool = false,
                        isAboutToPresentPaywallPurchase: Bool = false, lastRequestedAt: Date? = nil,
                        now: Date = Date(timeIntervalSince1970: 1_800_000_000)) -> AgeRequestPolicyInput {
        AgeRequestPolicyInput(hasRequestedThisProcessLaunch: hasRequestedThisProcessLaunch,
                              isFirstLaunchAfterInstall: isFirstLaunchAfterInstall,
                              isFirstLaunchOfSignificantChangeVersion: isFirstLaunchOfSignificantChangeVersion,
                              isAboutToPresentPaywallPurchase: isAboutToPresentPaywallPurchase,
                              lastRequestedAt: lastRequestedAt, now: now)
    }

    @Test("already requested this process launch: never asks again, whatever else is true")
    func alreadyRequestedThisLaunchNeverAsksAgain() {
        let everyTriggerTrue = input(hasRequestedThisProcessLaunch: true, isFirstLaunchAfterInstall: true,
                                     isFirstLaunchOfSignificantChangeVersion: true,
                                     isAboutToPresentPaywallPurchase: true, lastRequestedAt: .distantPast)
        #expect(AgeRequestPolicy.trigger(for: everyTriggerTrue) == nil)
    }

    @Test("first launch after install wins over every other trigger")
    func firstLaunchAfterInstallWins() {
        let i = input(isFirstLaunchAfterInstall: true, isFirstLaunchOfSignificantChangeVersion: true,
                      isAboutToPresentPaywallPurchase: true)
        #expect(AgeRequestPolicy.trigger(for: i) == .firstLaunchAfterInstall)
    }

    @Test("first launch of a significant-change version wins over the paywall and the routine floor")
    func significantChangeVersionWinsOverPaywall() {
        let i = input(isFirstLaunchOfSignificantChangeVersion: true, isAboutToPresentPaywallPurchase: true)
        #expect(AgeRequestPolicy.trigger(for: i) == .firstLaunchOfSignificantChangeVersion)
    }

    @Test("before a paywall purchase, when nothing else is due")
    func paywallPurchaseTrigger() {
        #expect(AgeRequestPolicy.trigger(for: input(isAboutToPresentPaywallPurchase: true)) == .beforePaywallPurchase)
    }

    @Test("never requested before, and none of the one-shot triggers are true: nothing (not a routine re-request)")
    func neverRequestedIsNotRoutine() {
        #expect(AgeRequestPolicy.trigger(for: input(lastRequestedAt: nil)) == nil)
    }

    @Test("exactly 12 months since the last request: due")
    func twelveMonthsIsDue() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let last = Date(timeIntervalSince1970: 1_700_000_000)
        let now = calendar.date(byAdding: .month, value: 12, to: last)!
        #expect(AgeRequestPolicy.trigger(for: input(lastRequestedAt: last, now: now)) == .routineReRequest)
    }

    @Test("one day short of 12 months: not yet due")
    func justUnderTwelveMonthsIsNotDue() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let last = Date(timeIntervalSince1970: 1_700_000_000)
        let almostAYear = calendar.date(byAdding: .day, value: -1, to: calendar.date(byAdding: .month, value: 12, to: last)!)!
        #expect(AgeRequestPolicy.trigger(for: input(lastRequestedAt: last, now: almostAYear)) == nil)
    }

    @Test("the routine floor still yields to a higher-priority trigger that also happens to be true")
    func routineFloorYieldsToHigherPriorityTriggers() {
        let i = input(isFirstLaunchAfterInstall: true, lastRequestedAt: .distantPast)
        #expect(AgeRequestPolicy.trigger(for: i) == .firstLaunchAfterInstall)
    }

    // MARK: - AgeRatingChangeDetector (EB-03)

    @Test("no prior observation is never a change (the first read, not a change)")
    func firstObservationIsNotAChange() {
        #expect(!AgeRatingChangeDetector.didChange(current: 9, lastKnown: nil))
    }

    @Test("an unavailable current value is never a change")
    func unavailableCurrentIsNotAChange() {
        #expect(!AgeRatingChangeDetector.didChange(current: nil, lastKnown: 4))
    }

    @Test("the same code twice is not a change")
    func sameCodeIsNotAChange() {
        #expect(!AgeRatingChangeDetector.didChange(current: 4, lastKnown: 4))
    }

    @Test("a different code is a change, in either direction")
    func differentCodeIsAChange() {
        #expect(AgeRatingChangeDetector.didChange(current: 12, lastKnown: 4))
        #expect(AgeRatingChangeDetector.didChange(current: 4, lastKnown: 12))
    }
}
