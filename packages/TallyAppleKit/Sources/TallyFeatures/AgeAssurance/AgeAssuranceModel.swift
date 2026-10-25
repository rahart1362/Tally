import Foundation
import Observation
import Synchronization
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
    /// SEC2-14: `evaluateBeforePaywall()`'s bounded wait, on whatever `Clock` `init` was given
    /// (production: `ContinuousClock`; tests: a clock that resolves at once, or on command, so
    /// nothing waits in real time). Captured as a closure the way `CanvasClient`'s `sleep` is, so
    /// the generic `Clock` type never has to be stored.
    @ObservationIgnored private let sleepForPaywallWait: @Sendable (Duration) async throws -> Void
    /// SEC2-01: set while this launch's significant-change consent is still `.pending`, `.denied`
    /// or `.unavailable` — i.e. not yet safe to acknowledge. A later `.granted` for THIS version,
    /// arriving through `listenForAnswers`, finishes the acknowledgement `evaluate` deferred.
    @ObservationIgnored private var unacknowledgedSignificantChangeVersion: String?

    /// - Parameter paywallWaitClock: measures `evaluateBeforePaywall()`'s bounded wait
    ///   (`TallyConfig.ageAssurancePaywallWaitBudget`). Tests pass a clock whose `sleep` they
    ///   control (a virtual one that resolves at once, or a gated one that resolves on command),
    ///   the way `CanvasClient`'s `clock` parameter works.
    public init<C: Clock>(requester: any AgeAssuranceRequesting = UnavailableAgeAssurance(),
                consent: any SignificantChangeConsenting = UnavailableSignificantChangeConsent(),
                ageRating: any AppStoreAgeRatingReading = UnavailableAppStoreAgeRating(),
                recordStore: any AgeRequestRecordStoring = InMemoryAgeRequestRecordStore(),
                versionStore: any SignificantChangeVersionStoring = InMemorySignificantChangeVersionStore(),
                clock: any DateProviding = SystemDateProvider(),
                paywallWaitClock: C = ContinuousClock(),
                currentAppVersion: String = AgeAssuranceModel.bundleShortVersion(),
                changeDescription: String = "") where C.Duration == Duration {
        self.requester = requester
        self.consent = consent
        self.ageRating = ageRating
        self.recordStore = recordStore
        self.versionStore = versionStore
        self.clock = clock
        self.currentAppVersion = currentAppVersion
        self.changeDescription = changeDescription
        sleepForPaywallWait = { try await paywallWaitClock.sleep(for: $0) }
        listenTask.replace(with: Task { [weak self] in await self?.listenForAnswers() })
    }

    public static func bundleShortVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    /// EB-01(b): the launch request point this app controls (`AppModel.apply(_:)`, once a launch
    /// resolves its route); `evaluateBeforePaywall()` below is the awaitable twin for the other
    /// two (first-sync and locked-feature paywall) request points — SEC2-14's "before a purchase"
    /// request must finish before the paywall sheet is presented, which this fire-and-forget form
    /// cannot guarantee. The 12-month floor is evaluated the same way, every time. Re-entrant: a
    /// call while an earlier one is still running supersedes it (the newer call has the same or
    /// newer `clock.now()`, so nothing is lost).
    public func evaluateIfDue(isFirstLaunchAfterInstall: Bool, isAboutToPresentPaywallPurchase: Bool) {
        evaluateTask.replace(with: Task { [weak self] in
            await self?.evaluate(isFirstLaunchAfterInstall: isFirstLaunchAfterInstall,
                                 isAboutToPresentPaywallPurchase: isAboutToPresentPaywallPurchase)
        })
    }

    /// SEC2-14: the same "before a paywall purchase" request as `evaluateIfDue(isFirstLaunchAfterInstall:
    /// false, isAboutToPresentPaywallPurchase: true)`, but awaitable, so `AppModel` can wait for
    /// it before presenting the paywall sheet instead of racing it — the system age sheet and the
    /// paywall sheet must never compete to present over the same window.
    ///
    /// **EB-01(g) extended to the wait itself: age assurance must never block the purchase flow,
    /// not even by hanging.** The real `DeclaredAgeRange` call was observed to never resolve in
    /// the iOS Simulator (CI run 40187586640: three `PaywallUITests` timed out once the paywall
    /// started awaiting it) — plausible on a slow or stuck device too. So this method:
    /// 1. First asks whether a request is even due (`AgeRequestPolicy.trigger`, via
    ///    `isPaywallRequestDue()`). If not — most calls, once this launch has already requested
    ///    once — it returns at once: no await on `requester`, and no await on `evaluateTask`
    ///    either, since whatever is already running there (possibly the launch-time call that IS
    ///    hanging) is irrelevant to this decision.
    /// 2. Otherwise it races the real request against `TallyConfig.ageAssurancePaywallWaitBudget`.
    ///    If the wait wins, this returns anyway and the request keeps running in `evaluateTask`
    ///    (cancelled only if a later call supersedes it): `outcome` and every store it would have
    ///    written still land whenever it eventually finishes. If it never finishes winning the
    ///    race just means the paywall was never blocked by it, same as before this method existed.
    public func evaluateBeforePaywall() async {
        guard await isPaywallRequestDue() else { return }
        // Two statements on purpose, not `await self?.evaluate(...)` alone: a single-expression
        // closure's implicit return would make this `Task<Void?, Never>` (from the `self?.`
        // optional chain), not the `Task<Void, Never>` `evaluateTask`/`run.value` below need.
        let run = Task { [weak self] in
            guard let self else { return }
            await self.evaluate(isFirstLaunchAfterInstall: false, isAboutToPresentPaywallPurchase: true)
        }
        evaluateTask.replace(with: run)
        let gate = PaywallWaitGate()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            gate.install(continuation)
            let timer = Task { [sleepForPaywallWait] in
                do { try await sleepForPaywallWait(TallyConfig.ageAssurancePaywallWaitBudget) } catch { return }
                gate.open()
            }
            Task {
                await run.value
                timer.cancel()
                gate.open()
            }
        }
    }

    /// SEC2-14: whether `evaluate(isFirstLaunchAfterInstall: false, isAboutToPresentPaywallPurchase:
    /// true)` would actually attempt a NEW request — i.e. whether `AgeRequestPolicy.trigger`
    /// returns non-nil for exactly that call shape — without ever touching `requester`. Reads
    /// only the same cheap, bounded stores `evaluate()` itself reads (never the hanging-prone
    /// system call), and when this launch has already requested once
    /// (`hasRequestedThisProcessLaunch`), not even those: `AgeRequestPolicy.trigger`'s very first
    /// guard rules it out regardless of anything else, so there is nothing to read.
    private func isPaywallRequestDue() async -> Bool {
        guard !hasRequestedThisProcessLaunch else { return false }
        let record = await recordStore.load()
        let versionState = await versionStore.load() ?? SignificantChangeVersionState()
        let ratingCode = await ageRating.currentAgeRatingCode()
        let ratingChanged = AgeRatingChangeDetector.didChange(current: ratingCode, lastKnown: versionState.lastKnownAgeRatingCode)
        let isSignificantChangeVersion = (TallyConfig.currentReleaseIsSignificantChange || ratingChanged)
            && versionState.lastAcknowledgedSignificantChangeVersion != currentAppVersion
        let input = AgeRequestPolicyInput(hasRequestedThisProcessLaunch: false, isFirstLaunchAfterInstall: false,
                                          isFirstLaunchOfSignificantChangeVersion: isSignificantChangeVersion,
                                          isAboutToPresentPaywallPurchase: true,
                                          lastRequestedAt: record?.lastRequestedAt, now: clock.now())
        return AgeRequestPolicy.trigger(for: input) != nil
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
        // AGE-2: this launch gets at most one attempt either way — `hasRequestedThisProcessLaunch`
        // is set before the call, whatever it returns, so an `.unavailable` result still cannot
        // retry within the SAME launch (only on the next one, below).
        hasRequestedThisProcessLaunch = true
        let result = await requester.requestAgeAssurance()
        outcome = result

        // AGE-2: the request record is saved only once `result` is known, still carrying the
        // date the request STARTED (`now`, captured above, before Apple answered) — it is a
        // request record, not a response record. `.unavailable` means the system sheet never
        // reached (or never resolved for) the person, so it must not count against the 12-month
        // floor: skipping the save here is cleaner than saving-then-clearing, since `outcome`
        // already carries the one signal (`.unavailable`) that distinguishes a real attempt from
        // a failed one — no second, separate "did it actually present" flag has to cross the
        // adapter boundary. The next launch then reads the same (possibly still-nil)
        // `lastRequestedAt` as before and retries, exactly like "never requested."
        if result != .unavailable {
            try? await recordStore.save(AgeRequestRecord(lastRequestedAt: now))
        }

        // SEC2-01/AGE-2: a significant-change version is acknowledged — and never asked about
        // again — only once nothing is left pending: either this outcome never required consent
        // at all, or consent came back `.granted`/`.notRequired`. A `.pending` question, a
        // `.denied` answer or a consent `.unavailable` attempt must ask again on the next launch,
        // so none of them may set `lastAcknowledgedSignificantChangeVersion` here — and neither
        // may an `.unavailable` AGE-ASSURANCE result (the residual from #85): a technical failure
        // never acknowledges the version, only a real decline or a real signal does. No age value
        // is persisted either way — this only ever writes the version string and the
        // rating-observation baseline already computed above.
        guard case .shared(let signal) = result, signal.significantChangeRequirement.isAny else {
            if trigger == .firstLaunchOfSignificantChangeVersion, result != .unavailable {
                versionState.lastAcknowledgedSignificantChangeVersion = currentAppVersion
            }
            try? await versionStore.save(versionState)
            return
        }

        consentOutcome = await consent.requestConsent(changeDescription: changeDescription,
                                                       for: signal.significantChangeRequirement)
        guard trigger == .firstLaunchOfSignificantChangeVersion else {
            try? await versionStore.save(versionState)
            return
        }
        switch consentOutcome {
        case .granted, .notRequired:
            versionState.lastAcknowledgedSignificantChangeVersion = currentAppVersion
            try? await versionStore.save(versionState)
        case .pending, .denied, .unavailable:
            try? await versionStore.save(versionState) // still records the rating observation
            unacknowledgedSignificantChangeVersion = currentAppVersion
        }
    }

    /// EB-02(b): a parent/guardian's answer can arrive long after `requestConsent` returned
    /// `.pending` (they may not open Messages right away). This stream runs for the process's
    /// whole lifetime so that answer still reaches `gateDecision`.
    ///
    /// SEC2-01: a `.granted` answer that finally resolves THIS launch's unacknowledged
    /// significant-change version finishes what `evaluate` deferred, so a later relaunch stops
    /// asking. Any other answer (including a late `.denied`) leaves it unacknowledged on purpose.
    private func listenForAnswers() async {
        for await answer in consent.pendingAnswers() {
            consentOutcome = answer
            guard answer == .granted, let version = unacknowledgedSignificantChangeVersion else { continue }
            unacknowledgedSignificantChangeVersion = nil
            var versionState = await versionStore.load() ?? SignificantChangeVersionState()
            versionState.lastAcknowledgedSignificantChangeVersion = version
            try? await versionStore.save(versionState)
        }
    }
}

/// SEC2-14: resumes `evaluateBeforePaywall()`'s one continuation the first time either side of
/// its race calls `open()`, as `HomeModel`'s identical `ResumeGate` does for
/// `refreshUntilSettledOrDelayed` (not reused directly: that one is file-private to
/// `HomeModel.swift`). A late second `open()` (the loser, finishing after the winner already
/// resumed) is a no-op, never a double-resume.
private nonisolated final class PaywallWaitGate: Sendable {
    private struct State {
        var continuation: CheckedContinuation<Void, Never>?
        var isOpen = false
    }

    private let state = Mutex(State())

    func install(_ continuation: CheckedContinuation<Void, Never>) {
        let resumeNow = state.withLock { state -> Bool in
            if state.isOpen { return true }
            state.continuation = continuation
            return false
        }
        if resumeNow { continuation.resume() }
    }

    func open() {
        let pending = state.withLock { state -> CheckedContinuation<Void, Never>? in
            if state.isOpen { return nil }
            state.isOpen = true
            let taken = state.continuation
            state.continuation = nil
            return taken
        }
        pending?.resume()
    }
}
