import Foundation

/// Architecture's contract (docs/pmo/reviews/architecture.md §3.2): the store never touches the
/// file system or key material directly, it only asks to seal/open plaintext for a given file kind.
/// `VaultSealer` (this module) is the production conformance.
public protocol SnapshotSealer: Sendable {
    func seal(_ plaintext: Data, file: StoreFile) throws -> Data
    func open(_ sealed: Data, file: StoreFile) throws -> Data
}

/// Raw value = the file byte authenticated in the blob header (§3.5), so a blob sealed for one
/// slot can never be opened as another (`VaultError.fileMismatch`).
public enum StoreFile: UInt8, Sendable, CaseIterable {
    case snapshot = 0x01, glance = 0x02, userState = 0x03, ledger = 0x04

    /// `glance` is the only file whose key the widget extension may hold (encryption.md §3.4).
    public var audience: KeyAudience { self == .glance ? .widget : .app }

    /// `userState` is user-authored and cannot be re-fetched; every other file can be rebuilt
    /// from Canvas (or, for `glance`, from the snapshot already on disk).
    public var isRederivable: Bool { self != .userState }
}

public enum KeyAudience: String, Sendable, CaseIterable { case app, widget }

/// One key per (account, audience). `account` is Architecture's `AccountKey.rawValue` (a hex
/// digest with no PII), so this type never carries a name or a host.
public struct KeyScope: Hashable, Sendable {
    public let account: String
    public let audience: KeyAudience
    public init(account: String, audience: KeyAudience) { self.account = account; self.audience = audience }
}

public enum VaultError: Error, Equatable, Sendable {
    /// Device locked / before first unlock (Keychain `errSecInteractionNotAllowed`, or a denied
    /// file read). NEVER delete, re-key or treat as corruption (encryption.md ENC-01/ENC-02).
    case protectedDataUnavailable
    /// The blob names a key that does not exist: new device, reinstall, or after a purge.
    case keyMissing
    case malformed
    case unsupportedFormat(UInt8)
    /// The blob decrypted under the right key for the wrong `StoreFile` slot (e.g. copied).
    case fileMismatch
    /// GCM tag failure: corruption, a torn write, tampering, or the wrong key.
    case authenticationFailed
    /// A seal was attempted in a process that may not mint keys (the widget extension).
    case readOnlyProcess
    case storage(code: Int)
}

/// What the store MUST do with each outcome. Pure (Sendable, Equatable), so the rule is
/// unit-tested without touching a file or a Keychain.
public enum VaultDisposition: Equatable, Sendable {
    /// Keep the file, the key and any in-memory state; retry once the device unlocks.
    case retryAfterUnlock
    /// The owner deletes the file: a snapshot re-fetches, a glance rebuilds, a ledger reconciles.
    case discardAndRebuild
    /// `userState` only: it cannot be re-fetched, so the store starts empty and tells the user once.
    case resetUserStateAndTell
    /// An unclassified I/O error: keep everything, log the category, retry later.
    case keepAndReport
}

extension VaultError {
    public func disposition(for file: StoreFile) -> VaultDisposition {
        switch self {
        case .protectedDataUnavailable: return .retryAfterUnlock
        case .storage, .readOnlyProcess: return .keepAndReport
        case .keyMissing, .malformed, .unsupportedFormat, .fileMismatch, .authenticationFailed:
            return file.isRederivable ? .discardAndRebuild : .resetUserStateAndTell
        }
    }
}
