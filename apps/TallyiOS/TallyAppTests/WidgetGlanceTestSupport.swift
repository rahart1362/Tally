import Foundation
import TallyDomain
import TallyStore
import TallyTestSupport

/// A store root with committed accounts, written the way the app writes them (an owner
/// `SnapshotStore` whose sealer may create keys), for the widget's reader to read.
struct GlanceStoreFixture {
    let root: URL
    /// Every key, both audiences: the app's view of the vault.
    let appKeys: InMemoryVaultKeyStore
    /// The widget's view of the same vault: the widget audience only (the App Group access group).
    var widgetKeys: InMemoryVaultKeyStore { appKeys.view(visible: [.widget]) }

    init() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("glance-\(UUID().uuidString)", isDirectory: true)
        appKeys = InMemoryVaultKeyStore()
    }

    static func account(_ userID: String) -> AccountKey {
        AccountKey.derive(host: "canvas.example.edu", userID: userID)
    }

    func ownerStore(_ account: AccountKey) -> SnapshotStore {
        SnapshotStore(root: root, accountKey: account,
                      sealer: VaultSealer(account: account.rawValue, keyring: VaultKeyring(store: appKeys), mayCreateKeys: true))
    }

    /// Commits a synthetic snapshot (`CanvasSnapshotFixture`) for `account` and returns its glance.
    @discardableResult
    func commit(_ account: AccountKey, fetchedAt: Date = Date(timeIntervalSince1970: 1_790_600_400),
                generation: UInt64 = 1, includeGrades: Bool = false, dueItemCount: Int = 3) async throws -> GlanceProjection {
        let snapshot = CanvasSnapshotFixture.make(generation: generation, accountKey: account, fetchedAt: fetchedAt,
                                                  dueItemCount: dueItemCount)
        return try await ownerStore(account).commit(snapshot, includeGrades: includeGrades)
    }

    func accountDirectory(_ account: AccountKey) -> URL {
        StoreLayout(root: root, accountKey: account).accountDirectory
    }

    /// Every file under the root with its bytes: what the widget must never change.
    func contents() -> [String: Data] {
        var files: [String: Data] = [:]
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return files }
        for case let url as URL in walker {
            if let data = try? Data(contentsOf: url) {
                files[String(url.path.dropFirst(root.path.count))] = data
            }
        }
        return files
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
