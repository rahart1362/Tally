import Foundation

/// Where the sealed store lives (architecture.md §3.2): `<App Group container>/Library/Application
/// Support/Tally`, beside `accounts.json`, so the widget can read the glance. When the App Group
/// container is unavailable (an unsigned or mis-provisioned build), the app's own Application
/// Support is used instead: the app still works, only the widget cannot see its glance.
///
/// File-system calls: the composition root hands this to `AccountEnvironment.storeRoot`, which is
/// only ever called off the main actor.
public enum StoreLocation {
    public static let folderName = "Tally"

    /// The App Group identifier from the app's Info.plist (`TallyAppGroupID`, project.yml).
    public static var appGroupID: String? {
        Bundle.main.object(forInfoDictionaryKey: "TallyAppGroupID") as? String
    }

    public static func root(appGroupID: String?) throws -> URL {
        let fileManager = FileManager.default
        if let appGroupID, !appGroupID.isEmpty,
           let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return container.appendingPathComponent("Library/Application Support/\(folderName)", isDirectory: true)
        }
        let support = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                          appropriateFor: nil, create: true)
        return support.appendingPathComponent(folderName, isDirectory: true)
    }
}
