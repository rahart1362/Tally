import Foundation
import TallyDomain

/// Produces one account's sealed snapshot from Canvas (architecture §3.3). `previous` is
/// only ever read, never mutated; on a fully successful fetch its optional sections are
/// simply replaced, and on a partial failure they seed the carry-forward values.
public protocol CanvasGateway: Sendable {
    func fetchSnapshot(previous: CanvasSnapshot?, now: Date) async throws -> CanvasSnapshot
}

/// The live `CanvasGateway`: composes `CanvasClient` calls per the endpoint catalogue and
/// applies the §3.2 partial-failure policy. Required sections (profile, courses, assignment
/// groups for every active course, planner) are all-or-nothing: the first failure among them
/// propagates and no snapshot is produced. Optional sections (grading periods, calendar
/// events, announcements, colors) are attempted independently; a failing one carries its
/// value forward from `previous`, flagged `carriedForward` with `previous`'s own section
/// timestamp, per architecture §3.2 ("flagged carriedForward with its own timestamp").
///
/// `generation` is `(previous?.generation ?? 0) + 1`: a placeholder monotonic counter. The
/// refresh coordinator (TallySync, out of this work package's scope) owns the real generation
/// and epoch bookkeeping (architecture §3.4) and may need to re-stamp the value this returns.
public actor LiveCanvasGateway: CanvasGateway {
    private let host: String
    private let accountKey: AccountKey
    private let client: CanvasClient

    public init(host: String, accountKey: AccountKey, client: CanvasClient) {
        self.host = host
        self.accountKey = accountKey
        self.client = client
    }

    public func fetchSnapshot(previous: CanvasSnapshot?, now: Date) async throws -> CanvasSnapshot {
        // Required: all-or-nothing. The first failure here propagates and nothing is returned.
        let profile = try await fetchProfile()
        let courses = try await fetchCourses()
        let groups = try await fetchAssignmentGroups(for: courses)
        let planner = try await fetchPlanner(now: now)

        // Optional: each attempted independently; a failure carries the previous value forward.
        async let gradingPeriodsResult = optionalSection(.gradingPeriods, previous: previous, now: now,
                                                          previousValue: { $0.gradingPeriods }, emptyValue: [:]) {
            try await self.fetchGradingPeriods(for: courses)
        }
        async let eventsResult = optionalSection(.events, previous: previous, now: now,
                                                 previousValue: { $0.events }, emptyValue: []) {
            try await self.fetchCalendarEvents(for: courses, now: now)
        }
        async let announcementsResult = optionalSection(.announcements, previous: previous, now: now,
                                                         previousValue: { $0.announcements }, emptyValue: []) {
            try await self.fetchAnnouncements(for: courses, now: now)
        }
        async let colorsResult = optionalSection(.colors, previous: previous, now: now,
                                                 previousValue: { $0.courseColors }, emptyValue: [:]) {
            try await self.fetchColors()
        }
        let (gradingPeriods, gradingPeriodsStatus) = await gradingPeriodsResult
        let (events, eventsStatus) = await eventsResult
        let (announcements, announcementsStatus) = await announcementsResult
        let (colors, colorsStatus) = await colorsResult

        let sections: [SnapshotSection: SectionStatus] = [
            .profile: SectionStatus(fetchedAt: now, carriedForward: false),
            .courses: SectionStatus(fetchedAt: now, carriedForward: false),
            .assignmentGroups: SectionStatus(fetchedAt: now, carriedForward: false),
            .planner: SectionStatus(fetchedAt: now, carriedForward: false),
            .gradingPeriods: gradingPeriodsStatus,
            .events: eventsStatus,
            .announcements: announcementsStatus,
            .colors: colorsStatus,
        ]

        return CanvasSnapshot(generation: (previous?.generation ?? 0) + 1, accountKey: accountKey, host: host, fetchedAt: now,
                              profile: profile, courses: courses, groups: groups, gradingPeriods: gradingPeriods,
                              planner: planner, events: events, announcements: announcements, courseColors: colors,
                              sections: sections)
    }

    // MARK: Required sections

    private func fetchProfile() async throws -> UserProfile {
        let data = try await client.fetchOne(path: "/api/v1/users/self/profile")
        return try mapOrContract(data) { try ProfileMapper.map($0) }
    }

    private func fetchCourses() async throws -> [Course] {
        let pages = try await client.fetchAllPages(path: "/api/v1/courses", query: CanvasQuery.courses())
        return try pages.flatMap { page in try mapOrContract(page) { try CourseMapper.map($0, host: host).items } }
    }

    private func fetchAssignmentGroups(for courses: [Course]) async throws -> [CanvasID<Course>: [AssignmentGroup]] {
        var groups: [CanvasID<Course>: [AssignmentGroup]] = [:]
        for course in courses {
            let pages = try await client.fetchAllPages(path: "/api/v1/courses/\(course.id.rawValue)/assignment_groups",
                                                       query: CanvasQuery.assignmentGroups())
            groups[course.id] = try pages.flatMap { page in
                try mapOrContract(page) { try AssignmentGroupMapper.map($0, courseID: course.id).items }
            }
        }
        return groups
    }

    private func fetchPlanner(now: Date) async throws -> [PlannerItem] {
        let start = CanvasDateWindow.dateString(now, offsetDays: TallyConfig.plannerWindowDays.lowerBound)
        let end = CanvasDateWindow.dateString(now, offsetDays: TallyConfig.plannerWindowDays.upperBound)
        let pages = try await client.fetchAllPages(path: "/api/v1/planner/items",
                                                   query: CanvasQuery.plannerItems(start: start, end: end))
        return try pages.flatMap { page in try mapOrContract(page) { try PlannerItemMapper.map($0, host: host).items } }
    }

    // MARK: Optional sections

    private func fetchGradingPeriods(for courses: [Course]) async throws -> [CanvasID<Course>: [GradingPeriod]] {
        var result: [CanvasID<Course>: [GradingPeriod]] = [:]
        for course in courses where course.hasGradingPeriods {
            let data = try await client.fetchOne(path: "/api/v1/courses/\(course.id.rawValue)/grading_periods")
            result[course.id] = try mapOrContract(data) { try GradingPeriodMapper.map($0).items }
        }
        return result
    }

    private func fetchCalendarEvents(for courses: [Course], now: Date) async throws -> [CalendarEvent] {
        let start = CanvasDateWindow.dateString(now, offsetDays: TallyConfig.plannerWindowDays.lowerBound)
        let end = CanvasDateWindow.dateString(now, offsetDays: TallyConfig.plannerWindowDays.upperBound)
        var events: [CalendarEvent] = []
        for chunk in ContextCodeChunker.chunks(for: courses.map(\.id)) {
            let pages = try await client.fetchAllPages(path: "/api/v1/calendar_events",
                                                       query: CanvasQuery.calendarEvents(contextCodes: chunk, start: start, end: end))
            events += try pages.flatMap { page in try mapOrContract(page) { try CalendarEventMapper.map($0).items } }
        }
        return events
    }

    private func fetchAnnouncements(for courses: [Course], now: Date) async throws -> [Announcement] {
        let start = CanvasDateWindow.dateString(now, offsetDays: -TallyConfig.announcementWindowDays)
        var announcements: [Announcement] = []
        for chunk in ContextCodeChunker.chunks(for: courses.map(\.id)) {
            let pages = try await client.fetchAllPages(path: "/api/v1/announcements",
                                                       query: CanvasQuery.announcements(contextCodes: chunk, start: start))
            announcements += try pages.flatMap { page in try mapOrContract(page) { try AnnouncementMapper.map($0).items } }
        }
        return announcements
    }

    private func fetchColors() async throws -> [CanvasID<Course>: String] {
        let data = try await client.fetchOne(path: "/api/v1/users/self/colors")
        return try mapOrContract(data) { try UserColorMapper.map($0) }
    }

    // MARK: Helpers

    /// A mapper's own decode failure (malformed *required section*, architecture §3.3)
    /// is reported as `.contract`; a `RefreshFailure` from `CanvasClient` itself propagates as-is.
    private func mapOrContract<T>(_ data: Data, _ map: (Data) throws -> T) throws -> T {
        do { return try map(data) } catch { throw RefreshFailure.contract }
    }

    /// Runs one optional section's fetch; on failure, carries `previous`'s value and section
    /// timestamp forward (or an empty value with no previous snapshot to draw from).
    private func optionalSection<Value>(_ section: SnapshotSection, previous: CanvasSnapshot?, now: Date,
                                        previousValue: (CanvasSnapshot) -> Value, emptyValue: Value,
                                        fetch: () async throws -> Value) async -> (Value, SectionStatus) {
        do {
            let value = try await fetch()
            return (value, SectionStatus(fetchedAt: now, carriedForward: false))
        } catch {
            guard let previous else { return (emptyValue, SectionStatus(fetchedAt: now, carriedForward: false)) }
            let previousStatus = previous.sections[section] ?? SectionStatus(fetchedAt: previous.fetchedAt, carriedForward: false)
            return (previousValue(previous), SectionStatus(fetchedAt: previousStatus.fetchedAt, carriedForward: true))
        }
    }
}
