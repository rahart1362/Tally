import Foundation
import Observation
import TallyDomain
import TallyStrings

/// Settings' App Lock rows (UX-WP-20, ux-ui.md §3.7.7 "App Lock (Face ID with passcode fallback)"),
/// over M2-C1's `AppLockModel` API. The rules stay there and in TallyDomain's `AppLockPolicy`; this
/// model only decides what the toggle shows:
///
/// - The switch moves at once, then `AppLockModel.setEnabled(_:)` decides. It returns `false` when
///   the device has no passcode (turning on) or the authentication failed or was cancelled
///   (turning off, MASVS-AUTH-3), and the switch then **snaps back** to the lock's real state.
/// - security.md §3.3: "`passcodeNotSet` means the toggle is unavailable", so it is disabled then,
///   with a line saying why. Any other reason the device cannot authenticate disables turning it
///   on; a lock that is already on can still be asked to turn off (that needs an authentication).
/// - The grace period ("Require Unlock") shows only while the lock is on.
///
/// Changes run in a task this model owns, never in a view's.
@MainActor
@Observable
public final class AppLockSettingsModel {
    /// Explicit and nonisolated (plan 06 A2; swiftlang/swift#88036).
    nonisolated deinit {}

    /// What the toggle is showing: the lock's state, or, while a change is being decided, the state
    /// the student asked for.
    public private(set) var isOn: Bool
    public private(set) var gracePeriod: AppLockPolicy.GracePeriod
    /// `availability` has been read (the rows show only then, so they never flash disabled).
    public private(set) var hasLoaded = false
    /// A change is being decided (an authentication may be on screen): the toggle waits.
    public private(set) var isChanging = false

    private let lock: AppLockModel
    private let changing = TaskBox()

    public init(lock: AppLockModel) {
        self.lock = lock
        isOn = lock.isEnabled
        gracePeriod = lock.gracePeriod
    }

    public var availability: AppLockAvailability { lock.availability }

    /// Reads whether the device can authenticate (`AppLockModel.refreshAvailability()`), and the
    /// lock's current setting.
    public func load() async {
        await lock.refreshAvailability()
        isOn = lock.isEnabled
        gracePeriod = lock.gracePeriod
        hasLoaded = true
    }

    /// Whether the student can use the toggle now.
    public var isToggleEnabled: Bool {
        guard !isChanging else { return false }
        switch availability {
        case .available: return true
        case .passcodeNotSet: return false
        case .unavailable: return lock.isEnabled
        }
    }

    public var title: String { String(localized: L10n.Lock.settingsTitle()) }

    /// The line under the rows: what the lock asks for, or why it cannot be used.
    public var footer: String {
        switch availability {
        case .available(let biometry):
            return String(localized: L10n.Lock.footerAsks(Self.credential(biometry)))
        case .passcodeNotSet:
            return lock.isEnabled
                ? String(localized: L10n.Lock.footerPasscodeNotSetLockOn())
                : String(localized: L10n.Lock.footerPasscodeNotSetLockOff())
        case .unavailable:
            return String(localized: L10n.Lock.footerUnavailable())
        }
    }

    /// The toggle: the switch moves at once, then snaps back if the lock did not change.
    public func requestEnabled(_ enabled: Bool) {
        guard !isChanging else { return }
        guard enabled != lock.isEnabled else {
            isOn = lock.isEnabled
            return
        }
        isOn = enabled
        isChanging = true
        changing.replace(with: Task { [weak self] in await self?.decide(enabled) })
    }

    /// `requestEnabled(_:)`, awaited to its end (tests).
    func setEnabled(_ enabled: Bool) async {
        requestEnabled(enabled)
        await awaitChange()
    }

    private func decide(_ enabled: Bool) async {
        _ = await lock.setEnabled(enabled)
        isChanging = false
        isOn = lock.isEnabled
        gracePeriod = lock.gracePeriod
    }

    /// "Require Unlock": how long Tally may stay in the background before it locks again.
    public func requestGracePeriod(_ period: AppLockPolicy.GracePeriod) {
        guard !isChanging, period != lock.gracePeriod else { return }
        gracePeriod = period
        isChanging = true
        changing.replace(with: Task { [weak self] in await self?.decide(period) })
    }

    /// `requestGracePeriod(_:)`, awaited to its end (tests).
    func setGracePeriod(_ period: AppLockPolicy.GracePeriod) async {
        requestGracePeriod(period)
        await awaitChange()
    }

    private func decide(_ period: AppLockPolicy.GracePeriod) async {
        await lock.setGracePeriod(period)
        isChanging = false
        gracePeriod = lock.gracePeriod
    }

    /// Waits for the change in flight (tests).
    func awaitChange() async {
        await changing.value()
    }

    public static func label(for period: AppLockPolicy.GracePeriod) -> String {
        switch period {
        case .immediately: String(localized: L10n.Lock.graceImmediately())
        case .oneMinute: String(localized: L10n.Lock.graceOneMinute())
        case .fiveMinutes: String(localized: L10n.Lock.graceFiveMinutes())
        case .fifteenMinutes: String(localized: L10n.Lock.graceFifteenMinutes())
        }
    }

    private static func credential(_ biometry: AppLockBiometry) -> String {
        switch biometry {
        case .faceID: String(localized: L10n.Lock.credentialFaceID())
        case .touchID: String(localized: L10n.Lock.credentialTouchID())
        case .opticID: String(localized: L10n.Lock.credentialOpticID())
        case .noBiometry: String(localized: L10n.Lock.credentialPasscodeOnly())
        }
    }
}
