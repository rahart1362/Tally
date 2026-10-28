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

/// Idea 10's walk through the week's drafts, one system sheet at a time. Add moves on to the next
/// draft. Cancel with more still to go asks whether to skip that one and continue, or stop (owner,
/// 2026-10-27: Cancel used to open the next draft silently, which read as the sheet reopening by
/// itself). Pure, so a hosted test drives it without the system sheet.
struct WeekAddWalk {
    /// The draft the system sheet is showing, if any.
    private(set) var showing: CalendarEventDraft?
    /// The drafts still to walk through after `showing`.
    private(set) var remaining: [CalendarEventDraft] = []
    /// A cancel left more to go: the question waits for the sheet to finish closing, because
    /// presenting an alert while the sheet is still on its way out can fail.
    private(set) var questionPending = false
    /// The skip-or-stop question is on screen.
    private(set) var asksToSkipOrStop = false

    init(drafts: [CalendarEventDraft] = []) {
        var queue = drafts
        showing = queue.isEmpty ? nil : queue.removeFirst()
        remaining = queue
    }

    /// The system sheet closed: `added` when the student tapped Add. Closing the last draft, or
    /// closing when nothing is showing (a second report of the same close), asks nothing.
    mutating func finish(added: Bool) {
        guard showing != nil else { return }
        if added || remaining.isEmpty {
            showNext()
        } else {
            showing = nil
            questionPending = true
        }
    }

    /// The sheet's `onDismiss`: it is fully gone, so a pending question can show now.
    mutating func sheetDismissed() {
        guard questionPending else { return }
        questionPending = false
        asksToSkipOrStop = true
    }

    /// "Skip and Continue": leaves the cancelled draft out and opens the next one.
    mutating func skipAndContinue() {
        asksToSkipOrStop = false
        showNext()
    }

    /// "Stop Adding": ends the walk. Whatever the student already added stays in Calendar.
    mutating func stop() {
        asksToSkipOrStop = false
        questionPending = false
        showing = nil
        remaining = []
    }

    /// The alert closed (SwiftUI resets its binding around the button's own action).
    mutating func questionClosed() {
        asksToSkipOrStop = false
    }

    private mutating func showNext() {
        showing = remaining.isEmpty ? nil : remaining.removeFirst()
    }
}
