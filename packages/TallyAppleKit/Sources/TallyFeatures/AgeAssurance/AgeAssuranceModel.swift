import Foundation
import Observation
import TallyDomain
import TallyStore

/// AGE-1 (engineering-backlog-us.md §2 EB-01–EB-04): the age-assurance state for this process,
/// built the way `AppLockModel` is (architecture.md §3.1's `@MainActor @Observable` model
/// pattern). Orchestrates EB-01(b)'s three request points plus the 12-month floor, EB-02's
/// significant-change consent, and EB-03's age-rating trigger; exposes `gateDecision` for
/// `RootView` to show the neutral restricted screen (EB-01(e)/EB-02(b)).
///
/// **Binding invariant.** The only things this model ever persists are a `Date`
/// (`AgeRequestRecord`, through `recordStore` — EB-01(c)'s "single, easily removed field") and two
/// non-age values (`SignificantChangeVersionState`, through `versionStore`: the app's own version
/// string and StoreKit's age-rating code — neither is a person's age). `outcome` and
/// `consentOutcome` live in memory for this process only and are never logged.
@MainActor
@Observable
public final class AgeAssuranceModel {
    // Plan 06 A2 / CI's `nm` gate: see `AppModel`'s identical note on why this must stay explicit
    // and `nonisolated` in a default-`MainActor` module.
    nonisolated deinit {}

    /// This process's one `requestAgeAssurance()` result, in memory only (EB-01(c)). `nil` before
    /// the first request this launch, or when none was due.
    public private(set) var outcome: AgeAssuranceOutcome?
    public private(set) var consentOutcome: SignificantChangeConsentOutcome = .notRequired

    /// EB-01(e)/EB-02(b): `RootView` shows the neutral restricted screen over the signed-in Home
    /// exactly when this is `.restrictedPendingConsent`. EB-01(g)/EB-02's "declined or unavailable
    /// never blocks" is `AgeGate`'s job, not this model's.
    public var gateDecision: AgeGateDecision { AgeGate.decision(for: consentOutcome) }

    @ObservationIgnored private var hasRequestedThisProcessLaunch = false
    @ObservationIgnored private let requester: any AgeAssuranceRequesting
    @ObservationIgnored private let consent: any SignificantChangeConsenting
    @ObservationIgnored private let ageRating: any AppStoreAgeRatingReading
    @ObservationIgnored private let recordStore: any AgeRequestRecordStoring
    @ObservationIgnored private let versionStore: any SignificantChangeVersionStoring
    @ObservationIgnored private let clock: any DateProviding
    @ObservationIgnored private let currentAppVersion: String
    /// The sentence a parent/guardian (or a verified adult) sees describing what changed. Plain
    /// English, handed verbatim to the system UI: neither `SignificantAppUpdateTopic` nor
    /// `showSignificantUpdateAcknowledgment` takes a localized resource (DeclaredAgeRange's own
    /// sample code hardcodes one English sentence) — an open item for a future localized release,
    /// not a gap in this one, since nothing ships a significant change yet (`TallyConfig
    /// .currentReleaseIsSignificantChange == false`).
    @ObservationIgnored private let changeDescription: String
    @ObservationIgnored private let evaluateTask = TaskBox()
    @ObservationIgnored private let listenTask = TaskBox()

    public init(requester: any AgeAssuranceRequesting = UnavailableAgeAssurance(),
                consent: any SignificantChangeConsenting = UnavailableSignificantChangeConsent(),
                ageRating: any AppStoreAgeRatingReading = UnavailableAppStoreAgeRating(),
                recordStore: any AgeRequestRecordStoring = InMemoryAgeRequestRecordStore(),
                versionStore: any SignificantChangeVersionStoring = InMemorySignificantChangeVersionStore(),
                clock: any DateProviding = SystemDateProvider(),
                currentAppVersion: String = AgeAssuranceModel.bundleShortVersion(),
                changeDescription: String = "") {
        self.requester = requester
        self.consent = consent
        self.ageRating = ageRating
        self.recordStore = recordStore
        self.versionStore = versionStore
        self.clock = clock
        self.currentAppVersion = currentAppVersion
        self.changeDescription = changeDescription
        listenTask.replace(with: Task { [weak self] in await self?.listenForAnswers() })
    }

    public static func bundleShortVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    /// EB-01(b): called at each of the three request points this app controls (`AppModel.apply(_:)`
    /// once a launch resolves its route, and before presenting the paywall); the 12-month floor is
    /// evaluated the same way, every time. Re-entrant: a call while an earlier one is still running
    /// supersedes it (the newer call has the same or newer `clock.now()`, so nothing is lost).
    public func evaluateIfDue(isFirstLaunchAfterInstall: Bool, isAboutToPresentPaywallPurchase: Bool) {
        evaluateTask.replace(with: Task { [weak self] in
            await self?.evaluate(isFirstLaunchAfterInstall: isFirstLaunchAfterInstall,
                                 isAboutToPresentPaywallPurchase: isAboutToPresentPaywallPurchase)
        })
    }

    private func evaluate(isFirstLaunchAfterInstall: Bool, isAboutToPresentPaywallPurchase: Bool) async {
        let record = await recordStore.load()
        var versionState = await versionStore.load() ?? SignificantChangeVersionState()
        let now = clock.now()
        // EB-03: StoreKit's age-rating signal, observed every evaluation regardless of whether a
        // request ends up due this time — "a change runs EB-02(b)" needs the comparison made
        // before this app's own `currentReleaseIsSignificantChange` flag is even consulted.
        let ratingCode = await ageRating.currentAgeRatingCode()
        let ratingChanged = AgeRatingChangeDetector.didChange(current: ratingCode, lastKnown: versionState.lastKnownAgeRatingCode)
        if let ratingCode { versionState.lastKnownAgeRatingCode = ratingCode }
        let isSignificantChangeVersion = (TallyConfig.currentReleaseIsSignificantChange || ratingChanged)
            && versionState.lastAcknowledgedSignificantChangeVersion != currentAppVersion

        let input = AgeRequestPolicyInput(hasRequestedThisProcessLaunch: hasRequestedThisProcessLaunch,
                                          isFirstLaunchAfterInstall: isFirstLaunchAfterInstall,
                                          isFirstLaunchOfSignificantChangeVersion: isSignificantChangeVersion,
                                          isAboutToPresentPaywallPurchase: isAboutToPresentPaywallPurchase,
                                          lastRequestedAt: record?.lastRequestedAt, now: now)
        guard let trigger = AgeRequestPolicy.trigger(for: input) else {
            try? await versionStore.save(versionState) // still records the rating observation
            return
        }
        hasRequestedThisProcessLaunch = true
        // EB-01(c): the date of the REQUEST itself, recorded before Apple answers — it is a
        // request record, not a response record, and every trigger here is a real presentation
        // of the system UI (or an attempt at one).
        try? await recordStore.save(AgeRequestRecord(lastRequestedAt: now))
        let result = await requester.requestAgeAssurance()
        outcome = result
        if trigger == .firstLaunchOfSignificantChangeVersion {
            versionState.lastAcknowledgedSignificantChangeVersion = currentAppVersion
        }
        try? await versionStore.save(versionState)

        guard case .shared(let signal) = result, signal.significantChangeRequirement.isAny else { return }
        consentOutcome = await consent.requestConsent(changeDescription: changeDescription,
                                                       for: signal.significantChangeRequirement)
    }

    /// EB-02(b): a parent/guardian's answer can arrive long after `requestConsent` returned
    /// `.pending` (they may not open Messages right away). This stream runs for the process's
    /// whole lifetime so that answer still reaches `gateDecision`.
    private func listenForAnswers() async {
        for await answer in consent.pendingAnswers() {
            consentOutcome = answer
        }
    }
}
