import Foundation
import Testing
import TallyDomain
import TallyTestSupport
@testable import TallyCanvasAPI

@Suite("Profile and user color mapping (fixtures)")
struct ProfileAndColorMapperTests {
    @Test(arguments: Fixtures.personas)
    func everyPersonaProfileDecodes(_ persona: String) throws {
        let profile = try ProfileMapper.map(Fixtures.data("personas/\(persona)/profile.json"))
        #expect(!profile.id.rawValue.isEmpty)
        #expect(!profile.name.isEmpty)
    }

    @Test func flagshipProfileHasNameTimeZoneAndCalendarFeedURL() throws {
        let profile = try ProfileMapper.map(Fixtures.data("personas/flagship/profile.json"))
        #expect(profile.id == "4820117" && profile.name == "Alex Sample")
        #expect(profile.timeZone == "America/Chicago")
        #expect(profile.calendarFeedURL?.absoluteString ==
                "https://canvas.northfield.example/feeds/calendars/user_Ask1r4LgYYQc3tzK8hToYfa1q5mdJkBhUxEMPXg7.ics")
    }

    @Test func profileWithoutCalendarBlockHasNilFeedURL() throws {
        let json = #"{"id":"1","name":"No Calendar"}"#
        let profile = try ProfileMapper.map(Data(json.utf8))
        #expect(profile.calendarFeedURL == nil && profile.shortName == nil)
    }

    @Test(arguments: Fixtures.personas)
    func everyPersonaColorsDecode(_ persona: String) throws {
        let colors = try UserColorMapper.map(Fixtures.data("personas/\(persona)/colors.json"))
        #expect(persona == "empty" ? colors.isEmpty : !colors.isEmpty)
        #expect(colors.values.allSatisfy { $0.hasPrefix("#") })
    }

    @Test func flagshipColorsKeyByCourseAndDropNonCourseKeys() throws {
        let colors = try UserColorMapper.map(Fixtures.data("personas/flagship/colors.json"))
        #expect(colors.count == 5)
        #expect(colors[CanvasID<Course>("51842")] == "#1770AB")
        #expect(colors[CanvasID<Course>("51845")] == "#65499D")
        #expect(colors.keys.allSatisfy { $0.rawValue != "4820117" }) // the user_ accent color is not a course color
    }

    @Test func emptyPersonaHasNoCustomColors() throws {
        #expect(try UserColorMapper.map(Fixtures.data("personas/empty/colors.json")).isEmpty)
    }
}
