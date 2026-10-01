import Foundation
import TallyDomain
import TallyStore

/// What the app's App Shortcuts answer (integrations.md §2.4: "What's due today?", "What's due
/// next?"), worked out from the glance the way the widgets work theirs out
/// (`GlanceTimelinePlanner`), so a spoken answer, a widget and the subscription seam
/// (`GlanceAccess`) always agree. The glance holds no grades unless the student opted in, and an
/// answer never uses them (PMO R10; integrations.md §2.4: "no intent returns grades by default").
public enum GlanceIntentAnswer: Equatable, Sendable {
    /// Nothing to answer from, and why (the same reasons the widgets show).
    case message(GlanceMessage)
    case list(GlanceAnswerList)
}

public struct GlanceAnswerList: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// The next open items, whatever day they are due.
        case dueNext
        /// The open items still due today.
        case dueToday
    }

    public let kind: Kind
    /// At most `GlanceIntentAnswers.listLimit`, earliest first.
    public let items: [GlanceSummary.Item]
    /// How many more of the same kind the glance holds after `items`.
    public let moreCount: Int
    /// The glance may hold only some of the later items (`GlanceSummary.laterIsLowerBound`).
    public let moreIsLowerBound: Bool
    public let overdueCount: Int
    public let hidesCourseNames: Bool
    public let asOf: Date
    public let isStale: Bool
    public let asOfIsBeforeToday: Bool
}

/// A course the Focus filter offers (integrations.md §2.6): its opaque Canvas ID and its short code,
/// the only course text the glance holds. FAM-11: an ID is a course within one student's glance;
/// M3-E2's student parameter says whose.
public struct GlanceCourseOption: Equatable, Sendable, Identifiable {
    public let id: String
    public let code: String

    public init(id: String, code: String) {
        self.id = id
        self.code = code
    }
}

public enum GlanceIntentAnswers {
    /// How many items a spoken answer reads out (insights-at-a-glance.md §1.5: "top 3").
    public static let listLimit = 3

    /// The glance's courses, once each, in Canvas's order; none when there is no glance, or when
    /// access does not cover the intents at `now` (`GlanceAccess`).
    public static func courses(_ result: GlanceReadResult, now: Date) -> [GlanceCourseOption] {
        guard case .loaded(let glance) = result, GlanceAccess.isUnlocked(glance, at: now) else { return [] }
        var seen = Set<String>()
        return glance.courses.compactMap { course in
            seen.insert(course.id.rawValue).inserted ? GlanceCourseOption(id: course.id.rawValue, code: course.shortCode) : nil
        }
    }

    public static func dueNext(_ result: GlanceReadResult, now: Date, calendar: Calendar,
                               limit: Int = listLimit) -> GlanceIntentAnswer {
        answer(result, now: now, calendar: calendar, kind: .dueNext, limit: limit)
    }

    public static func dueToday(_ result: GlanceReadResult, now: Date, calendar: Calendar,
                                limit: Int = listLimit) -> GlanceIntentAnswer {
        answer(result, now: now, calendar: calendar, kind: .dueToday, limit: limit)
    }

    static func answer(_ result: GlanceReadResult, now: Date, calendar: Calendar, kind: GlanceAnswerList.Kind,
                       limit: Int) -> GlanceIntentAnswer {
        switch GlanceTimelinePlanner.plan(for: result, now: now, calendar: calendar).current.content {
        case .placeholder:
            return .message(.unavailable)
        case .message(let message):
            return .message(message)
        case .summary(let summary):
            let candidates = kind == .dueToday ? summary.upcoming.filter { $0.day == .today } : summary.upcoming
            let shown = Array(candidates.prefix(max(limit, 0)))
            return .list(GlanceAnswerList(
                kind: kind, items: shown, moreCount: candidates.count - shown.count,
                moreIsLowerBound: summary.laterIsLowerBound && kind == .dueNext, overdueCount: summary.overdueCount,
                hidesCourseNames: summary.hidesCourseNames, asOf: summary.asOf, isStale: summary.isStale,
                asOfIsBeforeToday: summary.asOfIsBeforeToday))
        }
    }
}
