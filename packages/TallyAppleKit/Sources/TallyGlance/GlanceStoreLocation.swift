import Foundation

/// The three values the widget process needs to find the glance (plan 06 step 11). They come from
/// the widget extension's own Info.plist (`apps/TallyiOS/project.yml`), because nothing else can
/// tell the extension them: `Bundle.main` there is the extension, whose bundle ID is not the app's.
public struct GlanceConfiguration: Sendable, Equatable {
    /// The App Group the app and the widget share (`TALLY_SHARED_APP_GROUP_ID`).
    public let appGroupID: String
    /// The app's bundle ID. The widget-audience vault key's Keychain service is
    /// `<appBundleID>.vault.widget` (`KeychainVaultKeyStore`, encryption.md §3.4).
    public let appBundleID: String
    /// The Keychain access group of that key: the App Group ID behind the Team ID prefix
    /// (encryption.md §3.2, the widget entitlement's `$(AppIdentifierPrefix)$(TALLY_SHARED_APP_GROUP_ID)`).
    /// Without a Team ID (GO-LIVE GL-02) the prefix is empty, and on the CI simulator the query
    /// fails with `errSecMissingEntitlement` (-34018): the widget then shows its placeholder.
    public let keychainAccessGroup: String

    public static let appGroupIDKey = "TallyAppGroupID"
    public static let appBundleIDKey = "TallyAppBundleID"
    /// Info.plist value `$(AppIdentifierPrefix)`: "ABCDE12345." with a Team ID, empty without one.
    public static let keychainAccessGroupPrefixKey = "TallyKeychainAccessGroupPrefix"

    public init(appGroupID: String, appBundleID: String, keychainAccessGroup: String) {
        self.appGroupID = appGroupID
        self.appBundleID = appBundleID
        self.keychainAccessGroup = keychainAccessGroup
    }

    /// From an Info.plist dictionary. `nil` when the App Group ID or the app's bundle ID is missing
    /// or empty (a build misconfiguration, never a user state). A prefix that is not a Team ID
    /// followed by a dot (ten upper-case letters or digits; an unexpanded `$(…)`, say) counts as
    /// no Team ID at all.
    public static func from(infoDictionary: [String: Any]?) -> GlanceConfiguration? {
        guard let info = infoDictionary,
              let appGroupID = info[appGroupIDKey] as? String, !appGroupID.isEmpty,
              let appBundleID = info[appBundleIDKey] as? String, !appBundleID.isEmpty
        else { return nil }
        let prefix = (info[keychainAccessGroupPrefixKey] as? String) ?? ""
        return GlanceConfiguration(appGroupID: appGroupID, appBundleID: appBundleID,
                                   keychainAccessGroup: (isTeamIDPrefix(prefix) ? prefix : "") + appGroupID)
    }

    static func isTeamIDPrefix(_ prefix: String) -> Bool {
        let characters = Array(prefix)
        guard characters.count == 11, characters.last == "." else { return false }
        return characters.dropLast().allSatisfy { $0.isASCII && ($0.isUppercase || $0.isNumber) }
    }
}

/// Where the store lives inside the App Group container: `Library/Application Support/Tally/`
/// (architecture.md §3.2). `SnapshotStore` (`StoreLayout`) adds `accounts/<accountKey>/glance.v1.sealed`
/// below it. The app's composition root must commit the glance under this same root.
public enum GlanceStoreLocation {
    // MUTATION W2: an undeclared required-reason API in the widget bundle.
    public static var mutationW2: Bool { UserDefaults.standard.bool(forKey: "mutationW2") }

    public static func storeRoot(inContainer container: URL) -> URL {
        container
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Tally", isDirectory: true)
    }

    #if canImport(Darwin)
    /// `nil` when the process has no container for `appGroupID` (the entitlement is missing).
    public static func appGroupStoreRoot(appGroupID: String) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID).map(storeRoot(inContainer:))
    }
    #endif
}
