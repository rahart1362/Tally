import Foundation
import Testing
@testable import TallyDomain

private enum Course {}

@Suite("CanvasID")
struct CanvasIDTests {
    @Test func idsAbove2to53SurviveExactly() throws {
        let json = Data(#"["9007199254740993","12345678901234567890"]"#.utf8)
        let ids = try JSONDecoder().decode([CanvasID<Course>].self, from: json)
        #expect(ids.map(\.rawValue) == ["9007199254740993", "12345678901234567890"])
        #expect(try JSONEncoder().encode(ids) == json)
    }

    @Test func numericOrdering() {
        let ids: [CanvasID<Course>] = ["10", "9", "100", "11"]
        #expect(ids.sorted().map(\.rawValue) == ["9", "10", "11", "100"])
    }
}
