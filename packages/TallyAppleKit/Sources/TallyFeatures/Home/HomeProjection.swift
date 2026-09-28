import Foundation
import TallyDomain

/// Everything the Home shell renders for one snapshot generation (perf-app-runtime.md §2.2 rule 2):
/// small, `Equatable` values built off the main actor by `HomeProjector`, so a view body only
/// reads and formats, and an unchanged refresh re-renders nothing. No view ever holds the
/// `CanvasSnapshot` itself.
public nonisolated struct HomeProjection: Equatable, Sendable {
    public nonisolated enum Greeting: String, Equatable, Sendable {
        case morning, afternoon, evening
    }

    public nonisolated struct CourseRow: Identifiable, Equatable, Sendable {
        public let id: CanvasID<Course>
        public let code: String
        public let name: String
        /// `nil` when the course hides grades or has no current score.
        public let percent: Double?
        public let letterGrade: String?
    }

    public nonisolated struct EventRow: Identifiable, Equatable, Sendable {
        public let id: CanvasID<CalendarEvent>
        public let title: String
        public let startAt: Date
    }

    public nonisolated struct ToDoRow: Identifiable, Equatable, Sendable {
        public let id: String
        public let title: String
        public let dueAt: Date?
    }

    public let generation: UInt64
    public let dashboard: DashboardProjection
    public let studentDisplayName: String?
    public let greeting: Greeting
    /// Courses in Canvas order.
    public let courses: [CourseRow]
    /// Calendar events by start time.
    public let events: [EventRow]
    /// Planner items by due date (undated last).
    public let toDo: [ToDoRow]
    /// The earliest moment this projection can go stale on its own (a due date passes, the day
    /// or the greeting changes, an item enters a window, or `TallyConfig.dashboardMaxStaleness`).
    public let validUntil: Date

    public static let empty = HomeProjection(
        generation: 0, dashboard: .empty, studentDisplayName: nil, greeting: .morning,
        courses: [], events: [], toDo: [], validUntil: .distantFuture)
}
