import Foundation
import Testing
import TallyDomain
import TallyTestSupport
@testable import TallyCanvasAPI

@Suite("Planner items, calendar events and announcements (fixtures)")
struct ScheduleMapperTests {
    private let host = "canvas.northfield.example"

    /// Every `<prefix>*.json` body directly under `fixtures/canvas/<dir>` (paged and/or
    /// chunked file names all start with the endpoint's own name).
    private func bodies(_ dir: String, prefix: String) throws -> [URL] {
        let root = Fixtures.root().appendingPathComponent(dir)
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "json" && !$0.lastPathComponent.hasSuffix(".headers.json") }
    }

    // MARK: Planner items

    @Test(arguments: Fixtures.personas)
    func everyPersonaPlannerPageDecodes(_ persona: String) throws {
        let pages = try bodies("personas/\(persona)", prefix: "planner_items")
        #expect(!pages.isEmpty)
        for page in pages {
            let mapped = try PlannerItemMapper.map(Data(contentsOf: page), host: host)
            #expect(mapped.dropped == 0, "\(page.lastPathComponent) dropped an item")
        }
    }

    @Test func plannerItemDateComesFromPlannableDateForEveryType() throws {
        let items = try PlannerItemMapper.map(Fixtures.data("personas/finals/planner_items.json"), host: host).items
        let types = Set(items.map(\.plannableType))
        #expect(types.isSuperset(of: ["assignment", "quiz", "announcement", "calendar_event"]))
        #expect(items.allSatisfy { $0.dueAt != nil }) // every persona/scenario item carries plannable_date
    }

    @Test func plannerNoteResolvesAbsoluteURLAndAssignmentResolvesRelativeURL() throws {
        let items = try PlannerItemMapper.map(Fixtures.data("personas/flagship/planner_items.page1.json"), host: host).items
        let note = try #require(items.first { $0.id == "planner_note:1200" })
        #expect(note.title == "Study group: Calc II" && note.courseID == "51842")
        #expect(note.htmlURL?.absoluteString == "https://canvas.northfield.example/api/v1/planner_notes/1200")

        let markedComplete = try #require(items.first { $0.id == "assignment:1204492" })
        #expect(markedComplete.markedComplete)
        #expect(markedComplete.htmlURL?.absoluteString == "https://canvas.northfield.example/courses/51847/assignments/1204492")
    }

    @Test func submissionFlagsCarryThroughAndFalseMeansNoFlags() throws {
        let items = try PlannerItemMapper.map(Fixtures.data("personas/flagship/planner_items.page1.json"), host: host).items
        #expect(items.first { $0.id == "assignment:1204435" }?.excused == true)
        #expect(items.first { $0.id == "assignment:1204486" }?.late == true)
        #expect(items.first { $0.id == "assignment:1204411" }?.missing == true)
        let event = try #require(items.first { $0.plannableType == "calendar_event" })
        #expect(!event.submitted && !event.graded && !event.missing && !event.late && !event.excused)
    }

    @Test func plannerMultiPageScenarioDecodesEveryPage() throws {
        for page in ["page1", "page2", "page3"] {
            let mapped = try PlannerItemMapper.map(Fixtures.data("scenarios/planner_items/multi-page.\(page).json"), host: host)
            #expect(mapped.dropped == 0 && !mapped.items.isEmpty)
        }
    }

    @Test func plannerItemWithoutIdOrTypeIsDroppedAndCounted() throws {
        let json = #"[{"course_id":"1","plannable_date":"2026-01-01T00:00:00Z"},{"plannable_id":"9","plannable_type":"assignment","plannable_date":"2026-01-01T00:00:00Z"}]"#
        let mapped = try PlannerItemMapper.map(Data(json.utf8), host: host)
        #expect(mapped.dropped == 1 && mapped.items.map(\.id) == ["assignment:9"])
    }

    // MARK: Calendar events

    @Test(arguments: Fixtures.personas.filter { $0 != "empty" })
    func everyPersonaCalendarChunkDecodes(_ persona: String) throws {
        let chunks = try bodies("personas/\(persona)", prefix: "calendar_events")
        #expect(!chunks.isEmpty)
        for chunk in chunks {
            let mapped = try CalendarEventMapper.map(Data(contentsOf: chunk))
            #expect(mapped.dropped == 0, "\(chunk.lastPathComponent) dropped an item")
            #expect(mapped.items.allSatisfy { $0.courseID != nil })
        }
    }

    @Test func recurringClassEventMapsWithCourseAndLocation() throws {
        let events = try CalendarEventMapper.map(Fixtures.data("personas/flagship/calendar_events.chunk1.page1.json")).items
        let lecture = try #require(events.first { $0.id == "3310016" })
        #expect(lecture.title == "PSY 101 Lecture" && lecture.courseID == "51843")
        #expect(lecture.locationName == "Sage Hall 101" && !lecture.allDay)
        #expect(lecture.htmlURL?.absoluteString.contains("event_id=3310016") == true)
    }

    @Test func calendarEventWithoutStartAtIsDroppedAndCounted() throws {
        let json = #"[{"id":"1","title":"No start"},{"id":"2","title":"Ok","start_at":"2026-01-01T00:00:00Z","context_code":"course_9"}]"#
        let mapped = try CalendarEventMapper.map(Data(json.utf8))
        #expect(mapped.dropped == 1 && mapped.items.map(\.id) == ["2"])
    }

    @Test func nonCourseContextKeepsTheEventWithNilCourseID() throws {
        let json = #"[{"id":"1","title":"Personal","start_at":"2026-01-01T00:00:00Z","context_code":"user_42"}]"#
        let mapped = try CalendarEventMapper.map(Data(json.utf8))
        #expect(mapped.dropped == 0 && mapped.items.first?.courseID == nil)
    }

    // MARK: Announcements

    @Test(arguments: Fixtures.personas.filter { $0 != "empty" })
    func everyPersonaAnnouncementChunkDecodes(_ persona: String) throws {
        let chunks = try bodies("personas/\(persona)", prefix: "announcements")
        #expect(!chunks.isEmpty)
        for chunk in chunks {
            let mapped = try AnnouncementMapper.map(Data(contentsOf: chunk))
            #expect(mapped.dropped == 0, "\(chunk.lastPathComponent) dropped an item")
        }
    }

    @Test func readStateMapsToIsRead() throws {
        let announcements = try AnnouncementMapper.map(Fixtures.data("personas/flagship/announcements.chunk1.json")).items
        #expect(announcements.first { $0.id == "2551006" }?.isRead == false) // unread
        #expect(announcements.first { $0.id == "2551002" }?.isRead == true)  // read
        #expect(announcements.first { $0.id == "2551002" }?.courseID == "51843")
    }

    @Test func announcementWithoutCourseContextIsDroppedAndCounted() throws {
        let json = #"[{"id":"1","title":"No context","read_state":"read"},{"id":"2","title":"Ok","read_state":"unread","context_code":"course_5"}]"#
        let mapped = try AnnouncementMapper.map(Data(json.utf8))
        #expect(mapped.dropped == 1 && mapped.items.map(\.id) == ["2"])
    }

    @Test func largePersonaHasTwoAnnouncementAndTwoCalendarChunks() throws {
        let announcementChunks = try bodies("personas/large", prefix: "announcements")
        let calendarChunks = try bodies("personas/large", prefix: "calendar_events")
        #expect(Set(announcementChunks.map(\.lastPathComponent)).isSuperset(of: [
            "announcements.chunk1.page1.json", "announcements.chunk1.page2.json", "announcements.chunk2.json",
        ]))
        #expect(Set(calendarChunks.map(\.lastPathComponent)) == ["calendar_events.chunk1.json", "calendar_events.chunk2.json"])
    }
}
