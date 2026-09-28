import Foundation

/// The device-authentication port `AppLockPolicy` drives (security.md §3.3, ADR 0001):
/// biometrics first, device passcode as fallback (`LAPolicy.deviceOwnerAuthentication`).
/// `TallyDomain` stays Foundation-only, so the vocabulary below is what an `LAContext`
/// adapter maps `LAError`/`LABiometryType`/`evaluatedPolicyDomainState` onto; the adapter
/// itself is a later, iOS-only work package (WP-SEC-07).
public protocol DeviceAuthenticating: Sendable {
    /// One `.deviceOwnerAuthentication` attempt.
    func authenticate(reason: String) async -> AppLockPolicy.AuthResult
    /// `LAContext.evaluatedPolicyDomainState`: changes whenever the enrolled biometry
    /// changes (a face/fingerprint added or removed). `nil` when nothing is enrolled or
    /// the device has no passcode.
    func evaluatedPolicyDomainState() async -> Data?
}

/// Pure app-lock state machine (security.md WP-SEC-07; ADR 0001 "App lock").
///
/// Replaces the old `BiometricAuthManager`/`AppRootView` pair, which had three bypasses
/// this type is built to close and regression-test (`AppLockPolicyTests`):
/// 1. **Biometrics unavailable** — `canEvaluatePolicy` failing (no enrolment, or the
///    device has no passcode) set `isLocked = false` and returned `true` from
///    `authenticate()`, unlocking the app with no check at all.
/// 2. **Lockout** — `biometryLockout` (too many failed attempts) fails
///    `canEvaluatePolicy` exactly like case 1, so five deliberate Face ID failures also
///    unlocked the app.
/// 3. **Cold launch unlocked** — `isLocked` started `false` and was only set on
///    `.background`, so relaunching the app (or force-quitting it) skipped the lock
///    entirely.
///
/// The fix is structural, not a patched condition: `AuthResult` has exactly one case that
/// can ever move `state` to `.unlocked` (`.success`), every other case is a no-op that
/// leaves `state` exactly as it was, and the initializer starts `.locked` whenever the
/// setting is on — there is no path from "evaluation didn't run" to "unlocked".
public struct AppLockPolicy: Sendable, Equatable {
    /// Mirrors `ScenePhase` without importing SwiftUI (TallyDomain is Foundation-only).
    public enum Phase: Sendable, Equatable { case active, inactive, background }

    /// The re-lock grace period after backgrounding (ADR 0001; default `.oneMinute`).
    public enum GracePeriod: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
        case immediately, oneMinute, fiveMinutes, fifteenMinutes

        public var duration: Duration {
            switch self {
            case .immediately: TallyConfig.appLockGraceImmediately
            case .oneMinute: TallyConfig.appLockGraceOneMinute
            case .fiveMinutes: TallyConfig.appLockGraceFiveMinutes
            case .fifteenMinutes: TallyConfig.appLockGraceFifteenMinutes
            }
        }

        public static let `default`: GracePeriod = .oneMinute
    }

    public enum State: Sendable, Equatable { case locked, unlocked }

    /// Which credential an authentication must have used. Set to `.passcodeOnly` the
    /// moment a biometric-enrolment change is observed, so a freshly enrolled (possibly
    /// attacker-added) face or fingerprint cannot itself satisfy the very re-auth it
    /// triggered — only the device passcode can. Cleared on the next accepted result.
    public enum RequiredCredential: Sendable, Equatable { case biometricsOrPasscode, passcodeOnly }

    public enum AuthMethod: Sendable, Equatable { case biometric, passcode }

    /// What one `DeviceAuthenticating.authenticate(reason:)` call resolved to. Every case
    /// other than `.success` is a distinct `LAError` (or "policy can't even be evaluated")
    /// the adapter maps onto — deliberately not a single catch-all `.failure`, so a caller
    /// can show the right message (security.md §3.3's "Set a device passcode, or Sign out"
    /// for `.passcodeNotSet`), while the state machine still treats every one of them as
    /// "stay locked".
    public enum AuthResult: Sendable, Equatable {
        case success(via: AuthMethod)
        case failedOrCancelled
        case biometryUnavailable
        case biometryLockout
        case passcodeNotSet
    }

    /// What an authentication attempt is for. Both require the same `RequiredCredential`
    /// gate; only `.unlock` and `.disableLock` differ in what a `.success` then does.
    public enum Purpose: Sendable, Equatable { case unlock, disableLock }

    public private(set) var isEnabled: Bool
    public private(set) var gracePeriod: GracePeriod
    public private(set) var state: State
    public private(set) var phase: Phase = .active
    public private(set) var requiredCredential: RequiredCredential = .biometricsOrPasscode
    /// Last-seen `evaluatedPolicyDomainState`, opaque (never inspected, only compared).
    public private(set) var enrollmentToken: Data?
    private var backgroundedAt: Date?

    /// Cold launch (ADR 0001 "Locks at cold launch"): a caller reconstructs this fresh
    /// from persisted settings every process start, and `state` starts `.locked` whenever
    /// `isEnabled` is true — never `.unlocked`, regardless of how the app was last left.
    public init(isEnabled: Bool, gracePeriod: GracePeriod = .default, enrollmentToken: Data? = nil) {
        self.isEnabled = isEnabled
        self.gracePeriod = gracePeriod
        self.enrollmentToken = enrollmentToken
        state = isEnabled ? .locked : .unlocked
    }

    /// A neutral cover (ADR 0001 step 1) belongs on screen whenever the lock is enabled
    /// and the app isn't frontmost — independent of `state`, so it also hides an already
    /// -`unlocked` app's content from the app-switcher snapshot (security.md §3.3's "App
    /// -switcher snapshot" row, which the old code never covered at all).
    public var showsPrivacyCover: Bool { isEnabled && phase != .active }

    /// Turning the lock **on** needs no re-authentication (the student is already using
    /// an unlocked app to reach the toggle); only turning it **off** does — see
    /// `authenticationCompleted(_:for:.disableLock)`.
    public mutating func enable(now: Date) {
        isEnabled = true
        backgroundedAt = nil
    }

    /// `ScenePhase` transitions (ADR 0001 "Locks... after being in the background longer
    /// than the grace period"; ADR 0001 does not start the grace-period timer on
    /// `.inactive` alone, only on an actual `.background` sojourn).
    public mutating func scenePhaseChanged(to newPhase: Phase, now: Date) {
        defer { phase = newPhase }
        guard isEnabled else { return }
        if newPhase == .background {
            backgroundedAt = now
            return
        }
        guard phase == .background, let backgroundedAt else { return }
        defer { self.backgroundedAt = nil }
        if now.timeIntervalSince(backgroundedAt) >= gracePeriod.duration.timeInterval {
            state = .locked
        }
    }

    /// `LAContext.evaluatedPolicyDomainState` observed on this launch (or after a
    /// biometry-settings round trip). A change from a previously *known* value — enrolling,
    /// removing or replacing a face/fingerprint — forces a re-lock and demotes the next
    /// accepted authentication to passcode-only (security.md §3.3 "Biometric policy").
    /// The very first observation (no prior token) only records the baseline.
    public mutating func observedEnrollmentToken(_ token: Data?, now: Date) {
        defer { enrollmentToken = token }
        guard let previous = enrollmentToken, previous != token else { return }
        state = .locked
        requiredCredential = .passcodeOnly
    }

    /// Applies one `DeviceAuthenticating` result. Returns whether it actually changed
    /// `state`/`isEnabled` — every non-`.success` result, and a `.success` that used
    /// biometrics while `.passcodeOnly` is required, changes nothing and returns `false`;
    /// `state` (and `isEnabled`, for `.disableLock`) are left exactly as they already were.
    @discardableResult
    public mutating func authenticationCompleted(_ result: AuthResult, for purpose: Purpose) -> Bool {
        guard case .success(let method) = result else { return false }
        guard requiredCredential == .biometricsOrPasscode || method == .passcode else { return false }
        switch purpose {
        case .unlock: state = .unlocked
        case .disableLock: isEnabled = false; state = .unlocked
        }
        requiredCredential = .biometricsOrPasscode
        return true
    }

    public mutating func setGracePeriod(_ period: GracePeriod) { gracePeriod = period }
}
