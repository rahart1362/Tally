import Foundation
import Synchronization
import TallyDomain
import TallyStore

/// AGE-1: the Apple-framework ports, as `WebAuthPresenting`/`AppLockAuthenticating` declare theirs
/// — `TallyFeatures` names what it needs; `TallyPlatform` conforms over the real
/// `DeclaredAgeRange`/`PermissionKit`/`StoreKit` calls (architecture.md §3.1: "Features never
/// import TallyPlatform" says nothing against the reverse, and `TallyPlatform` already imports
/// `TallyFeatures`).

/// EB-01(b)/(c): one `requestAgeRange` round trip, with the `isEligibleForAgeFeatures` gate
/// already applied. Never persists anything — that is `AgeAssuranceModel`'s job, and the one
/// thing it is allowed to persist is a date (`AgeRequestRecord`).
public protocol AgeAssuranceRequesting: Sendable {
    func requestAgeAssurance() async -> AgeAssuranceOutcome
}

/// The default when no adapter is injected (tests, previews, a process with no window to present
/// from): EB-01(g), "unavailable" never blocks and never asks.
public struct UnavailableAgeAssurance: AgeAssuranceRequesting {
    public init() {}
    public func requestAgeAssurance() async -> AgeAssuranceOutcome { .unavailable }
}

/// EB-02(b)/EB-01(e): PermissionKit's `SignificantAppUpdateTopic` for an affected minor, or
/// DeclaredAgeRange's own acknowledgment sheet for a verified adult who only needs to be notified
/// (`requirement.adultNotificationRequired`, never routed through PermissionKit).
public protocol SignificantChangeConsenting: Sendable {
    /// Presents the appropriate system UI for `requirement` and returns promptly: `.granted` only
    /// when an answer already exists (the adult's own acknowledgment, or — on the SDK's
    /// synchronous "ask in person" path — an immediate parental approval). `.pending` means a
    /// question was sent to a parent/guardian; its eventual answer arrives through
    /// `pendingAnswers()`, matched by the topic alone (one outstanding question at a time; this
    /// app asks one thing: continued access).
    func requestConsent(changeDescription: String, for requirement: SignificantChangeRequirement) async -> SignificantChangeConsentOutcome

    /// A long-lived stream of parental answers for questions this process already sent
    /// (PermissionKit's `AskCenter.shared.responses(for: SignificantAppUpdateTopic.self)`).
    /// Process-lifetime only, like every other signal in this feature — nothing here is persisted.
    func pendingAnswers() -> AsyncStream<SignificantChangeConsentOutcome>
}

public struct UnavailableSignificantChangeConsent: SignificantChangeConsenting {
    public init() {}
    public func requestConsent(changeDescription: String, for requirement: SignificantChangeRequirement) async -> SignificantChangeConsentOutcome {
        requirement.isAny ? .unavailable : .notRequired
    }
    public func pendingAnswers() -> AsyncStream<SignificantChangeConsentOutcome> {
        AsyncStream { $0.finish() }
    }
}

/// EB-03: `AppStore.ageRatingCode` at launch.
public protocol AppStoreAgeRatingReading: Sendable {
    func currentAgeRatingCode() async -> Int?
}

public struct UnavailableAppStoreAgeRating: AppStoreAgeRatingReading {
    public init() {}
    public func currentAgeRatingCode() async -> Int? { nil }
}

/// EB-01(c)'s one persisted field, behind a port the way `AppLockPreferenceStoring` wraps the
/// Keychain: `AgeAssuranceModel` never touches a file directly, so a test can inject an in-memory
/// store and never reach disk.
public protocol AgeRequestRecordStoring: Sendable {
    func load() async -> AgeRequestRecord?
    func save(_ record: AgeRequestRecord) async throws
}

/// The default when no store is injected (tests, previews): nothing persisted, so every launch
/// reads as "never requested" — safe (the policy then tries `.firstLaunchAfterInstall`, never a
/// silent skip).
public final class InMemoryAgeRequestRecordStore: AgeRequestRecordStoring, Sendable {
    private let stored = Mutex<AgeRequestRecord?>(nil)
    public init(_ record: AgeRequestRecord? = nil) { stored.withLock { $0 = record } }
    public func load() async -> AgeRequestRecord? { stored.withLock { $0 } }
    public func save(_ record: AgeRequestRecord) async throws { stored.withLock { $0 = record } }
}

/// EB-02/EB-03's non-age tracking (which version's significant-change flow this device has already
/// seen, and the last known StoreKit age-rating code).
public protocol SignificantChangeVersionStoring: Sendable {
    func load() async -> SignificantChangeVersionState?
    func save(_ state: SignificantChangeVersionState) async throws
}

public final class InMemorySignificantChangeVersionStore: SignificantChangeVersionStoring, Sendable {
    private let stored = Mutex<SignificantChangeVersionState?>(nil)
    public init(_ state: SignificantChangeVersionState? = nil) { stored.withLock { $0 = state } }
    public func load() async -> SignificantChangeVersionState? { stored.withLock { $0 } }
    public func save(_ state: SignificantChangeVersionState) async throws { stored.withLock { $0 = state } }
}
