import Foundation
import Testing
import TallyDomain
import TallyTestSupport
@testable import TallyCanvasAPI

@Suite("Canvas dates and course mapping (fixtures)")
struct CourseMapperTests {
    private let host = "canvas.northfield.example"

    @Test func everyDateVariantParsesToTheDocumentedInstant() throws {
        let base = try #require(CanvasDate.parse("2026-09-28T13:00:00Z"))
        #expect(base == Date(timeIntervalSince1970: 1_790_600_400))
        #expect(CanvasDate.parse("2026-09-28T08:00:00-05:00") == base)
        #expect(CanvasDate.parse("2026-09-28T09:00:00-0400") == base)
        #expect(abs(CanvasDate.parse("2026-09-28T13:00:00.123Z")!.timeIntervalSince(base) - 0.123) < 1e-6)
        #expect(abs(CanvasDate.parse("2026-09-28T06:00:00.123456-07:00")!.timeIntervalSince(base) - 0.123456) < 1e-6)
        #expect(CanvasDate.parse("2026-09-28") == base.addingTimeInterval(-13 * 3600))
        #expect(CanvasDate.parse("2026-09-17 15:38:12 +0000") == Date(timeIntervalSince1970: 1_789_659_492))
        for bad in ["", "2026-13-01T00:00:00Z", "yesterday", "2026-09-28T25:00:00Z"] { #expect(CanvasDate.parse(bad) == nil) }
    }

    @Test(arguments: Fixtures.personas)
    func everyPersonaDecodes(_ persona: String) throws {
        let mapped = try CourseMapper.map(Fixtures.data("personas/\(persona)/courses.json"), host: host)
        #expect(mapped.dropped == 0)
        #expect(persona == "empty" ? mapped.items.isEmpty : !mapped.items.isEmpty)
    }

    @Test func flagshipMatchesTheMockupAndExpectedGrades() throws {
        let courses = try CourseMapper.map(Fixtures.data("personas/flagship/courses.json"), host: host).items
        let expected = try JSONSerialization.jsonObject(with: Fixtures.data("expected/grades/flagship.json")) as! [String: Any]
        let rows = expected["courses"] as! [[String: Any]]
        #expect(courses.count == 5 && rows.count == 5)
        for row in rows {
            let course = try #require(courses.first { $0.id.rawValue == row["course_id"] as? String })
            #expect(course.scores?.currentScore == row["current_score"] as? Double)
            #expect(course.scores?.currentGrade == row["current_grade"] as? String)
        }
        #expect(Set(courses.map(\.courseCode)).isSuperset(of: ["MATH 122", "BIO 101"]))
    }

    @Test func scenarioEdgeCases() throws {
        func load(_ name: String) throws -> Mapped<Course> { try CourseMapper.map(Fixtures.data("scenarios/courses/\(name).json"), host: host) }
        #expect(try load("hidden-final-grades").items.first?.gradeVisibility == .hiddenTotals)
        #expect(try load("large-ids").items.first?.id.rawValue == "184670000000012345")
        #expect(try load("multiple-enrollments").items.first?.scores?.currentScore == 86.0)
        let restricted = try load("access-restricted-by-date")
        #expect(restricted.dropped >= 1)
    }

    @Test func gradeEngineCourseFlags() throws {
        func course(_ name: String) throws -> Course { try #require(CourseMapper.map(Fixtures.data("scenarios/courses/\(name).json"), host: host).items.first) }
        let concluded = try course("concluded-course")
        #expect(concluded.studentEnrollmentCompleted && !concluded.hasWeightedGradingPeriods)
        let weighted = try course("weighted-grading-periods")
        #expect(weighted.hasWeightedGradingPeriods && !weighted.studentEnrollmentCompleted)
        #expect(try !course("unweighted-grading-periods").hasWeightedGradingPeriods)
        #expect(try !course("multiple-enrollments").studentEnrollmentCompleted)   // two active rows
        let flagship = try CourseMapper.map(Fixtures.data("personas/flagship/courses.json"), host: host).items
        #expect(flagship.allSatisfy { !$0.studentEnrollmentCompleted && !$0.hasWeightedGradingPeriods })
        let gradingPeriods = try CourseMapper.map(Fixtures.data("personas/grading-periods/courses.json"), host: host).items
        #expect(gradingPeriods.count == 4 && gradingPeriods.allSatisfy(\.hasWeightedGradingPeriods))
    }

    @Test func gradingPeriodsMapWeightsAndDates() throws {
        let periods = try GradingPeriodMapper.map(Fixtures.data("personas/grading-periods/grading_periods/90411.json"))
        #expect(periods.dropped == 0)
        #expect(periods.items.map(\.id) == ["2201", "2202", "2203"])
        #expect(periods.items.map(\.weight) == [40.0, 40.0, 20.0])
        #expect(periods.items.map(\.title) == ["Quarter 1", "Quarter 2", "Semester Exam"])
        let q1 = try #require(periods.items.first)
        #expect(q1.startDate == CanvasDate.parse("2026-08-17T04:00:00Z") && q1.endDate == CanvasDate.parse("2026-10-17T03:59:59Z"))
        #expect(q1.closeDate == CanvasDate.parse("2026-10-24T03:59:59Z") && !q1.isClosed)
        #expect(try GradingPeriodMapper.map(Fixtures.data("scenarios/grading_periods/none.json")).items.isEmpty)
        let undated = #"{"grading_periods":[{"id":"1","title":"No dates","weight":null},{"id":"2","start_date":"2026-01-01T00:00:00Z","end_date":"2026-02-01T00:00:00Z"}]}"#
        let mapped = try GradingPeriodMapper.map(Data(undated.utf8))
        #expect(mapped.dropped == 1 && mapped.items.map(\.id) == ["2"] && mapped.items[0].weight == nil)
    }
}
