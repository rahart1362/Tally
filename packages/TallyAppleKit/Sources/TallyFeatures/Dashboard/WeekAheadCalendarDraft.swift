import Foundation
import TallyDomain

/// Idea 10 ("Add this week to Calendar", `pmo-audit/.build-audit/ideas1/report.md`): the
/// Week-ahead strip's due items as the existing per-item sheet needs them
/// (`AddToCalendarView`/`EKEventEditViewController`, PMO R6 -- zero permission). Pure and
/// testable: no view, no system call. Lives beside `DashboardView` rather than
/// `CalendarProjection.swift` because its input is `DashboardProjection.WeekDay`, not the
/// Calendar tab's own (wider) agenda.
enum WeekAheadCalendarDraft {
    /// How long before the deadline the block starts, so it is never a zero-length event -- the
    /// same convention the Calendar tab's own due-item drafts use
    /// (`CalendarBuilder.dueMarkerMinutes`), duplicated here rather than shared across the two
    /// UI-only files it belongs to (`TallyDomain` cannot hold `CalendarEventDraft`: it is a
    /// `TallyFeatures` type, one layer up).
    static let leadMinutes = 15

    /// Every day's items, in day-then-time order (the order `DashboardProjection.WeekDay` already
    /// keeps), ready to walk one system sheet at a time.
    static func drafts(for days: [DashboardProjection.WeekDay], accountHost: String) -> [CalendarEventDraft] {
        days.flatMap(\.items).map { draft(for: $0, accountHost: accountHost) }
    }

    /// One due item's draft: the title with its course code (like the Calendar tab's own drafts),
    /// a short block ending at the deadline, and Canvas's own link — only when
    /// `CanvasLinkOpener.isSafe` clears it for `accountHost` (SEC2-04: `item.url` is Canvas-supplied,
    /// unvalidated `html_url`, the same class of risk SEC1-15 already gates before opening
    /// anything). No location: a due item has none (`DashboardProjection.WeekDayItem` carries no
    /// field for one).
    static func draft(for item: DashboardProjection.WeekDayItem, accountHost: String) -> CalendarEventDraft {
        let marker = TimeInterval(leadMinutes * 60)
        let title = item.courseCode.map { "\($0): \(item.title)" } ?? item.title
        let safeURL = item.url.flatMap { CanvasLinkOpener.isSafe($0, accountHost: accountHost) ? $0 : nil }
        return CalendarEventDraft(title: title, start: item.dueAt.addingTimeInterval(-marker), end: item.dueAt,
                                  isAllDay: false, location: nil, url: safeURL)
    }
}
