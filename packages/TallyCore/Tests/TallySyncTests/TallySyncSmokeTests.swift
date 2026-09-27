import Testing
import TallyTestSupport
@testable import TallySync

@Suite("TallySync smoke")
struct TallySyncSmokeTests {
    @Test("module links and exposes its name")
    func moduleLinks() {
        #expect(TallySyncModule.name == "TallySync")
        #expect(TallyTestSupportModule.name == "TallyTestSupport")
    }
}
