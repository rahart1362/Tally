import Accessibility
import EventKit
import Foundation
import SwiftUI
import Testing
import TallyDomain
@testable import TallyFeatures

/// M3-A: what the screens hand to the system, tested here rather than by driving system UI (the
/// owner's guidance: never UI-test a system sheet such as `EKEventEditViewController`; test what
/// presents it). Hosted only: it needs SwiftUI, EventKit and Accessibility.
@Suite("M3-A: what the screens hand to the system")
@MainActor
struct ScreenPresenterTests {
    @Test("UX-WP-17: the day timeline is offered below the accessibility sizes and never at them")
    func timelineOnlyBelowTheAccessibilitySizes() {
        for size in DynamicTypeSize.allCases {
            #expect(CalendarScreen.offersTimeline(at: size) == !size.isAccessibilitySize, "\(size)")
        }
        #expect(CalendarScreen.offersTimeline(at: .large))
        #expect(!CalendarScreen.offersTimeline(at: .accessibility5))
    }

    @Test("R6: Add to Calendar opens the editor on the agenda item's own title, times, place and link")
    func addToCalendarEvent() async throws {
        let (_, screens) = try await ScreenFixtures.projections("flagship")
        let items = screens.calendar.days.flatMap(\.items)
        let due = try #require(items.first { $0.kind == .due && $0.title == "Problem Set 7" })
        let lecture = try #require(items.first { $0.title == "Calculus II Lecture" })
        #expect(lecture.draft.location == "Sage Hall 210")
        let store = EKEventStore()
        for draft in [due.draft, lecture.draft] {
            let event = AddToCalendarView.event(for: draft, in: store)
            #expect(event.title == draft.title)
            #expect(event.startDate == draft.start)
            #expect(event.endDate == draft.end)
            #expect(event.isAllDay == draft.isAllDay)
            #expect(event.location == draft.location)
            #expect(event.url == draft.url)
        }
    }

    @Test("A11Y-08: the category chart's Audio Graph has the chart's title, its sentence and a point per category")
    func categoryChartDescriptor() async throws {
        let (snapshot, screens) = try await ScreenFixtures.projections("flagship")
        let math = try #require(snapshot.courses.first { $0.courseCode == "MATH 122" })
        let detail = try #require(screens.courseDetails[math.id])
        let chart = CategoryChartDescriptor(title: "Category weights", summary: detail.weightsSummary,
                                           weights: detail.weights).makeChartDescriptor()
        #expect(chart.title == "Category weights")
        #expect(chart.summary == "Problem Sets 30%, Quizzes 20%, Exams 50%")
        #expect(chart.series.count == 1)
        #expect(chart.series.first?.dataPoints.count == 3)
    }

    @Test("A11Y-08: the trend's Audio Graph has its title, the range's sentence and a point per day")
    func trendChartDescriptor() {
        let start = ScreenFixtures.anchor.addingTimeInterval(-30 * 86_400)
        let view = TrendRangeView(points: [TrendPoint(date: start, percent: 86),
                                           TrendPoint(date: ScreenFixtures.anchor, percent: 88.3)],
                                  summary: "Up from 86.0 to 88.3 percent over the last month",
                                  start: start, end: ScreenFixtures.anchor, lowerPercent: 85, upperPercent: 90)
        let chart = TrendChartDescriptor(view: view).makeChartDescriptor()
        #expect(chart.title == "Performance trend")
        #expect(chart.summary == view.summary)
        #expect(chart.series.count == 1)
        #expect(chart.series.first?.dataPoints.count == 2)
    }
}
