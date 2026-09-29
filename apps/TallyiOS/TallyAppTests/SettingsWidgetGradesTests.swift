import Foundation
import Synchronization
import Testing
import TallyDomain
import TallyStore
import TallySync
import TallyTestSupport
@testable import TallyFeatures

/// M3-A O11 (PMO R10): "Show Grades in Widgets" reaches the widget when it is saved, not when the
/// account's coordinator is next built. Turning grades off rebuilds the glance on disk without them
/// and reloads the widget; a save that leaves the setting alone reloads nothing.
@Suite("M3-A O11: Show Grades in Widgets reaches the glance on disk at once")
@MainActor
struct SettingsWidgetGradesTests {
    private final class Reloads: Sendable {
        private let count = Mutex(0)
        func record() { count.withLock { $0 += 1 } }
        var value: Int { count.withLock { $0 } }
    }

    private static func hasGrades(_ result: GlanceLoadResult) -> Bool? {
        guard case .loaded(let glance) = result else { return nil }
        return glance.overallGradeBand != nil || glance.courses.contains { $0.currentGrade != nil }
    }

    @Test("turning grades off takes them out of the glance on disk and reloads the widget once",
          .timeLimit(.minutes(2)))
    func turningGradesOffReachesTheWidgetNow() async throws {
        let account = AccountKey("m3-widget-grades-\(UUID().uuidString)")
        let (directory, sealer) = try ScreenModelSupport.sealer(account)
        let userStateStore = UserStateStore(root: directory, accountKey: account, sealer: sealer)
        try await userStateStore.save(UserState(showGradesInGlance: true))
        let snapshotStore = SnapshotStore(root: directory, accountKey: account, sealer: sealer)
        let coordinator = RefreshCoordinator(
            gateway: ServingGateway(CanvasSnapshotFixture.make(generation: 1)), store: snapshotStore,
            clock: SystemDateProvider(), initialSnapshot: nil, includeGrades: true)
        let runtime = AccountRuntime()
        await runtime.install(coordinator)
        _ = await coordinator.run(trigger: .manual)
        #expect(Self.hasGrades(await snapshotStore.loadGlance()) == true, "committed with grades opted in")

        let reloads = Reloads()
        let settings = SettingsModel(userState: AccountUserStateAccess(store: userStateStore, runtime: runtime,
                                                                       reloadWidgets: { reloads.record() }))
        await settings.load()
        #expect(settings.showGradesInWidgets)

        settings.setShowGradesInWidgets(false)
        await settings.awaitSaved()
        #expect(Self.hasGrades(await snapshotStore.loadGlance()) == false, "no grades on disk, before any refresh")
        #expect(reloads.value == 1)
        #expect(await coordinator.includeGrades == false)

        settings.setEveryChange(true) // another setting: the glance is already right
        await settings.awaitSaved()
        #expect(reloads.value == 1, "a save that leaves the widget setting alone reloads nothing")
    }
}
