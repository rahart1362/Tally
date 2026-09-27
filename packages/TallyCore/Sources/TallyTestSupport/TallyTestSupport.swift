import TallyCanvasAPI
import TallyDomain
import TallyStore

/// Test doubles shared by every test target: fixture loader, replay
/// transport, test clock, and in-memory stores.
public enum TallyTestSupportModule {
    public static let name = "TallyTestSupport"
}
