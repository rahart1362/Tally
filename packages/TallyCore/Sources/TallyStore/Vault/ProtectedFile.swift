import Foundation

/// The only place Tally writes a store file (WP-ENC-02 CI grep gate: no other `Data.write(to:`
/// in `TallyCore`). Class: `CompleteUntilFirstUserAuthentication` for every store file, because
/// background refresh and the widget must read while the device is locked (encryption.md §3.2).
///
/// The Data Protection class and `isExcludedFromBackup` are requested here as values; they compile
/// on Linux but are no-ops there (swift-corelibs-foundation has no Data Protection, and silently
/// ignores `isExcludedFromBackup`). Actual enforcement is device-only and is WP-ENC-06's job, not
/// this package's: this target only proves the request is made on every write and that Linux's
/// no-op does not corrupt anything.
public enum ProtectedFile {
    public static func prepareDirectory(_ url: URL, excludeFromBackup: Bool) throws {
        var attributes: [FileAttributeKey: Any] = [:]
        #if canImport(Darwin)
        attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
        #endif
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: attributes)
        if excludeFromBackup { try setExcludedFromBackup(url) }
    }

    /// nil when absent; `.protectedDataUnavailable` when Data Protection denies access.
    public static func read(_ url: URL) throws -> Data? {
        do { return try Data(contentsOf: url) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
        catch let error as CocoaError where error.code == .fileReadNoPermission { throw VaultError.protectedDataUnavailable }
        catch { throw VaultError.storage(code: (error as NSError).code) }
    }

    /// Temp file in the same directory -> write -> fsync -> rename (Foundation's `.atomic`), then
    /// re-apply backup exclusion: Apple says some file operations reset it, and it is only guidance.
    public static func atomicWrite(_ data: Data, to url: URL, excludeFromBackup: Bool) throws {
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            if excludeFromBackup { try setExcludedFromBackup(url) }
        } catch let error as CocoaError where error.code == .fileWriteNoPermission {
            throw VaultError.protectedDataUnavailable
        } catch {
            throw VaultError.storage(code: (error as NSError).code)
        }
    }

    public static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Removes anything not in `keeping` (e.g. temp files orphaned by a crash mid-write).
    /// Foreground-launch only, per encryption.md §3.6.
    public static func sweep(directory: URL, keeping names: Set<String>) {
        for name in (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [] where !names.contains(name) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    static func setExcludedFromBackup(_ url: URL) throws {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values) // no-op in swift-corelibs-foundation on Linux
    }
}

public enum SealedRead: Equatable, Sendable {
    case plaintext(Data)
    case absent
    case failed(VaultError, VaultDisposition)
}

/// Read/write one sealed store file and apply the disposition rules. `SnapshotStore` (and the
/// user-state / sync-ledger stores) call this instead of touching files or the sealer directly.
public struct SealedFileAccess: Sendable {
    public let sealer: any SnapshotSealer
    /// Only the owning process deletes. The widget passes `false`: it could otherwise race the
    /// app's atomic replace and delete a freshly written glance.
    public let isOwner: Bool

    public init(sealer: any SnapshotSealer, isOwner: Bool) { self.sealer = sealer; self.isOwner = isOwner }

    public func read(_ file: StoreFile, at url: URL) -> SealedRead {
        let blob: Data
        do {
            guard let data = try ProtectedFile.read(url) else { return .absent }
            blob = data
        } catch {
            let e = (error as? VaultError) ?? .storage(code: -1)
            return .failed(e, e.disposition(for: file))
        }
        do {
            return .plaintext(try sealer.open(blob, file: file))
        } catch {
            let e = (error as? VaultError) ?? .storage(code: -1)
            let d = e.disposition(for: file)
            if isOwner, d == .discardAndRebuild || d == .resetUserStateAndTell { ProtectedFile.remove(url) }
            return .failed(e, d)
        }
    }

    public func write(_ plaintext: Data, _ file: StoreFile, to url: URL, excludeFromBackup: Bool) throws {
        guard isOwner else { throw VaultError.readOnlyProcess }
        try ProtectedFile.atomicWrite(try sealer.seal(plaintext, file: file), to: url, excludeFromBackup: excludeFromBackup)
    }
}

/// Sign-out / "Clear cached data" for one account. Shred keys FIRST, then delete ciphertext: if
/// deletion fails or the app dies in between, what remains is undecryptable (encryption.md §3.7).
/// The caller (`AccountPurger`, or Security's `EraseService`) also revokes the token and removes
/// notifications, Spotlight/App Intents donations and, if the user chooses, Tally calendar events.
public enum VaultPurger {
    public static func purge(account: String, keyring: VaultKeyring, directories: [URL]) throws {
        try keyring.shred(account: account)
        for dir in directories { ProtectedFile.remove(dir) }
    }
}

/// Keychain items can survive app deletion (Apple: not guaranteed either way); files never do.
/// The first foreground launch of a fresh install shreds inherited keys. Foreground-only (the
/// sentinel check is not safe to run from a background launch).
public enum VaultBootstrap {
    public static func reconcileInstall(keyring: VaultKeyring, sentinel: URL) throws {
        guard !FileManager.default.fileExists(atPath: sentinel.path) else { return }
        try keyring.shredEverything()
        try ProtectedFile.atomicWrite(Data(), to: sentinel, excludeFromBackup: true)
    }
}
