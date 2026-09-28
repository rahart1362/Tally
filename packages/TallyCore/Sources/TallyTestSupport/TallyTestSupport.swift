// Plan 06 A1: the replay transport lives in `TallyReplay` (it ships in the app's sample mode);
// every test that imports TallyTestSupport keeps seeing `ReplayTransport` and `RouteFixture`.
@_exported import TallyReplay
import TallyCanvasAPI
import TallyDomain
import TallyStore

/// Test doubles shared by every test target: fixture loader, replay
/// transport, test clock, and in-memory stores.
public enum TallyTestSupportModule {
    public static let name = "TallyTestSupport"
}
