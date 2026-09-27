import Foundation
import TallyDomain

/// The minimum endpoint set (architecture §3.3) and the scope string an institution admin
/// grants for each one on a scoped developer key.
public enum CanvasScopes {
    public static let profile = "url:GET|/api/v1/users/:user_id/profile"
    public static let courses = "url:GET|/api/v1/courses"
    public static let assignmentGroups = "url:GET|/api/v1/courses/:course_id/assignment_groups"
    /// UNVERIFIED string (architecture §3.3): the docs page lists it, but no scoped key was tested.
    public static let gradingPeriods = "url:GET|/api/v1/courses/:course_id/grading_periods"
    public static let plannerItems = "url:GET|/api/v1/planner/items"
    public static let calendarEvents = "url:GET|/api/v1/calendar_events"
    public static let announcements = "url:GET|/api/v1/announcements"
    public static let colors = "url:GET|/api/v1/users/:id/colors"

    /// The 8 scopes requested for a student's own data (excludes institution search,
    /// which is unauthenticated, and token revocation, which needs no scope).
    public static let all: [String] = [profile, courses, assignmentGroups, gradingPeriods,
                                       plannerItems, calendarEvents, announcements, colors]
}

/// One entry in the endpoint catalogue: which snapshot section an endpoint feeds, which
/// drives the §3.2 partial-failure policy (required sections are all-or-nothing).
public struct CanvasEndpointDescriptor: Sendable, Equatable {
    public let name: String
    public let scope: String
    public let section: SnapshotSection
}

public enum CanvasEndpointCatalogue {
    public static let all: [CanvasEndpointDescriptor] = [
        .init(name: "profile", scope: CanvasScopes.profile, section: .profile),
        .init(name: "courses", scope: CanvasScopes.courses, section: .courses),
        .init(name: "assignment_groups", scope: CanvasScopes.assignmentGroups, section: .assignmentGroups),
        .init(name: "grading_periods", scope: CanvasScopes.gradingPeriods, section: .gradingPeriods),
        .init(name: "planner_items", scope: CanvasScopes.plannerItems, section: .planner),
        .init(name: "calendar_events", scope: CanvasScopes.calendarEvents, section: .events),
        .init(name: "announcements", scope: CanvasScopes.announcements, section: .announcements),
        .init(name: "colors", scope: CanvasScopes.colors, section: .colors),
    ]
}

/// `context_codes[]=course_…`, at most `TallyConfig.contextCodesPerRequest` per request
/// (calendar events and announcements, architecture §3.3). Chunks are cut from the courses
/// list in the order Canvas returned it (not re-sorted), matching how a real client would
/// walk the array it already has; this is also the order the `large` fixture was recorded in.
public enum ContextCodeChunker {
    public static func chunks(for courseIDs: [CanvasID<Course>],
                              size: Int = TallyConfig.contextCodesPerRequest) -> [[String]] {
        guard size > 0, !courseIDs.isEmpty else { return [] }
        return stride(from: 0, to: courseIDs.count, by: size).map { start in
            courseIDs[start..<min(start + size, courseIDs.count)].map { "course_\($0.rawValue)" }
        }
    }
}

/// Calendar-day arithmetic in UTC for the planner/calendar/announcement request windows
/// (architecture §3.3; the fixtures' README confirms the calendar-event window reuses the
/// planner window, and dates are plain `yyyy-MM-dd`, never a timestamp).
public enum CanvasDateWindow {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    public static func dateString(_ date: Date, offsetDays: Int) -> String {
        let shifted = calendar.date(byAdding: .day, value: offsetDays, to: date) ?? date
        let c = calendar.dateComponents([.year, .month, .day], from: shifted)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// The exact query for each endpoint (architecture §3.3's request column). Pair order never
/// matters for a real Canvas request or for `ReplayTransport` (both normalize before matching).
public enum CanvasQuery {
    public static func courses() -> [(String, String)] {
        [("enrollment_state", "active"), ("include[]", "current_grading_period_scores"),
         ("include[]", "teachers"), ("include[]", "term"), ("include[]", "total_scores"), ("per_page", "100")]
    }

    public static func assignmentGroups() -> [(String, String)] {
        [("include[]", "assignments"), ("include[]", "submission"), ("per_page", "100")]
    }

    public static func plannerItems(start: String, end: String) -> [(String, String)] {
        [("start_date", start), ("end_date", end), ("per_page", "100")]
    }

    public static func calendarEvents(contextCodes: [String], start: String, end: String) -> [(String, String)] {
        contextCodes.map { ("context_codes[]", $0) } + [("end_date", end), ("per_page", "100"),
                                                        ("start_date", start), ("type", "event")]
    }

    /// `per_page=50` (architecture §3.3 row 7); no `end_date` — announcements are an
    /// open-ended "since" window, not a bounded one.
    public static func announcements(contextCodes: [String], start: String) -> [(String, String)] {
        contextCodes.map { ("context_codes[]", $0) } + [("per_page", "50"), ("start_date", start)]
    }
}
