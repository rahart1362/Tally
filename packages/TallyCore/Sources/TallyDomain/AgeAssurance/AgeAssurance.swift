import Foundation

/// AGE-1 (engineering-backlog-us.md §2 EB-01–EB-04; matrix.md §2 duty table). Every type here is
/// pure: no I/O, no Apple framework, no persistence. The real `DeclaredAgeRange`/`PermissionKit`
/// calls live in `TallyPlatform` (`DeclaredAgeRangeAdapter`, `SignificantChangeConsentAdapter`),
/// behind the ports `TallyFeatures` declares (`AgeAssuranceRequesting`, `SignificantChangeConsenting`);
/// this file is what their results feed, and what every test in `AgeAssuranceTests.swift` drives
/// with injected values (EB-01(h): "decision logic as pure functions with injected results").
///
/// **Binding invariant (dossier §2, Tex. §121.055, Ala. HB161 §9(a)(3)/(c)(3), Cal. Civ. 1798.501):
/// the age range or category is NEVER persisted, logged, sent or shared.** Every type below that
/// carries an age signal (`AgeCategory`, `AgeAssuranceSignal`, `AgeAssuranceOutcome`) is plain,
/// in-memory `Sendable` state; nothing in this file is `Codable`, and `AgeAssuranceModel`
/// (TallyFeatures) never writes one to disk. The one persisted type in this whole feature is
/// `AgeRequestRecord` (TallyStore), which carries only a `Date` — no age value at all.

// MARK: - EB-01(b)/(c): the age-range signal itself

/// TX/UT/AL/LA's four age categories (matrix.md §2 duty table: "child (<13), younger teenager
/// (13-15), older teenager (16-17), adult"), derived from a `requestAgeRange(ageGates: 13, 16, 18)`
/// response's `lowerBound` the way Apple's own DeclaredAgeRange guide computes it ("Requesting
/// people's age range information in your app"): `lowerBound == nil` means under the lowest gate.
public enum AgeCategory: Sendable, Equatable, CaseIterable {
    case child
    case youngerTeen
    case olderTeen
    case adult
    /// Apple returned a range this app's gates cannot place (for example a `nil` `lowerBound` at
    /// a gate other than 13, or a future SDK shape `DeclaredAgeRangeAdapter` cannot parse).
    /// EB-01(g): treated exactly like a decline — never blocks, never changes a feature.
    case unknown

    /// `ageGates: 13, 16, 18` is EB-01's fixed gate set (the four matrix categories); `lowerBound`
    /// is `AgeRangeService.AgeRange.lowerBound` from a `.sharing` response.
    public static func fromLowerBound(_ lowerBound: Int?) -> AgeCategory {
        guard let lowerBound else { return .child }
        switch lowerBound {
        case ..<13: return .child
        case 13..<16: return .youngerTeen
        case 16..<18: return .olderTeen
        default: return .adult
        }
    }

    /// EB-01(f)/(e): every non-adult category gets the same treatment (no special-casing under
    /// 13 beyond the shared consent gate — "no feature change" for under-13, Q7).
    public var isMinor: Bool { self == .child || self == .youngerTeen || self == .olderTeen }
}

/// EB-02: which significant-change duties apply to the person in front of the device right now,
/// from `AgeRangeService.RegulatoryFeature` (the current SDK, iOS 26.4+). The backlog's assumption
/// — Apple's now-deprecated `AgeRangeService.ParentalControls.significantAppChangeApprovalRequired`
/// — is superseded; `DeclaredAgeRangeAdapter` records the deviation and falls back to it only on
/// iOS 26.0–26.3, where `requiredRegulatoryFeatures` does not exist.
public struct SignificantChangeRequirement: Sendable, Equatable {
    /// `.significantAppChangeRequiresParentalConsent`: a parent/guardian must consent through
    /// PermissionKit before this minor may continue (EB-02(b)).
    public var parentalConsentRequired: Bool
    /// `.significantAppChangeRequiresAdultNotification`: a verified adult must acknowledge the
    /// change (DeclaredAgeRange's own `showSignificantUpdateAcknowledgment`), not PermissionKit.
    public var adultNotificationRequired: Bool

    public init(parentalConsentRequired: Bool = false, adultNotificationRequired: Bool = false) {
        self.parentalConsentRequired = parentalConsentRequired
        self.adultNotificationRequired = adultNotificationRequired
    }

    public static let none = SignificantChangeRequirement()
    public var isAny: Bool { parentalConsentRequired || adultNotificationRequired }
}

/// EB-01(c): the in-memory-only result of one successful `requestAgeRange` call.
/// `AgeAssuranceModel` (TallyFeatures) holds this for the process's lifetime and never longer, and
/// never persists it.
public struct AgeAssuranceSignal: Sendable, Equatable {
    public var category: AgeCategory
    public var significantChangeRequirement: SignificantChangeRequirement

    public init(category: AgeCategory, significantChangeRequirement: SignificantChangeRequirement = .none) {
        self.category = category
        self.significantChangeRequirement = significantChangeRequirement
    }
}

/// What one `requestAgeAssurance()` call told this launch.
public enum AgeAssuranceOutcome: Sendable, Equatable {
    /// `AgeRangeService.isEligibleForAgeFeatures == false`: EB-01(b), "Request only where Apple
    /// reports that regulatory requirements apply" — the request UI was never shown.
    case regulatoryRequirementsDoNotApply
    /// `Response.declinedSharing`, a thrown `AgeRangeService.Error`, or no window to present from
    /// (the Simulator — DeclaredAgeRange has no effect there). EB-01(g): never blocks.
    case declinedOrUnavailable
    case shared(AgeAssuranceSignal)
}

// MARK: - EB-02(b)/EB-01(e): the significant-change / parental-consent gate

/// A parent/guardian's answer to a `SignificantAppUpdateTopic` permission question
/// (`PermissionChoice.Answer`, PermissionKit), or a verified adult's own acknowledgment
/// (`showSignificantUpdateAcknowledgment`).
public enum SignificantChangeConsentOutcome: Sendable, Equatable {
    /// Nothing to ask (an adult with no notification duty, or a category this gate does not
    /// restrict).
    case notRequired
    /// The parent approved, or the adult acknowledged.
    case granted
    /// Asked; no answer yet. `AgeGate` restricts until a later answer arrives
    /// (`SignificantChangeConsenting.pendingAnswers()`).
    case pending
    case denied
    /// The API threw, or there was no window to present from.
    case unavailable
}

public enum AgeGateDecision: Sendable, Equatable {
    case allow
    case restrictedPendingConsent
}

public enum AgeGate {
    /// EB-01(e)/EB-02(b)/(f)/(g), matrix.md §2 "no enforcement of terms vs. unconsented minor":
    /// the one place that decides whether to show the neutral restricted screen and hide data.
    ///
    /// `.notRequired`/`.granted`/`.unavailable` all allow. `.unavailable` allowing, specifically,
    /// is EB-01(g) read together with the backlog's non-goal ("no Tally server, no App Store
    /// Server Notifications endpoint"): Apple's only way to tell Tally a parent said no is
    /// PermissionKit's live response (this process only) or a server notification Tally does not
    /// receive. An app that failed closed whenever that live call could not be made — the
    /// Simulator, a flaky connection, an OS below 26.2 — would block far more often than real
    /// denials occur, which is a worse outcome than the gap it closes; Apple's own launch-block
    /// (device-verified, EB-04) is the backstop for an actual revocation. Only an explicit
    /// `.denied`, or a `.pending` question nothing has answered yet, restricts.
    public static func decision(for consent: SignificantChangeConsentOutcome) -> AgeGateDecision {
        switch consent {
        case .notRequired, .granted, .unavailable: .allow
        case .pending, .denied: .restrictedPendingConsent
        }
    }
}

// MARK: - EB-01(b): when to request

/// Why `AgeRequestPolicy.trigger(for:)` says to request now (matrix.md §2 duty table: "Request age
/// signal at download/first launch", "Request at purchase", "Request at significant change",
/// "Routine re-request limit").
public enum AgeRequestTrigger: Sendable, Equatable {
    case firstLaunchAfterInstall
    case firstLaunchOfSignificantChangeVersion
    case beforePaywallPurchase
    case routineReRequest
}

public struct AgeRequestPolicyInput: Sendable, Equatable {
    public var hasRequestedThisProcessLaunch: Bool
    public var isFirstLaunchAfterInstall: Bool
    public var isFirstLaunchOfSignificantChangeVersion: Bool
    public var isAboutToPresentPaywallPurchase: Bool
    public var lastRequestedAt: Date?
    public var now: Date

    public init(hasRequestedThisProcessLaunch: Bool, isFirstLaunchAfterInstall: Bool,
                isFirstLaunchOfSignificantChangeVersion: Bool, isAboutToPresentPaywallPurchase: Bool,
                lastRequestedAt: Date?, now: Date) {
        self.hasRequestedThisProcessLaunch = hasRequestedThisProcessLaunch
        self.isFirstLaunchAfterInstall = isFirstLaunchAfterInstall
        self.isFirstLaunchOfSignificantChangeVersion = isFirstLaunchOfSignificantChangeVersion
        self.isAboutToPresentPaywallPurchase = isAboutToPresentPaywallPurchase
        self.lastRequestedAt = lastRequestedAt
        self.now = now
    }
}

public enum AgeRequestPolicy {
    /// EB-01(b): "first launch after install; the first launch of a significant-change version;
    /// before a paywall purchase if not requested this launch; at most one routine re-request per
    /// 12 months." Checked in exactly that order — the first three are one-time-per-launch events
    /// that always take priority over the 12-month floor underneath them. `nil` means "don't ask."
    public static func trigger(for input: AgeRequestPolicyInput) -> AgeRequestTrigger? {
        guard !input.hasRequestedThisProcessLaunch else { return nil }
        if input.isFirstLaunchAfterInstall { return .firstLaunchAfterInstall }
        if input.isFirstLaunchOfSignificantChangeVersion { return .firstLaunchOfSignificantChangeVersion }
        if input.isAboutToPresentPaywallPurchase { return .beforePaywallPurchase }
        if isRoutineReRequestDue(lastRequestedAt: input.lastRequestedAt, now: input.now) { return .routineReRequest }
        return nil
    }

    /// Utah 13-76-202, Alabama HB161 §9(b)(1): "at most one routine re-check/re-request per 12
    /// months." Never requested yet (`lastRequestedAt == nil`) is not "routine" — one of the three
    /// other triggers covers a brand-new device/account.
    public static func isRoutineReRequestDue(lastRequestedAt: Date?, now: Date,
                                              months: Int = TallyConfig.ageRequestRoutineReRequestMonths) -> Bool {
        guard let lastRequestedAt else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        guard let next = calendar.date(byAdding: .month, value: months, to: lastRequestedAt) else { return false }
        return now >= next
    }
}

// MARK: - EB-03: the StoreKit age-rating signal

/// EB-03: "StoreKit age-rating property at launch; a change runs EB-02(b)." Pure comparison; the
/// caller (`AgeAssuranceModel`) persists the new code via `SignificantChangeVersionState` and, on
/// a change, treats this launch as significant (feeds
/// `AgeRequestPolicyInput.isFirstLaunchOfSignificantChangeVersion`).
public enum AgeRatingChangeDetector {
    /// `current`/`lastKnown` are `AppStore.ageRatingCode` values (the APP's rating, never a
    /// person's age — safe to persist). `nil` current (the property is unavailable) is never a
    /// change; no prior observation (`lastKnown == nil`) is the first read, not a change either.
    public static func didChange(current: Int?, lastKnown: Int?) -> Bool {
        guard let current, let lastKnown else { return false }
        return current != lastKnown
    }
}
