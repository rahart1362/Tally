#if DEBUG
import Foundation
import Synchronization
import Testing
import TallyDomain
import TallyStore
import TallyTestSupport
@testable import TallyFeatures

/// SEC2-01 (sec-fix-5): `AgeAssuranceModel` must persist `lastAcknowledgedSignificantChangeVersion`
/// only once this launch's significant-change consent resolved in the minor's/adult's favor
/// (`.granted`) or was never required (`.notRequired`) -- including a later `.granted` that
/// arrives through `listenForAnswers`. A `.pending` question, a `.denied` answer or an
/// `.unavailable` attempt must leave the version unacknowledged, so the very next launch asks
/// again. These tests run two model instances over the SAME fake stores to simulate exactly that
/// relaunch, the way `AppLockModelTests` simulates a cold launch over the same preference store.
@Suite("AgeAssuranceModel: SEC2-01 significant-change persistence across a relaunch")
@MainActor
struct AgeAssuranceModelTests {
    private static let appVersion = "9.2.0"
    private static let restrictedSignal = AgeAssuranceSignal(
        category: .youngerTeen,
        significantChangeRequirement: SignificantChangeRequirement(parentalConsentRequired: true))

    /// One launch's model. `ratingCode` must differ from whatever `versionStore` already holds as
    /// `lastKnownAgeRatingCode`, so `AgeRatingChangeDetector.didChange` fires and
    /// `AgeRequestPolicy.trigger` returns `.firstLaunchOfSignificantChangeVersion` — the trigger
    /// this app ships today is the compile-time `TallyConfig.currentReleaseIsSignificantChange`,
    /// which a test cannot flip, but both triggers feed the exact same `evaluate()` path, and
    /// `AppStoreAgeRatingReading` is the seam the model already exposes for tests. `outcome`
    /// defaults to a restricted `.shared` signal (every existing test's scenario); AGE-2's
    /// declined/unavailable tests override it.
    private func launch(ratingCode: Int, outcome: AgeAssuranceOutcome = .shared(Self.restrictedSignal),
                        consent: ScriptedSignificantChangeConsent,
                        recordStore: InMemoryAgeRequestRecordStore,
                        versionStore: InMemorySignificantChangeVersionStore) -> AgeAssuranceModel {
        AgeAssuranceModel(requester: FixedAgeAssuranceRequester(outcome: outcome),
                          consent: consent,
                          ageRating: FixedAgeRating(code: ratingCode),
                          recordStore: recordStore,
                          versionStore: versionStore,
                          clock: TestClock(),
                          currentAppVersion: Self.appVersion)
    }

    /// Polls until `evaluate()`'s one `versionStore.save` for this launch has landed: that save is
    /// unconditional and always carries the just-observed `ratingCode`, so seeing it land is proof
    /// the whole async pipeline (request, consent, acknowledgement decision) finished.
    private func waitForEvaluation(_ versionStore: InMemorySignificantChangeVersionStore, ratingCode: Int) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while await versionStore.load()?.lastKnownAgeRatingCode != ratingCode {
            guard ContinuousClock.now < deadline else {
                Issue.record("evaluate() never finished (lastKnownAgeRatingCode never reached \(ratingCode))")
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test("pending, denied and unavailable are never acknowledged, and the SAME version asks again on the very next launch",
          arguments: [SignificantChangeConsentOutcome.pending, .denied, .unavailable])
    func unresolvedOutcomesAskAgain(_ outcome: SignificantChangeConsentOutcome) async throws {
        let recordStore = InMemoryAgeRequestRecordStore()
        let versionStore = InMemorySignificantChangeVersionStore(
            SignificantChangeVersionState(lastAcknowledgedSignificantChangeVersion: nil, lastKnownAgeRatingCode: 4))
        let consent = ScriptedSignificantChangeConsent(outcome)

        let first = launch(ratingCode: 9, consent: consent, recordStore: recordStore, versionStore: versionStore)
        first.evaluateIfDue(isFirstLaunchAfterInstall: false, isAboutToPresentPaywallPurchase: false)
        try await waitForEvaluation(versionStore, ratingCode: 9)

        #expect(first.consentOutcome == outcome)
        #expect(await versionStore.load()?.lastAcknowledgedSignificantChangeVersion == nil,
                "a \(outcome) outcome must never be acknowledged")
        #expect(consent.requestCount == 1)

        // Relaunch: a second model instance over the SAME stores (a fresh process reading the
        // same disk state). The unacknowledged version must trigger the request again.
        let second = launch(ratingCode: 14, consent: consent, recordStore: recordStore, versionStore: versionStore)
        second.evaluateIfDue(isFirstLaunchAfterInstall: false, isAboutToPresentPaywallPurchase: false)
        try await waitForEvaluation(versionStore, ratingCode: 14)

        #expect(second.outcome != nil, "the relaunch never asked again")
        #expect(consent.requestCount == 2, "SEC2-01: a \(outcome) outcome must ask again on the next launch")
        #expect(await versionStore.load()?.lastAcknowledgedSignificantChangeVersion == nil)
        // AGE-1's invariant: the only things ever written are the version string and the rating
        // baseline, never an age or category.
        #expect(await recordStore.load()?.lastRequestedAt != nil)
    }

    @Test("AGE-2: declined is recorded as a request, and (today's behaviour) a significant-change version IS acknowledged")
    func declinedIsRecordedAndAcknowledgesTheVersion() async throws {
        let recordStore = InMemoryAgeRequestRecordStore()
        let versionStore = InMemorySignificantChangeVersionStore(
            SignificantChangeVersionState(lastAcknowledgedSignificantChangeVersion: nil, lastKnownAgeRatingCode: 4))
        let consent = ScriptedSignificantChangeConsent(.notRequired)

        let model = launch(ratingCode: 9, outcome: .declined, consent: consent, recordStore: recordStore, versionStore: versionStore)
        model.evaluateIfDue(isFirstLaunchAfterInstall: false, isAboutToPresentPaywallPurchase: false)
        try await waitForEvaluation(versionStore, ratingCode: 9)

        #expect(model.outcome == .declined)
        #expect(await recordStore.load()?.lastRequestedAt != nil,
                "a decline is a real, informed answer and must count toward the 12-month floor")
        #expect(await versionStore.load()?.lastAcknowledgedSignificantChangeVersion == Self.appVersion,
                "a decline resolves the significant-change version today, same as before this split")
        #expect(consent.requestCount == 0, "no age signal was ever shared, so there is nothing to ask consent about")
    }

    @Test("AGE-2: unavailable is never recorded as a request, never acknowledges a significant-change version, and a relaunch retries")
    func unavailableNeverRecordsAndRetries() async throws {
        let recordStore = InMemoryAgeRequestRecordStore()
        let versionStore = InMemorySignificantChangeVersionStore(
            SignificantChangeVersionState(lastAcknowledgedSignificantChangeVersion: nil, lastKnownAgeRatingCode: 4))
        let consent = ScriptedSignificantChangeConsent(.notRequired)

        let first = launch(ratingCode: 9, outcome: .unavailable, consent: consent, recordStore: recordStore, versionStore: versionStore)
        first.evaluateIfDue(isFirstLaunchAfterInstall: false, isAboutToPresentPaywallPurchase: false)
        try await waitForEvaluation(versionStore, ratingCode: 9)

        #expect(first.outcome == .unavailable)
        #expect(await recordStore.load()?.lastRequestedAt == nil,
                "a technical failure must not count toward the 12-month floor")
        #expect(await versionStore.load()?.lastAcknowledgedSignificantChangeVersion == nil,
                "a technical failure must never acknowledge the significant-change version (the #85 residual)")
        #expect(consent.requestCount == 0)

        // Relaunch: a second model instance over the SAME stores (a fresh process reading the
        // same disk state). Nothing was persisted, so the still-unacknowledged version must
        // trigger the request again — production relies on `TallyConfig
        // .currentReleaseIsSignificantChange` staying true across every launch of an
        // unacknowledged version; a test cannot flip that compile-time flag, so (like
        // `unresolvedOutcomesAskAgain` above) it uses a different rating code to re-fire the
        // same `evaluate()` path through the rating-change detector instead.
        let second = launch(ratingCode: 14, outcome: .unavailable, consent: consent, recordStore: recordStore, versionStore: versionStore)
        second.evaluateIfDue(isFirstLaunchAfterInstall: false, isAboutToPresentPaywallPurchase: false)
        try await waitForEvaluation(versionStore, ratingCode: 14)

        #expect(second.outcome == .unavailable, "the relaunch never retried the request")
        #expect(await recordStore.load()?.lastRequestedAt == nil)
        #expect(await versionStore.load()?.lastAcknowledgedSignificantChangeVersion == nil)
    }

    @Test("granted is acknowledged at once, and the relaunch never asks again")
    func grantedIsAcknowledgedAndNeverAsksAgain() async throws {
        let recordStore = InMemoryAgeRequestRecordStore()
        let versionStore = InMemorySignificantChangeVersionStore(
            SignificantChangeVersionState(lastAcknowledgedSignificantChangeVersion: nil, lastKnownAgeRatingCode: 4))
        let consent = ScriptedSignificantChangeConsent(.granted)

        let first = launch(ratingCode: 9, consent: consent, recordStore: recordStore, versionStore: versionStore)
        first.evaluateIfDue(isFirstLaunchAfterInstall: false, isAboutToPresentPaywallPurchase: false)
        try await waitForEvaluation(versionStore, ratingCode: 9)

        #expect(await versionStore.load()?.lastAcknowledgedSignificantChangeVersion == Self.appVersion)
        #expect(consent.requestCount == 1)

        // Relaunch: already acknowledged, so the request must not fire again even though the
        // rating keeps "changing" underneath it.
        let second = launch(ratingCode: 14, consent: consent, recordStore: recordStore, versionStore: versionStore)
        second.evaluateIfDue(isFirstLaunchAfterInstall: false, isAboutToPresentPaywallPurchase: false)
        try await Task.sleep(for: .milliseconds(100)) // give a (wrongly) re-triggered request time to run
        #expect(second.outcome == nil, "an acknowledged version must not ask again")
        #expect(consent.requestCount == 1)
    }

    @Test("a later .granted through listenForAnswers finishes the deferred acknowledgement")
    func lateGrantedAnswerFinishesTheAcknowledgement() async throws {
        let recordStore = InMemoryAgeRequestRecordStore()
        let versionStore = InMemorySignificantChangeVersionStore(
            SignificantChangeVersionState(lastAcknowledgedSignificantChangeVersion: nil, lastKnownAgeRatingCode: 4))
        let consent = ScriptedSignificantChangeConsent(.pending)

        let model = launch(ratingCode: 9, consent: consent, recordStore: recordStore, versionStore: versionStore)
        model.evaluateIfDue(isFirstLaunchAfterInstall: false, isAboutToPresentPaywallPurchase: false)
        try await waitForEvaluation(versionStore, ratingCode: 9)
        #expect(await versionStore.load()?.lastAcknowledgedSignificantChangeVersion == nil)

        // `listenForAnswers` subscribes on its own task, started from `init`; wait for that
        // subscription to actually exist before sending the answer, or `sendAnswer` could run
        // before there is any continuation to yield to.
        let listenerDeadline = ContinuousClock.now + .seconds(5)
        while !consent.hasActiveListener {
            guard ContinuousClock.now < listenerDeadline else {
                Issue.record("listenForAnswers never subscribed to pendingAnswers()")
                break
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        consent.sendAnswer(.granted)
        let deadline = ContinuousClock.now + .seconds(5)
        while await versionStore.load()?.lastAcknowledgedSignificantChangeVersion != Self.appVersion {
            guard ContinuousClock.now < deadline else {
                Issue.record("the late .granted answer was never persisted")
                break
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await versionStore.load()?.lastAcknowledgedSignificantChangeVersion == Self.appVersion)
        #expect(model.consentOutcome == .granted)
    }
}

private struct FixedAgeAssuranceRequester: AgeAssuranceRequesting {
    let outcome: AgeAssuranceOutcome
    func requestAgeAssurance() async -> AgeAssuranceOutcome { outcome }
}

private struct FixedAgeRating: AppStoreAgeRatingReading {
    let code: Int?
    func currentAgeRatingCode() async -> Int? { code }
}

/// Answers `requestConsent` with a fixed scripted outcome and counts calls; `sendAnswer` pushes a
/// later answer through `pendingAnswers()`, the way a real parental response arrives (SEC2-01).
private final class ScriptedSignificantChangeConsent: SignificantChangeConsenting {
    private let state: Mutex<(outcome: SignificantChangeConsentOutcome, count: Int,
                               continuations: [AsyncStream<SignificantChangeConsentOutcome>.Continuation])>

    init(_ outcome: SignificantChangeConsentOutcome) {
        state = Mutex((outcome, 0, []))
    }

    var requestCount: Int { state.withLock { $0.count } }
    /// Whether `pendingAnswers()` has been called and its continuation is still live -- lets a
    /// test wait for `listenForAnswers`'s own subscription task to actually start before sending
    /// an answer, instead of racing it.
    var hasActiveListener: Bool { state.withLock { !$0.continuations.isEmpty } }

    func requestConsent(changeDescription: String, for requirement: SignificantChangeRequirement) async -> SignificantChangeConsentOutcome {
        state.withLock { current in
            current.count += 1
            return current.outcome
        }
    }

    func pendingAnswers() -> AsyncStream<SignificantChangeConsentOutcome> {
        let (stream, continuation) = AsyncStream<SignificantChangeConsentOutcome>.makeStream()
        state.withLock { $0.continuations.append(continuation) }
        return stream
    }

    func sendAnswer(_ outcome: SignificantChangeConsentOutcome) {
        state.withLock { $0.continuations.forEach { $0.yield(outcome) } }
    }
}
#endif
