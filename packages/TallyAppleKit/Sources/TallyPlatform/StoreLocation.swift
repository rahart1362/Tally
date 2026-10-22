import Foundation

/// Where the store lives (architecture.md §3.2; SEC1-09 minimisation). Two roots, not one:
/// - `privateRoot()`: the app's own Application Support. `accounts.json` and every account file
///   except the glance live here — nothing the widget needs to read.
/// - `sharedRoot(appGroupID:)`: the App Group container, when its entitlement is actually usable.
///   Only `glance.v1.sealed` ever goes here: the one file the widget's `GlanceReader` opens.
///
/// Before SEC1-09 there was one root, the App Group container when available and the app's own
/// storage otherwise (`AccountEnvironment.storeRoot`'s old contract) — every file, including
/// `accounts.json`, sat wherever the widget could also reach it. `StoreMigration` moves an
/// existing install's files from that old, combined location to the new split one.
///
/// File-system calls: the composition root hands these to `AccountEnvironment.storeRoot` /
/// `.sharedRoot`, which are only ever called off the main actor.
public enum StoreLocation {
    public static let folderName = "Tally"

    /// The App Group identifier from the app's Info.plist (`TallyAppGroupID`, project.yml).
    public static var appGroupID: String? {
        Bundle.main.object(forInfoDictionaryKey: "TallyAppGroupID") as? String
    }

    /// Always succeeds (Application Support always exists), independent of whether the App Group
    /// entitlement is usable. SEC1-09: this is where `accounts.json` and every account file except
    /// the glance live.
    public static func privateRoot() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                   appropriateFor: nil, create: true)
        return support.appendingPathComponent(folderName, isDirectory: true)
    }

    /// `nil` when the App Group entitlement is missing or mis-provisioned (GO-LIVE GL-02; an
    /// unsigned or ad-hoc build without a Team ID can still fail this). Callers must not fall back
    /// to `privateRoot()` for this value: a `nil` here means "the widget gets no glance this
    /// launch," not "write it somewhere else instead" — that would defeat SEC1-09's point. Before
    /// the split, this same lookup (with that private-storage fallback) was the app's *only* root,
    /// so a build whose App Group never resolves degrades exactly as it always did: one root, no
    /// split, nothing new to migrate (`StoreMigration`'s `privateRoot == oldCombinedRoot` guard).
    public static func sharedRoot(appGroupID: String?) -> URL? {
        guard let appGroupID, !appGroupID.isEmpty,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        else { return nil }
        return container.appendingPathComponent("Library/Application Support/\(folderName)", isDirectory: true)
    }
}
