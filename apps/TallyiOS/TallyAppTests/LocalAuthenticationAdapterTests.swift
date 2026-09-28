import Foundation
import LocalAuthentication
import Synchronization
import Testing
import TallyDomain
import TallyFeatures
@testable import TallyPlatform

/// SEC-07 / PL-03 (security.md WP-SEC-07; plan 07 M2-C1 L-4): the `LAContext` adapter over a fake
/// context. Every `LAError` code, from `canEvaluatePolicy` and from the evaluation itself, and any
/// other error or a `false` result, must leave the app locked; only a real success unlocks. The
/// policy is always `.deviceOwnerAuthentication`, and evaluation goes through the async API.
@Suite("LocalAuthenticationAdapter: every LAError keeps the app locked")
struct LocalAuthenticationAdapterTests {
    /// Every `LAError.Code` raw value in the iOS 26 SDK (LAError.h), including the macOS-only and
    /// deprecated ones, plus one that no SDK defines: an unknown code must also fail closed.
    static let allLAErrorCodes: [Int] = [
        -1,    // authenticationFailed
        -2,    // userCancel
        -3,    // userFallback
        -4,    // systemCancel
        -5,    // passcodeNotSet
        -6,    // biometryNotAvailable (touchIDNotAvailable)
        -7,    // biometryNotEnrolled (touchIDNotEnrolled)
        -8,    // biometryLockout (touchIDLockout)
        -9,    // appCancel
        -10,   // invalidContext
        -11,   // companionNotAvailable (watchNotAvailable)
        -12,   // biometryNotPaired
        -13,   // biometryDisconnected
        -14,   // invalidDimensions
        -1004, // notInteractive
        -9999, // not defined by any SDK
    ]

    private static func laError(_ code: Int) -> NSError {
        NSError(domain: LAErrorDomain, code: code)
    }

    private static func expectedResult(_ code: Int) -> AppLockPolicy.AuthResult {
        switch code {
        case -5: .passcodeNotSet
        case -8: .biometryLockout
        case -6, -7: .biometryUnavailable
        default: .failedOrCancelled
        }
    }

    /// Feeds `result` to a locked policy: it must stay locked.
    private func staysLocked(_ result: AppLockPolicy.AuthResult) -> Bool {
        var policy = AppLockPolicy(isEnabled: true)
        policy.authenticationCompleted(result, for: .unlock)
        return policy.state == .locked
    }

    @Test("an LAError from the evaluation keeps the app locked", arguments: LocalAuthenticationAdapterTests.allLAErrorCodes)
    func evaluationErrorsStayLocked(_ code: Int) async {
        let context = FakeLAContext(evaluation: .failure(Self.laError(code)))
        let result = await LocalAuthenticationAdapter(makeContext: { context }).authenticate(reason: "test")
        #expect(result == Self.expectedResult(code))
        #expect(staysLocked(result), "LAError \(code) unlocked the app")
        #expect(context.evaluatedPolicies == [.deviceOwnerAuthentication])
    }

    @Test("an LAError from canEvaluatePolicy keeps the app locked and never evaluates", arguments: LocalAuthenticationAdapterTests.allLAErrorCodes)
    func canEvaluateErrorsStayLocked(_ code: Int) async {
        let context = FakeLAContext(canEvaluateError: Self.laError(code), evaluation: .success(true))
        let result = await LocalAuthenticationAdapter(makeContext: { context }).authenticate(reason: "test")
        #expect(result == Self.expectedResult(code))
        #expect(staysLocked(result), "LAError \(code) from canEvaluatePolicy unlocked the app")
        #expect(context.evaluatedPolicies.isEmpty, "evaluated a policy that cannot be evaluated")
        #expect(context.checkedPolicies == [.deviceOwnerAuthentication])
    }

    @Test("a non-LocalAuthentication error, a false result, and canEvaluatePolicy false with no error all stay locked")
    func otherFailuresStayLocked() async {
        let other = FakeLAContext(evaluation: .failure(CancellationError()))
        let falseResult = FakeLAContext(evaluation: .success(false))
        let silent = FakeLAContext(canEvaluate: false, evaluation: .success(true))
        for context in [other, falseResult, silent] {
            let result = await LocalAuthenticationAdapter(makeContext: { context }).authenticate(reason: "test")
            #expect(result == .failedOrCancelled)
            #expect(staysLocked(result))
        }
    }

    @Test("only a successful evaluation unlocks; it reports biometry when the device has it")
    func successUnlocks() async {
        for (type, method) in [(LABiometryType.faceID, AppLockPolicy.AuthMethod.biometric), (.touchID, .biometric),
                               (.opticID, .biometric), (.none, .passcode)] {
            let context = FakeLAContext(biometryType: type, evaluation: .success(true))
            let result = await LocalAuthenticationAdapter(makeContext: { context }).authenticate(reason: "test")
            #expect(result == .success(via: method))
            var policy = AppLockPolicy(isEnabled: true)
            let changed = policy.authenticationCompleted(result, for: .unlock)
            #expect(changed)
            #expect(policy.state == .unlocked)
        }
    }

    @Test("availability: the biometry kind, passcode not set, or unavailable")
    func availability() async {
        let faceID = FakeLAContext(biometryType: .faceID, evaluation: .success(true))
        #expect(await LocalAuthenticationAdapter(makeContext: { faceID }).availability() == .available(.faceID))
        let noPasscode = FakeLAContext(canEvaluateError: Self.laError(-5), evaluation: .success(true))
        #expect(await LocalAuthenticationAdapter(makeContext: { noPasscode }).availability() == .passcodeNotSet)
        let lockout = FakeLAContext(canEvaluateError: Self.laError(-8), evaluation: .success(true))
        #expect(await LocalAuthenticationAdapter(makeContext: { lockout }).availability() == .unavailable)
    }

    @Test("each attempt gets a fresh context")
    func freshContextPerAttempt() async {
        let made = Mutex(0)
        let adapter = LocalAuthenticationAdapter(makeContext: {
            made.withLock { $0 += 1 }
            return FakeLAContext(evaluation: .success(true))
        })
        _ = await adapter.authenticate(reason: "one")
        _ = await adapter.authenticate(reason: "two")
        #expect(made.withLock { $0 } == 2)
    }
}

/// A scripted `LocalAuthenticationContext`: what `canEvaluate` answers, what `evaluate` does, and
/// which policies were checked and evaluated.
final class FakeLAContext: LocalAuthenticationContext, @unchecked Sendable {
    // @unchecked: every mutable field is behind `state`; the rest are immutable.
    private let canEvaluateResult: Bool
    private let canEvaluateError: NSError?
    private let evaluation: Result<Bool, any Error>
    private let type: LABiometryType
    private let state = Mutex<(checked: [LAPolicy], evaluated: [LAPolicy])>(([], []))

    init(canEvaluate: Bool = true, canEvaluateError: NSError? = nil, biometryType: LABiometryType = .faceID,
         evaluation: Result<Bool, any Error>) {
        canEvaluateResult = canEvaluateError == nil ? canEvaluate : false
        self.canEvaluateError = canEvaluateError
        self.evaluation = evaluation
        type = biometryType
    }

    var checkedPolicies: [LAPolicy] { state.withLock { $0.checked } }
    var evaluatedPolicies: [LAPolicy] { state.withLock { $0.evaluated } }

    var biometryType: LABiometryType { type }
    var biometryStateHash: Data? { nil }

    func canEvaluate(_ policy: LAPolicy) -> (canEvaluate: Bool, error: (any Error)?) {
        state.withLock { $0.checked.append(policy) }
        return (canEvaluateResult, canEvaluateError)
    }

    func evaluate(_ policy: LAPolicy, reason: String) async throws -> Bool {
        state.withLock { $0.evaluated.append(policy) }
        return try evaluation.get()
    }
}
