import Foundation
import Synchronization
import TallyDomain

/// The stored app-lock setting (ADR 0001 "App lock"; security.md WP-SEC-07). The composition root
/// persists it in the Keychain (`KeychainAppLockPreferenceStore`, `TallyPlatform`), never in
/// `UserDefaults`: "The preference lives in the Keychain" (ADR 0001), so it cannot be edited or
/// restored from a backup (security.md §3.3, the "Lock flag edited or restored from backup" row).
public nonisolated struct AppLockPreference: Codable, Sendable, Equatable {
    public var isEnabled: Bool
    public var gracePeriod: AppLockPolicy.GracePeriod

    public init(isEnabled: Bool, gracePeriod: AppLockPolicy.GracePeriod = .default) {
        self.isEnabled = isEnabled
        self.gracePeriod = gracePeriod
    }

    public static let disabled = AppLockPreference(isEnabled: false)
}

/// One read of the stored setting.
public nonisolated enum AppLockPreferenceRead: Sendable, Equatable {
    case found(AppLockPreference)
    /// Never set (or reset by sign-out or a fresh install): the lock is off.
    case notFound
    /// The Keychain could not be read (before first unlock, or an error).
    case unavailable

    /// What a launch acts on. An unreadable setting **fails closed**: the app locks, because it
    /// cannot tell whether the student turned the lock on (security.md §3.3: "fail closed").
    public var effective: AppLockPreference {
        switch self {
        case .found(let preference): preference
        case .notFound: .disabled
        case .unavailable: AppLockPreference(isEnabled: true)
        }
    }
}

public nonisolated protocol AppLockPreferenceStoring: Sendable {
    func load() async -> AppLockPreferenceRead
    func save(_ preference: AppLockPreference) async throws
    /// Removes the setting (sign-out and erase; a fresh install's first launch).
    func reset() async
}

/// Which biometry the device offers, for the lock view's button label.
public nonisolated enum AppLockBiometry: Sendable, Equatable {
    /// No biometry enrolled or available: the device passcode is the credential.
    case noBiometry
    case touchID, faceID, opticID
}

/// Whether `.deviceOwnerAuthentication` can be evaluated right now.
public nonisolated enum AppLockAvailability: Sendable, Equatable {
    case available(AppLockBiometry)
    /// `LAError.passcodeNotSet`. security.md §3.3: the toggle is unavailable, and a lock that is
    /// already on can never be opened this way; the only way out is "Sign Out & Erase".
    case passcodeNotSet
    /// Any other reason the policy cannot be evaluated.
    case unavailable
}

/// TallyDomain's `DeviceAuthenticating` port plus what the lock view needs to label its button and
/// what Settings needs to offer the toggle. The production conformance is
/// `LocalAuthenticationAdapter` (`TallyPlatform`), over `LAContext`'s async API only.
public nonisolated protocol AppLockAuthenticating: DeviceAuthenticating {
    func availability() async -> AppLockAvailability
}

/// The default when no device authenticator is injected (tests, previews). It can never unlock:
/// every attempt reports `.failedOrCancelled`, so an injected lock with no authenticator fails
/// closed rather than open.
public nonisolated struct UnavailableAppLockAuthenticator: AppLockAuthenticating {
    public init() {}
    public func authenticate(reason: String) async -> AppLockPolicy.AuthResult { .failedOrCancelled }
    public func evaluatedPolicyDomainState() async -> Data? { nil }
    public func availability() async -> AppLockAvailability { .unavailable }
}

/// An in-process store: the default when the composition root injects none (tests, sample-only
/// previews). Nothing is persisted.
public nonisolated final class InMemoryAppLockPreferenceStore: AppLockPreferenceStoring {
    private let stored: Mutex<AppLockPreference?>

    public init(_ preference: AppLockPreference? = nil) {
        stored = Mutex(preference)
    }

    public func load() async -> AppLockPreferenceRead {
        stored.withLock { $0.map(AppLockPreferenceRead.found) ?? .notFound }
    }

    public func save(_ preference: AppLockPreference) async throws {
        stored.withLock { $0 = preference }
    }

    public func reset() async {
        stored.withLock { $0 = nil }
    }
}
