import Testing
import TallyTestSupport
@testable import TallyStore

@Suite("TallyStore smoke")
struct TallyStoreSmokeTests {
    @Test("module links and exposes its name")
    func moduleLinks() {
        #expect(TallyStoreModule.name == "TallyStore")
        #expect(TallyTestSupportModule.name == "TallyTestSupport")
    }
}
