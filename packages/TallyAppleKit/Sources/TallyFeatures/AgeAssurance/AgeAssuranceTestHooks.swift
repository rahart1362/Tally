#if DEBUG || TALLY_TEST_HOOKS
import Foundation
import TallyDomain

/// AGE-1 (EB-01(h): "a UI test of the consent screen") — a UI-test hook, built like
/// `SubscriptionTestHooks`: a synthetic requester/consent pair, never real `DeclaredAgeRange`/
/// `PermissionKit` state, and never compiled into a shipping Release build (the same `#if DEBUG ||
/// TALLY_TEST_HOOKS` guard; CI's "shipping Release build has no UI-test hooks" step would fail on
/// the `TallyTestHooks.` prefix otherwise).
///
/// Launch argument `-TallyTestHooks.ageAssurance <allow|restricted>`. `restricted` scripts a
/// minor whose significant-change consent is denied, so `AgeRestrictedView` shows; the hook also
/// fires the one request itself (`evaluateIfDue`), since a real UI test's app install may have
/// already consumed `LaunchBootstrapper`'s "first launch after install" sentinel in an earlier
/// test method — this hook does not depend on that real, one-time signal at all.
public nonisolated struct AgeAssuranceTestHooks: Sendable {
    public static let key = "TallyTestHooks.ageAssurance"

    public nonisolated enum Scripted: String, Sendable {
        /// EB-01(g): regulatory requirements do not apply — every existing UI test's default,
        /// unaffected by this feature.
        case allow
        /// A minor (`.youngerTeen`) whose significant-change consent was denied: `AgeRestrictedView`
        /// shows over the signed-in Home.
        case restricted
    }

    public let scripted: Scripted?

    public init(arguments: [String]) {
        guard let flag = arguments.lastIndex(of: "-\(Self.key)"),
              arguments.index(after: flag) < arguments.endIndex else {
            scripted = nil
            return
        }
        scripted = Scripted(rawValue: arguments[arguments.index(after: flag)])
    }

    /// `nil` when the hook is off: the composition root keeps its real `AgeAssuranceModel`.
    @MainActor
    public func model() -> AgeAssuranceModel? {
        guard let scripted else { return nil }
        let model: AgeAssuranceModel
        switch scripted {
        case .allow:
            model = AgeAssuranceModel(requester: HookAgeAssuranceRequester(outcome: .regulatoryRequirementsDoNotApply))
        case .restricted:
            model = AgeAssuranceModel(
                requester: HookAgeAssuranceRequester(outcome: .shared(AgeAssuranceSignal(
                    category: .youngerTeen,
                    significantChangeRequirement: SignificantChangeRequirement(parentalConsentRequired: true)))),
                consent: HookSignificantChangeConsent(outcome: .denied))
        }
        // Bypasses the real trigger policy's "first launch after install"/"significant-change
        // version" signals entirely (EB-01(b) is covered by `AgeAssuranceTests.swift`'s pure
        // tests, not this UI test): this hook only needs ONE request to fire, deterministically,
        // regardless of which launch of the UI-test run this is.
        model.evaluateIfDue(isFirstLaunchAfterInstall: true, isAboutToPresentPaywallPurchase: false)
        return model
    }
}

nonisolated struct HookAgeAssuranceRequester: AgeAssuranceRequesting {
    let outcome: AgeAssuranceOutcome
    func requestAgeAssurance() async -> AgeAssuranceOutcome { outcome }
}

nonisolated struct HookSignificantChangeConsent: SignificantChangeConsenting {
    let outcome: SignificantChangeConsentOutcome
    func requestConsent(changeDescription: String, for requirement: SignificantChangeRequirement) async -> SignificantChangeConsentOutcome { outcome }
    func pendingAnswers() -> AsyncStream<SignificantChangeConsentOutcome> { AsyncStream { $0.finish() } }
}
#endif
