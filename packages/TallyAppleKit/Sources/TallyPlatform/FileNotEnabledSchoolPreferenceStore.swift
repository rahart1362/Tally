import Foundation
import TallyFeatures
import TallyStore

/// FEAT-2: the searched-but-not-enabled school name, in one small plaintext file beside the account
/// stores (`StoreLocation.root`), protected and excluded from backup the way `ProtectedFile`
/// protects every other store file (WP-ENC-02's "no other `Data.write(to:` in `TallyCore`" gate is
/// a `TallyCore` rule; this is `TallyAppleKit`'s own platform adapter, so it reuses `ProtectedFile`
/// directly rather than hand-rolling a second `Data.write(to:`). No Keychain and no sealing: the
/// value is not sensitive the way the app lock flag is (`KeychainAppLockPreferenceStore`) — a
/// free-text school name the student already typed, never transmitted.
public final class FileNotEnabledSchoolPreferenceStore: NotEnabledSchoolPreferenceStoring, Sendable {
    private let fileURL: @Sendable () throws -> URL

    /// - Parameter fileURL: resolves the file's location; called fresh each time (the App Group
    ///   container can become available only after first unlock).
    public init(fileURL: @escaping @Sendable () throws -> URL) {
        self.fileURL = fileURL
    }

    public func load() async -> String? {
        guard let url = try? fileURL(), let data = (try? ProtectedFile.read(url)) ?? nil else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func save(_ schoolName: String) async {
        guard let url = try? fileURL() else { return }
        try? ProtectedFile.prepareDirectory(url.deletingLastPathComponent(), excludeFromBackup: true)
        try? ProtectedFile.atomicWrite(Data(schoolName.utf8), to: url, excludeFromBackup: true)
    }

    public func clear() async {
        guard let url = try? fileURL() else { return }
        ProtectedFile.remove(url)
    }
}
