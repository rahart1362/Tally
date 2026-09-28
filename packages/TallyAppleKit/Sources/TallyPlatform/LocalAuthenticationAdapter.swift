import Foundation
import LocalAuthentication
import TallyDomain
import TallyFeatures

/// The `LAContext` operations the app lock uses (PL-03), behind a protocol so tests can drive every
/// `LAError` through a fake context. Evaluation is **async only** (plan 06 A3; CI's hygiene gate
/// fails on a callback-style `evaluatePolicy`/`evaluateAccessControl`): a reply closure formed in
/// main-actor code is main-actor isolated, and Swift 6's dynamic isolation check traps when
/// LocalAuthentication calls it on its own queue (SE-0423).
public protocol LocalAuthenticationContext: AnyObject {
    /// Populated once `canEvaluate` has run.
    var biometryType: LABiometryType { get }
    /// `canEvaluatePolicy(_:error:)`: whether `policy` can run now, and the `LAError` when not.
    func canEvaluate(_ policy: LAPolicy) -> (canEvaluate: Bool, error: (any Error)?)
    /// The async form of `LAContext.evaluatePolicy` (policy, localized reason). Never the reply-closure form.
    func evaluate(_ policy: LAPolicy, reason: String) async throws -> Bool
    /// The enrolled-biometry state (iOS 18's `LADomainState`, replacing the deprecated
    /// `evaluatedPolicyDomainState`). Changes when a face or finger is enrolled or removed.
    var biometryStateHash: Data? { get }
}

extension LAContext: LocalAuthenticationContext {
    public func canEvaluate(_ policy: LAPolicy) -> (canEvaluate: Bool, error: (any Error)?) {
        var error: NSError?
        let canEvaluate = canEvaluatePolicy(policy, error: &error)
        return (canEvaluate, error)
    }

    public func evaluate(_ policy: LAPolicy, reason: String) async throws -> Bool {
        try await evaluatePolicy(policy, localizedReason: reason)
    }

    public var biometryStateHash: Data? { domainState.biometry.stateHash }
}

/// SEC-07 (security.md WP-SEC-07, ADR 0001): `AppLockAuthenticating` over `LAContext` with
/// `LAPolicy.deviceOwnerAuthentication` (biometrics first, the device passcode as the fallback, so a
/// failed Face ID can never lock a student out or let anyone else in). A fresh context per attempt.
///
/// **Fails closed.** Only `evaluate` returning `true` is a success. Every `LAError` (and any other
/// error, and a `false` result) maps to a non-success `AppLockPolicy.AuthResult`, which
/// `AppLockPolicy` treats as "stay locked". The distinct cases only choose the lock view's wording:
/// `.passcodeNotSet` offers sign-out (security.md §3.3).
///
/// `.deviceOwnerAuthentication` does not report which credential succeeded. A success is reported
/// as `.biometric` whenever the device has biometry (the conservative reading); the app does not
/// arm `AppLockPolicy`'s passcode-only enrolment rule, which this API cannot satisfy (security.md
/// §3.3: domain-state checks "add nothing against T1 and are not required").
public final class LocalAuthenticationAdapter: AppLockAuthenticating, Sendable {
    private let makeContext: @Sendable () -> any LocalAuthenticationContext

    public init(makeContext: @escaping @Sendable () -> any LocalAuthenticationContext = { LAContext() }) {
        self.makeContext = makeContext
    }

    @concurrent
    public func authenticate(reason: String) async -> AppLockPolicy.AuthResult {
        let context = makeContext()
        let check = context.canEvaluate(.deviceOwnerAuthentication)
        guard check.canEvaluate else { return Self.result(for: check.error) }
        do {
            let succeeded = try await context.evaluate(.deviceOwnerAuthentication, reason: reason)
            return succeeded ? .success(via: Self.method(for: context.biometryType)) : .failedOrCancelled
        } catch {
            return Self.result(for: error)
        }
    }

    @concurrent
    public func evaluatedPolicyDomainState() async -> Data? {
        let context = makeContext()
        guard context.canEvaluate(.deviceOwnerAuthentication).canEvaluate else { return nil }
        return context.biometryStateHash
    }

    @concurrent
    public func availability() async -> AppLockAvailability {
        let context = makeContext()
        let check = context.canEvaluate(.deviceOwnerAuthentication)
        if check.canEvaluate { return .available(Self.biometry(context.biometryType)) }
        return Self.result(for: check.error) == .passcodeNotSet ? .passcodeNotSet : .unavailable
    }

    /// Every failure keeps the app locked; this only picks which non-success it is.
    static func result(for error: (any Error)?) -> AppLockPolicy.AuthResult {
        guard let error = error.map({ $0 as NSError }), error.domain == LAErrorDomain else { return .failedOrCancelled }
        switch LAError.Code(rawValue: error.code) {
        case .passcodeNotSet?: return .passcodeNotSet
        case .biometryLockout?: return .biometryLockout
        case .biometryNotAvailable?, .biometryNotEnrolled?: return .biometryUnavailable
        default: return .failedOrCancelled
        }
    }

    static func method(for type: LABiometryType) -> AppLockPolicy.AuthMethod {
        biometry(type) == .noBiometry ? .passcode : .biometric
    }

    static func biometry(_ type: LABiometryType) -> AppLockBiometry {
        switch type {
        case .faceID: .faceID
        case .touchID: .touchID
        case .opticID: .opticID
        case .none: .noBiometry
        @unknown default: .noBiometry
        }
    }
}
