import Testing
import TallyDomain
@testable import TallyFeatures
@testable import Tally

/// E04: the composition root's `AppModel`. There is no signed-in account in this branch yet
/// (see `AppEnvironment`'s doc comment), so the honest, real state is `refreshCoordinator == nil`
/// — this suite proves that state is exactly what `AppEnvironment.live()` produces, and that
/// `AppModel` itself behaves correctly independent of that (attach/detach are exercised with a
/// real coordinator in `RefreshStatusModelTests`).
@Suite("AppModel / AppEnvironment: composition root")
@MainActor
struct AppModelTests {
    @Test("live() builds synchronously with no coordinator yet (no account exists in this branch)")
    func liveHasNoCoordinatorYet() {
        let environment = AppEnvironment.live()
        #expect(environment.appModel.refreshCoordinator == nil)
        #expect(environment.appModel.refreshStatus.freshness == .noCache)
    }

    @Test("a fresh AppModel starts detached")
    func freshAppModelIsDetached() {
        let model = AppModel()
        #expect(model.refreshCoordinator == nil)
        #expect(model.refreshStatus.freshness == .noCache)
    }
}
