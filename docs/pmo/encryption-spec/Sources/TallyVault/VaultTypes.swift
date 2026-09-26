import Foundation

/// Architecture's contract (docs/pmo/reviews/architecture.md §3.2), reproduced so conformance compiles here.
public protocol SnapshotSealer: Sendable {
    func seal(_ plaintext: Data, file: StoreFile) throws -> Data
    func open(_ sealed: Data, file: StoreFile) throws -> Data
}

/// Raw value = the file byte in the authenticated header, so a blob can never be opened as another file.
public enum StoreFile: UInt8, Sendable, CaseIterable {
    case snapshot = 0x01, glance = 0x02, userState = 0x03, ledger = 0x04
    /// `glance` is the only file whose key the widget extension can reach.
    public var audience: KeyAudience { self == .glance ? .widget : .app }
    /// userState is user-authored and cannot be re-fetched; everything else can be rebuilt.
    public var isRederivable: Bool { self != .userState }
}

public enum KeyAudience: String, Sendable, CaseIterable { case app, widget }

/// One key per (account, audience). `account` is Architecture's accountKey (hex digest, no PII).
public struct KeyScope: Hashable, Sendable {
    public let account: String
    public let audience: KeyAudience
    public init(account: String, audience: KeyAudience) { self.account = account; self.audience = audience }
}

public enum VaultError: Error, Equatable, Sendable {
    /// Device locked / before first unlock. NEVER delete, re-key or treat as corruption.
    case protectedDataUnavailable
    /// Blob names a key that does not exist: new device, reinstall, or after a purge.
    case keyMissing
    case malformed
    case unsupportedFormat(UInt8)
    case fileMismatch
    /// GCM tag failure: corruption, torn write, tampering or wrong key.
    case authenticationFailed
    /// Seal attempted in a process that may not create keys (the widget extension).
    case readOnlyProcess
    case storage(code: Int)
}

/// What the SnapshotStore MUST do with each outcome. Pure, so it is unit-tested on Linux.
public enum VaultDisposition: Equatable, Sendable {
    case retryAfterUnlock      // keep file + key + in-memory state; retry on protectedDataDidBecomeAvailable
    case discardAndRebuild     // owner deletes file; snapshot -> refetch, glance -> rebuild from snapshot, ledger -> reconcile
    case resetUserStateAndTell // userState only: cannot be re-fetched; start empty and tell the user once
    case keepAndReport         // unclassified I/O error: keep everything, log category, retry later
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
