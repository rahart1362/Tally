import Testing
import TallyTestSupport
@testable import TallyCanvasAPI

@Suite("TallyCanvasAPI smoke")
struct TallyCanvasAPISmokeTests {
    @Test("module links and exposes its name")
    func moduleLinks() {
        #expect(TallyCanvasAPIModule.name == "TallyCanvasAPI")
        #expect(TallyTestSupportModule.name == "TallyTestSupport")
    }
}
