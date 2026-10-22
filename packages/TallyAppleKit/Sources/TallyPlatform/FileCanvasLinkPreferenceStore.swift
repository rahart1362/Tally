import Foundation
import TallyFeatures
import TallyStore

/// FEAT-8 (Idea 7, "Open Canvas links in: App / Browser"): the student's choice, in one small
/// plaintext file in `StoreLocation.privateRoot()` -- never the shared App Group container
/// `FileNotEnabledSchoolPreferenceStore` uses (nothing here needs the widget), and never
/// `UserState` (FEAT-3 and FEAT-4 own the next schema bumps). Not sensitive, so no Keychain: the
/// same `ProtectedFile` pattern every other small device preference uses.
public final class FileCanvasLinkPreferenceStore: CanvasLinkPreferenceStoring, Sendable {
    private let fileURL: @Sendable () throws -> URL

    /// - Parameter fileURL: resolves the file's location; called fresh each time (mirrors
    ///   `FileNotEnabledSchoolPreferenceStore`).
    public init(fileURL: @escaping @Sendable () throws -> URL) {
        self.fileURL = fileURL
    }

    public func load() async -> CanvasLinkPreference? {
        guard let url = try? fileURL(), let data = (try? ProtectedFile.read(url)) ?? nil,
              let rawValue = String(data: data, encoding: .utf8) else { return nil }
        return CanvasLinkPreference(rawValue: rawValue)
    }

    public func save(_ preference: CanvasLinkPreference) async {
        guard let url = try? fileURL() else { return }
        try? ProtectedFile.prepareDirectory(url.deletingLastPathComponent(), excludeFromBackup: true)
        try? ProtectedFile.atomicWrite(Data(preference.rawValue.utf8), to: url, excludeFromBackup: true)
    }

    public func clear() async {
        guard let url = try? fileURL() else { return }
        ProtectedFile.remove(url)
    }
}
