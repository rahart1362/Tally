import Foundation
import Testing
import TallyDesignSystem

/// MVP-2b: `TallyTokenBreaks.breakable` lets a one-word value wrap only at its own separators.
@Suite("Token breaks: a web address or a price wraps at its separators, never mid-word")
struct TokenBreaksTests {
    private static let space = String(TallyTokenBreaks.opportunity)

    @Test("A web address gets a break opportunity after each dot")
    func webAddress() {
        #expect(TallyTokenBreaks.breakable("canvas.northfield.example")
            == "canvas." + Self.space + "northfield." + Self.space + "example")
    }

    @Test("A price breaks after its slash, never inside the amount")
    func price() {
        #expect(TallyTokenBreaks.breakable("$9.99/year") == "$9.99/" + Self.space + "year")
    }

    @Test("Text with nothing to break, and a trailing separator, are unchanged")
    func unchanged() {
        for value in ["Northfield University", "9.99", "x/9", "ends.", ""] {
            #expect(TallyTokenBreaks.breakable(value) == value)
        }
    }

    @Test("Removing the break opportunities gives back the original value")
    func reversible() {
        let value = "canvas.northfield.example"
        #expect(TallyTokenBreaks.breakable(value).replacingOccurrences(of: Self.space, with: "") == value)
    }
}
