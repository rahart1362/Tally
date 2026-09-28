import Foundation

/// A to-do/due item from the Canvas planner, with the student's submission flags.
public struct PlannerItem: Codable, Sendable, Equatable, Identifiable {
    public let id: String                 // "<plannable_type>:<plannable_id>", stable across refreshes
    public let courseID: CanvasID<Course>?
    public let title: String
    public let plannableType: String      // assignment, quiz, discussion_topic, planner_note, ...
    public let dueAt: Date?
    public let pointsPossible: Double?
    public let submitted: Bool
    public let graded: Bool
    public let missing: Bool
    public let late: Bool
    public let excused: Bool
    public let markedComplete: Bool       // the student's own planner override
    public let htmlURL: URL?

    public init(id: String, courseID: CanvasID<Course>?, title: String, plannableType: String, dueAt: Date?,
                pointsPossible: Double?, submitted: Bool, graded: Bool, missing: Bool, late: Bool,
                excused: Bool, markedComplete: Bool, htmlURL: URL?) {
        self.id = id; self.courseID = courseID; self.title = title; self.plannableType = plannableType
        self.dueAt = dueAt; self.pointsPossible = pointsPossible; self.submitted = submitted; self.graded = graded
        self.missing = missing; self.late = late; self.excused = excused
        self.markedComplete = markedComplete; self.htmlURL = htmlURL
    }
}

public struct CalendarEvent: Codable, Sendable, Equatable, Identifiable {
    public let id: CanvasID<CalendarEvent>
    public let courseID: CanvasID<Course>?
    public let title: String
    public let startAt: Date
    public let endAt: Date?
    public let allDay: Bool
    public let locationName: String?
    public let htmlURL: URL?

    public init(id: CanvasID<CalendarEvent>, courseID: CanvasID<Course>?, title: String, startAt: Date,
                endAt: Date?, allDay: Bool, locationName: String?, htmlURL: URL?) {
        self.id = id; self.courseID = courseID; self.title = title; self.startAt = startAt
        self.endAt = endAt; self.allDay = allDay; self.locationName = locationName; self.htmlURL = htmlURL
    }
}

public struct Announcement: Codable, Sendable, Equatable, Identifiable {
    public let id: CanvasID<Announcement>
    public let courseID: CanvasID<Course>
    public let title: String
    public let postedAt: Date?
    public let isRead: Bool
    public let htmlURL: URL?

    public init(id: CanvasID<Announcement>, courseID: CanvasID<Course>, title: String, postedAt: Date?, isRead: Bool, htmlURL: URL?) {
        self.id = id; self.courseID = courseID; self.title = title; self.postedAt = postedAt
        self.isRead = isRead; self.htmlURL = htmlURL
    }
}

public struct UserProfile: Codable, Sendable, Equatable {
    public let id: CanvasID<UserProfile>
    public let name: String
    public let shortName: String?
    public let timeZone: String?
    /// The student's personal Canvas calendar feed (PMO R6: calendar subscription).
    public let calendarFeedURL: URL?

    public init(id: CanvasID<UserProfile>, name: String, shortName: String?, timeZone: String?, calendarFeedURL: URL?) {
        self.id = id; self.name = name; self.shortName = shortName; self.timeZone = timeZone
        self.calendarFeedURL = calendarFeedURL
    }
}
