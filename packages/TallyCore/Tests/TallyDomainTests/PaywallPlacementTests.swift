import Foundation
import Testing
@testable import TallyDomain

/// PAY-06 (GL-01): when the paywall may appear, as a table over every trigger and session; and
/// PAY-05/G-6: what it says, with no grade claim for a school whose grades are not in Canvas.
@Suite("Paywall placement (PAY-06) and content (PAY-05, plan 08 G-6)")
struct PaywallPlacementTests {
    static let now = Date(timeIntervalSince1970: 1_790_000_000)
    static let day: TimeInterval = 24 * 60 * 60
    static let entitled = EntitlementState.entitled(until: now.addingTimeInterval(30 * day))
    static let expiredPastGrace = EntitlementState.entitled(until: now.addingTimeInterval(-4 * day))
    static let lapsed = EntitlementState.lapsed(since: now.addingTimeInterval(-day))

    static func context(_ session: PaywallContext.Session, _ state: EntitlementState?, locked: Bool = false,
                        reconnecting: Bool = false, enforced: Bool = true) -> PaywallContext {
        PaywallContext(session: session, isLocked: locked, isReconnecting: reconnecting, accountState: state, now: now,
                       gate: SubscriptionGate(isEnforced: enforced))
    }

    @Test("Before sign-in (Welcome, search, not enabled, the first sync and its failure): never, whatever the trigger")
    func neverSignedOut() {
        for trigger in PaywallTrigger.allCases {
            for state: EntitlementState? in [nil, .preview, Self.lapsed, Self.entitled] {
                #expect(!PaywallPlacement.shows(trigger, in: Self.context(.signedOut, state)), "\(trigger), \(String(describing: state))")
            }
        }
    }

    @Test("Signed in with something to buy: after the first sync and from a locked feature")
    func signedInNeedingPurchase() {
        for state in [EntitlementState.preview, Self.lapsed, Self.expiredPastGrace] {
            #expect(PaywallPlacement.shows(.firstSyncFinished, in: Self.context(.signedIn, state)), "\(state)")
            #expect(PaywallPlacement.shows(.lockedFeature, in: Self.context(.signedIn, state)), "\(state)")
            #expect(PaywallPlacement.shows(.settings, in: Self.context(.signedIn, state)), "\(state)")
        }
    }

    @Test("Signed in and entitled (inside the offline grace too): never by itself; Settings still shows the plans")
    func signedInEntitled() {
        let insideGrace = EntitlementState.entitled(until: Self.now.addingTimeInterval(-2 * Self.day))
        for state in [Self.entitled, insideGrace] {
            #expect(!PaywallPlacement.shows(.firstSyncFinished, in: Self.context(.signedIn, state)))
            #expect(!PaywallPlacement.shows(.lockedFeature, in: Self.context(.signedIn, state)))
            #expect(PaywallPlacement.shows(.settings, in: Self.context(.signedIn, state)))
        }
    }

    @Test("While the state is unknown (before the launch's first), never by itself")
    func unknownStateWaits() {
        #expect(!PaywallPlacement.shows(.firstSyncFinished, in: Self.context(.signedIn, nil)))
        #expect(!PaywallPlacement.shows(.lockedFeature, in: Self.context(.signedIn, nil)))
    }

    @Test("Never while the app lock or its cover is up, or during a reconnect")
    func lockAndReconnect() {
        for trigger in PaywallTrigger.allCases {
            #expect(!PaywallPlacement.shows(trigger, in: Self.context(.signedIn, .preview, locked: true)), "\(trigger)")
            #expect(!PaywallPlacement.shows(trigger, in: Self.context(.sample, .demo, locked: true)), "\(trigger)")
        }
        #expect(!PaywallPlacement.shows(.firstSyncFinished, in: Self.context(.signedIn, .preview, reconnecting: true)))
        #expect(!PaywallPlacement.shows(.lockedFeature, in: Self.context(.signedIn, .preview, reconnecting: true)))
    }

    @Test("Sample mode: never by itself; Settings → Subscription behind the interstitial (PAY-09)")
    func sampleMode() {
        for state: EntitlementState? in [nil, .demo, .preview, Self.lapsed] {
            #expect(!PaywallPlacement.shows(.firstSyncFinished, in: Self.context(.sample, state)))
            #expect(!PaywallPlacement.shows(.lockedFeature, in: Self.context(.sample, state)))
        }
        #expect(PaywallPlacement.shows(.settings, in: Self.context(.sample, .demo)))
        #expect(PaywallPlacement.needsInterstitial(.settings, in: Self.context(.sample, .demo)))
        #expect(!PaywallPlacement.needsInterstitial(.settings, in: Self.context(.signedIn, .preview)))
        #expect(!PaywallPlacement.needsInterstitial(.lockedFeature, in: Self.context(.sample, .demo)))
    }

    @Test("Not enforced (by injection): nothing is locked, so nothing is offered by itself")
    func notEnforced() {
        #expect(!PaywallPlacement.shows(.firstSyncFinished, in: Self.context(.signedIn, .preview, enforced: false)))
        #expect(!PaywallPlacement.shows(.lockedFeature, in: Self.context(.signedIn, Self.lapsed, enforced: false)))
    }

    // MARK: - PAY-05 and G-6: what it says

    @Test("A school whose grades are not in Canvas gets no grade, what-if or grade-alert claim (G-6)")
    func noGradeClaimsForNoneInCanvas() {
        for eligible in [true, false] {
            let content = PaywallContent(school: .noneInCanvas, isEligibleForTrial: eligible)
            #expect(content.variant == .noGradeClaims)
            #expect(!content.features.contains { $0.claimsGrades }, "\(content.features)")
            #expect(content.features == [.dueDates, .reminders, .workload, .privacy])
        }
    }

    @Test("Every other school summary gets the standard list, which leads with grades", arguments: [
        SchoolGradeSummary.allInCanvas, .mixed(outside: 2), .undetermined,
    ])
    func standardForTheRest(_ school: SchoolGradeSummary) {
        let content = PaywallContent(school: school, isEligibleForTrial: true)
        #expect(content.variant == .standard)
        #expect(content.features == [.grades, .dueDates, .reminders, .insights, .privacy])
    }

    @Test("The trial line and the free-trial button only when the Apple Account is eligible")
    func trialOnlyWhenEligible() {
        let eligible = PaywallContent(school: .allInCanvas, isEligibleForTrial: true)
        #expect(eligible.showsTrial && eligible.action == .startFreeTrial)
        let notEligible = PaywallContent(school: .allInCanvas, isEligibleForTrial: false)
        #expect(!notEligible.showsTrial && notEligible.action == .subscribe)
    }
}
