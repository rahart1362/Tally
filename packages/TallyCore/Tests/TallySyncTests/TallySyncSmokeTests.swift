import Testing
import TallyTestSupport
@testable import TallySync

@Suite("TallySync smoke", .timeLimit(.minutes(1)))
struct TallySyncSmokeTests {
    @Test("module links and exposes its name")
    func moduleLinks() {
        #expect(TallySyncModule.name == "TallySync")
        #expect(TallyTestSupportModule.name == "TallyTestSupport")
    }
}
