import Foundation
import TallyDomain

/// Settings' Account and Calendar rows (ux-ui.md §3.7.7): who is signed in, at which Canvas, and
/// the student's own calendar feed (PMO R6). Built off the main actor.
public nonisolated struct AccountProjection: Equatable, Sendable {
    /// The Canvas profile's name ("Signed in as …").
    public let displayName: String?
    /// The school's Canvas host ("canvas.northfield.example").
    public let host: String
    /// The student's own Canvas calendar feed, as a `webcal://` link.
    public let subscribeURL: URL?

    public static let empty = AccountProjection(displayName: nil, host: "", subscribeURL: nil)

    public static func build(from snapshot: CanvasSnapshot) -> AccountProjection {
        AccountProjection(displayName: snapshot.profile.name, host: snapshot.host,
                          subscribeURL: snapshot.profile.calendarFeedURL.flatMap(CalendarBuilder.webcal))
    }
}

/// Every M3 screen's projection of one snapshot, built together by `HomeProjector` off the main
/// actor (perf-app-runtime.md §3 item 4: views only read and format).
public nonisolated struct ScreenProjections: Equatable, Sendable {
    public let courseCards: [CourseCard]
    public let courseDetails: [CanvasID<Course>: CourseDetailProjection]
    public let toDo: ToDoProjection
    public let calendar: CalendarProjection
    public let insights: InsightsProjection
    public let account: AccountProjection

    public static let empty = ScreenProjections(
        courseCards: [], courseDetails: [:], toDo: .empty, calendar: .empty, insights: .empty, account: .empty)

    /// `gradeAvailability`: the projection's `GradeAvailabilityIndex` (plan 08 §4.3, built once
    /// by `HomeProjector`); `nil` classifies the snapshot at `formatter.now` with no override.
    public static func build(from snapshot: CanvasSnapshot, formatter: ScreenFormatter,
                             gradeAvailability: GradeAvailabilityIndex? = nil) -> ScreenProjections {
        // Plan 08 XG-03: one index for every screen (classified here when the caller has none).
        let index = gradeAvailability ?? GradeAvailabilityIndex(snapshot: snapshot, overrides: [:], now: formatter.now)
        return ScreenProjections(
            courseCards: CourseCardBuilder.cards(from: snapshot, formatter: formatter, gradeAvailability: index),
            courseDetails: CourseDetailBuilder.details(from: snapshot, formatter: formatter, gradeAvailability: index),
            toDo: ToDoBuilder.projection(from: snapshot, formatter: formatter, gradeAvailability: index),
            calendar: CalendarBuilder.projection(from: snapshot, formatter: formatter),
            insights: InsightsBuilder.projection(from: snapshot, formatter: formatter, gradeAvailability: index),
            account: AccountProjection.build(from: snapshot))
    }
}
