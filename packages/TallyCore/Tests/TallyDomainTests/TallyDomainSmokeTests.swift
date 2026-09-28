import Testing
import TallyTestSupport
@testable import TallyDomain

@Suite("TallyDomain smoke")
struct TallyDomainSmokeTests {
    @Test("module links and exposes its name")
    func moduleLinks() {
        #expect(TallyDomainModule.name == "TallyDomain")
        #expect(TallyTestSupportModule.name == "TallyTestSupport")
    }
}
