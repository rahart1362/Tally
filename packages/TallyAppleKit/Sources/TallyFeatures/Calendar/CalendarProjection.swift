import Foundation
import TallyDomain

/// What "Add to Calendar" pre-fills in the system's event editor (`EKEventEditViewController`,
/// PMO R6: no calendar permission prompt). Plain values, built off the main actor.
public nonisolated struct CalendarEventDraft: Identifiable, Equatable, Sendable {
    public var id: String { "\(title)|\(start.timeIntervalSince1970)" }
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let location: String?
    public let url: URL?
}

/// One agenda row (ux-ui.md §3.7.4, UX-WP-17): a class or event with its time range and place, or
/// an item due, with a conflict line when it overlaps something (icon plus text, never colour).
public nonisolated struct AgendaItem: Identifiable, Equatable, Sendable {
    public nonisolated enum Kind: String, Equatable, Sendable {
        case classMeeting, event, due
    }

    public let id: String
    public let kind: Kind
    public let title: String
    public let courseCode: String?
    public let paletteIndex: Int?
    /// "9:00 AM – 9:50 AM", "Due 11:59 PM" or "All day".
    public let timeText: String
    public let location: String?
    /// "Overlaps with BIO 101 Lab", or `nil`.
    public let conflictText: String?
    public let isExam: Bool
    public let isAllDay: Bool
    public let draft: CalendarEventDraft
    /// Minutes from the day's local midnight, and the length, for the day timeline.
    public let startMinute: Int
    public let durationMinutes: Int
    public let accessibilityLabel: String
}

public nonisolated struct AgendaDay: Identifiable, Equatable, Sendable {
    /// The day's local midnight.
    public let id: Date
    /// "Today · Mon, Sep 28" / "Tue, Sep 29".
    public let heading: String
    public let items: [AgendaItem]
    /// The day timeline's blocks: every item except all-day ones.
    public let timedItems: [AgendaItem]
    public let isToday: Bool
    /// The week strip: "28", "M", and 0...3 dots for how busy the day is.
    public let dayNumber: String
    public let weekdayLetter: String
    public let dotCount: Int
    /// "Monday, September 28, today, 4 items" (the week strip, for VoiceOver).
    public let stripLabel: String
    /// The first hour the day timeline shows: 8 AM, or earlier when something starts earlier.
    public let timelineStartHour: Int
}

public nonisolated struct CalendarProjection: Equatable, Sendable {
    /// The large title: the month of today ("September").
    public let monthTitle: String
    /// The week strip: the 7 days of this week, in the student's locale's week order.
    public let week: [AgendaDay]
    /// The agenda: this week and next, one section per day.
    public let days: [AgendaDay]
    /// Today's section, where the agenda opens.
    public let todayID: Date?
    /// The student's own Canvas calendar feed as a `webcal://` link (PMO R6), when Canvas gave one.
    public let subscribeURL: URL?

    public static let empty = CalendarProjection(monthTitle: "", week: [], days: [], todayID: nil, subscribeURL: nil)

    /// The agenda day `offset` days from `id` (from today when `id` is nil), or nil past either end
    /// of the agenda. The day pager that replaces the week strip at the accessibility sizes steps
    /// through the agenda with it.
    public func day(from id: Date?, offset: Int) -> AgendaDay? {
        guard let anchor = id ?? todayID, let start = days.firstIndex(where: { $0.id == anchor }) else { return nil }
        let target = start + offset
        return days.indices.contains(target) ? days[target] : nil
    }
}

/// Builds the Calendar tab from one snapshot (pure; unit-tested).
public nonisolated enum CalendarBuilder {
    /// Days in the agenda: this week and next.
    static let agendaDays = 14
    /// A due time is an instant; the day timeline gives it this much room.
    static let dueMarkerMinutes = 15
    /// The day timeline starts no later than this hour.
    static let defaultTimelineStartHour = 8
    /// Words that mark an exam (insights-at-a-glance.md §1.3 detection heuristic: `exam|midterm|
    /// final|test`, whole words). Heuristic accuracy is UNVERIFIED there too.
    static let examWords: Set<String> = ["exam", "exams", "midterm", "midterms", "final", "finals", "test", "tests"]

    public static func projection(from snapshot: CanvasSnapshot, formatter: ScreenFormatter) -> CalendarProjection {
        let calendar = formatter.calendar
        let today = calendar.startOfDay(for: formatter.now)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let dayStarts = (0..<agendaDays).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
        guard let first = dayStarts.first, let last = dayStarts.last,
              let windowEnd = calendar.date(byAdding: .day, value: 1, to: last) else {
            return .empty
        }

        var courseIndex: [CanvasID<Course>: (code: String, palette: Int)] = [:]
        for (index, course) in snapshot.courses.enumerated() where courseIndex[course.id] == nil {
            courseIndex[course.id] = (course.courseCode, index)
        }
        var entries = eventEntries(snapshot, window: first..<windowEnd, courses: courseIndex)
            + dueEntries(snapshot, window: first..<windowEnd, courses: courseIndex)
        entries.sort { $0.start != $1.start ? $0.start < $1.start : $0.id < $1.id }
        let conflicts = conflictTitles(entries)

        var byDay: [Date: [AgendaItem]] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.start)
            byDay[day, default: []].append(item(entry, conflicts: conflicts[entry.id] ?? [], formatter: formatter))
        }
        let days = dayStarts.map { dayStart in
            agendaDay(dayStart, items: byDay[dayStart] ?? [], isToday: dayStart == today, formatter: formatter)
        }
        return CalendarProjection(
            monthTitle: formatter.monthTitle(formatter.now), week: Array(days.prefix(7)), days: days,
            todayID: days.contains { $0.id == today } ? today : nil,
            subscribeURL: snapshot.profile.calendarFeedURL.flatMap(webcal))
    }

    // MARK: - Entries

    nonisolated struct Entry {
        let id: String
        let kind: AgendaItem.Kind
        let title: String
        let courseID: CanvasID<Course>?
        let course: (code: String, palette: Int)?
        let start: Date
        let end: Date?
        let isAllDay: Bool
        let location: String?
        let url: URL?
        let isExam: Bool
    }

    static func eventEntries(_ snapshot: CanvasSnapshot, window: Range<Date>,
                             courses: [CanvasID<Course>: (code: String, palette: Int)]) -> [Entry] {
        var seen = Set<CanvasID<CalendarEvent>>()
        return snapshot.events.compactMap { event in
            guard window.contains(event.startAt), seen.insert(event.id).inserted else { return nil }
            let course = event.courseID.flatMap { courses[$0] }
            let kind: AgendaItem.Kind = course != nil && !event.allDay ? .classMeeting : .event
            return Entry(id: "event:\(event.id.rawValue)", kind: kind, title: event.title, courseID: event.courseID,
                         course: course,
                         start: event.startAt, end: event.endAt, isAllDay: event.allDay, location: event.locationName,
                         url: event.htmlURL, isExam: isExam(event.title))
        }
    }

    static func dueEntries(_ snapshot: CanvasSnapshot, window: Range<Date>,
                           courses: [CanvasID<Course>: (code: String, palette: Int)]) -> [Entry] {
        var seen = Set<CanvasID<Assignment>>()
        var entries: [Entry] = []
        for course in snapshot.courses {
            for group in snapshot.groups[course.id] ?? [] {
                for assignment in group.assignments where assignment.published {
                    guard let due = assignment.dueAt, window.contains(due),
                          seen.insert(assignment.id).inserted else { continue }
                    entries.append(Entry(id: "due:\(assignment.id.rawValue)", kind: .due, title: assignment.name,
                                         courseID: course.id, course: courses[course.id], start: due, end: nil,
                                         isAllDay: false,
                                         location: nil, url: assignment.htmlURL, isExam: isExam(assignment.name)))
                }
            }
        }
        return entries
    }

    static func isExam(_ title: String) -> Bool {
        let words = title.lowercased().split { !$0.isLetter }.map(String.init)
        return words.contains(where: examWords.contains)
    }

    // MARK: - Conflicts (insights-at-a-glance.md §2.1 A8, `AlertEngine.scheduleConflicts`)

    /// For each entry, the titles of the entries it overlaps. Only overlaps involving a class or an
    /// event are shown: a due time during a class, or two meetings at once. Two due times close
    /// together are A8's "Info" case, which the agenda leaves to the overload warnings. A course's
    /// own due time inside its own class or event (a quiz taken in class, an exam's assignment at its
    /// exam session) is the same commitment, not a clash.
    static func conflictTitles(_ entries: [Entry]) -> [String: [String]] {
        let timed = entries.filter { !$0.isAllDay }
        let byID = Dictionary(timed.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let items = timed.map { AlertEngine.ScheduleItem(id: $0.id, start: $0.start, end: $0.end, isExam: $0.isExam) }
        var titles: [String: [String]] = [:]
        for alert in AlertEngine.scheduleConflicts(items) {
            guard case .scheduleConflict(let idA, let idB) = alert.kind,
                  let a = byID[idA], let b = byID[idB], a.end != nil || b.end != nil else { continue }
            let sameCourse = a.courseID != nil && a.courseID == b.courseID
            if sameCourse, a.kind == .due || b.kind == .due { continue }
            titles[a.id, default: []].append(label(b))
            titles[b.id, default: []].append(label(a))
        }
        return titles
    }

    private static func label(_ entry: Entry) -> String {
        guard let code = entry.course?.code, !entry.title.contains(code) else { return entry.title }
        return "\(code) \(entry.title)"
    }

    // MARK: - Rows and days

    static func item(_ entry: Entry, conflicts: [String], formatter: ScreenFormatter) -> AgendaItem {
        let calendar = formatter.calendar
        let dayStart = calendar.startOfDay(for: entry.start)
        // A due time is an instant: its block (timeline and "Add to Calendar") ends at the deadline.
        let marker = TimeInterval(dueMarkerMinutes * 60)
        let blockStart = entry.kind == .due ? max(dayStart, entry.start.addingTimeInterval(-marker)) : entry.start
        let blockEnd = entry.end ?? (entry.kind == .due ? entry.start : entry.start.addingTimeInterval(marker))
        let startMinute = max(0, Int(blockStart.timeIntervalSince(dayStart) / 60))
        let duration = max(dueMarkerMinutes, Int(blockEnd.timeIntervalSince(blockStart) / 60))

        let timeText: String
        let spokenTime: String
        if entry.isAllDay {
            timeText = "All day"
            spokenTime = "all day"
        } else if entry.kind == .due {
            timeText = "Due \(formatter.timeText(entry.start))"
            spokenTime = "due at \(formatter.timeText(entry.start))"
        } else if let endAt = entry.end {
            timeText = "\(formatter.timeText(entry.start)) – \(formatter.timeText(endAt))"
            spokenTime = "\(formatter.timeText(entry.start)) to \(formatter.timeText(endAt))"
        } else {
            timeText = formatter.timeText(entry.start)
            spokenTime = timeText
        }

        let conflictText: String? = conflicts.first.map { first in
            conflicts.count == 1 ? "Overlaps with \(first)" : "Overlaps with \(first) and \(conflicts.count - 1) more"
        }
        var spoken = [entry.title]
        if let code = entry.course?.code { spoken.append(code) }
        if entry.isExam { spoken.append("exam") }
        spoken.append(spokenTime)
        if let location = entry.location { spoken.append(location) }
        if let conflictText { spoken.append("conflict: \(conflictText)") }

        return AgendaItem(
            id: entry.id, kind: entry.kind, title: entry.title, courseCode: entry.course?.code,
            paletteIndex: entry.course?.palette, timeText: timeText, location: entry.location,
            conflictText: conflictText, isExam: entry.isExam, isAllDay: entry.isAllDay,
            draft: CalendarEventDraft(title: entry.course.map { "\($0.code): \(entry.title)" } ?? entry.title,
                                      start: blockStart, end: max(blockEnd, blockStart.addingTimeInterval(marker)),
                                      isAllDay: entry.isAllDay, location: entry.location, url: entry.url),
            startMinute: startMinute, durationMinutes: duration,
            accessibilityLabel: spoken.joined(separator: ", "))
    }

    static func agendaDay(_ dayStart: Date, items: [AgendaItem], isToday: Bool, formatter: ScreenFormatter) -> AgendaDay {
        let heading = formatter.dayHeading(dayStart)
        let count = items.count
        let spokenCount = count == 1 ? "1 item" : "\(count) items"
        var strip = [formatter.dayHeading(dayStart, spoken: true)]
        if isToday { strip.append("today") }
        strip.append(spokenCount)
        let earliestHour = items.filter { !$0.isAllDay }.map { $0.startMinute / 60 }.min() ?? defaultTimelineStartHour
        return AgendaDay(
            id: dayStart, heading: isToday ? "Today · \(heading)" : heading, items: items,
            timedItems: items.filter { !$0.isAllDay }, isToday: isToday,
            dayNumber: formatter.dayNumber(dayStart), weekdayLetter: formatter.weekdayLetter(dayStart),
            dotCount: min(3, count), stripLabel: strip.joined(separator: ", "),
            timelineStartHour: min(defaultTimelineStartHour, earliestHour))
    }

    /// `https://host/feeds/…ics` as `webcal://host/feeds/…ics`, which iOS hands to Calendar's own
    /// subscription flow (no calendar permission for Tally, PMO R6).
    static func webcal(_ feed: URL) -> URL? {
        guard var components = URLComponents(url: feed, resolvingAgainstBaseURL: false),
              components.scheme == "https" || components.scheme == "http" || components.scheme == "webcal" else { return nil }
        components.scheme = "webcal"
        return components.url
    }
}
