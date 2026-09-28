import Foundation
import Testing
import TallyDomain
import TallyTestSupport
@testable import TallyStore

/// SH-4 (sync-hardening.md; crash-safety.md "Remaining risks"): nothing keeps a `SnapshotStore`
/// alive once its owner lets go, after the calls it normally serves, for the app (the owner) and
/// for the widget (a read-only, non-owner view of the same account).
@Suite("SnapshotStore lifecycle: deallocates after typical use (SH-4)")
struct SnapshotStoreLifecycleTests {
    private let accountKey = AccountKey("acct-sh4")

    @Test func deallocatesAfterTypicalUse() async throws {
        weak var weakAppStore: SnapshotStore?
        weak var weakWidgetStore: SnapshotStore?
        do {
            let root = try tempStoreDirectory()
            let keyring = VaultKeyring(store: InMemoryVaultKeyStore())
            let appStore = SnapshotStore(root: root, accountKey: accountKey,
                                         sealer: VaultSealer(account: accountKey.rawValue, keyring: keyring, mayCreateKeys: true))
            weakAppStore = appStore
            try await appStore.prepare()
            try await appStore.commit(CanvasSnapshotFixture.make(generation: 1), includeGrades: false)
            try await appStore.commit(CanvasSnapshotFixture.make(generation: 2), includeGrades: true)
            await #expect(throws: SnapshotStoreError.staleGeneration(attempted: 2, current: 2)) {
                try await appStore.commit(CanvasSnapshotFixture.make(generation: 2), includeGrades: false)
            }
            guard case .loaded = await appStore.loadSnapshot() else { Issue.record("expected the committed snapshot"); return }
            guard case .loaded = await appStore.loadGlance() else { Issue.record("expected the glance"); return }
            await appStore.sweepOrphanedTempFiles()

            let widgetStore = SnapshotStore(root: root, accountKey: accountKey,
                                            sealer: VaultSealer(account: accountKey.rawValue, keyring: keyring, mayCreateKeys: false),
                                            isOwner: false)
            weakWidgetStore = widgetStore
            guard case .loaded = await widgetStore.loadGlance() else { Issue.record("expected the widget to read the glance"); return }
        }
        #expect(weakAppStore == nil, "SnapshotStore must not outlive its owner")
        #expect(weakWidgetStore == nil, "nor may the widget's read-only store")
    }
}
