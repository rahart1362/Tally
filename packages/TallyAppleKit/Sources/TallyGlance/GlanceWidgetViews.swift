import SwiftUI
import TallyDesignSystem
import TallyDomain
import TallyStore
import TallyStrings
import WidgetKit

/// The widget kinds, for `WidgetCenter.reloadTimelines(ofKind:)`.
public enum GlanceWidgetKind {
    /// "Next up". WP-E01's placeholder widget used this kind string, so a widget already placed on a
    /// Home Screen carries over.
    public static let nextUp = "TallyGlanceWidget"
    public static let standing = "TallyStandingWidget"
}

/// "Next up" (insights-at-a-glance.md §1.5, Home small): the next open item's title, course code
/// and due time, and how many more are coming or overdue. It never shows a grade.
public struct NextUpWidgetView: View {
    private let entry: GlanceEntry

    public init(entry: GlanceEntry) {
        self.entry = entry
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: TallySpacing.xs) {
            GlanceHeader(title: "Next up")
            switch entry.content {
            case .placeholder:
                GlancePlaceholderLines()
            case .message(let message):
                GlanceMessageText(message: message)
            case .summary(let summary):
                NextUpSummaryView(summary: summary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(TallyColor.bgBrand, for: .widget)
    }
}

/// "Standing" (insights-at-a-glance.md §1.5, Home small, opt-in): the overall grade band. The
/// glance carries a band only when the user chose to show grades in widgets (PMO R10,
/// `UserState.showGradesInGlance`), and the band is privacy-sensitive: hidden while the iPhone is
/// locked (`GradeBandBadge`). Without a band it says why (plan 08 §4.4 row 14): grades not shown
/// in widgets, no grades yet, or grades not kept in Canvas (`GlanceText.standingMessage`).
public struct StandingWidgetView: View {
    private let entry: GlanceEntry

    public init(entry: GlanceEntry) {
        self.entry = entry
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: TallySpacing.xs) {
            GlanceHeader(title: "Standing")
            switch entry.content {
            case .placeholder:
                GlancePlaceholderLines()
            case .message(let message):
                GlanceMessageText(message: message)
            case .summary(let summary):
                StandingSummaryView(summary: summary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(TallyColor.bgBrand, for: .widget)
    }
}

/// The one grade any widget shows. PMO R10: grades are opt-in (the glance has none otherwise) and
/// redacted while the iPhone is locked. Two layers: when the environment carries the `.privacy`
/// redaction reason (WidgetKit's locked rendering), the band is not drawn at all and a fixed,
/// readable "Hidden while locked" line takes its place, the same for every band; and the band text
/// itself is `.privacySensitive()`, so WidgetKit's own redaction also hides it.
struct GradeBandBadge: View {
    let band: GradeBand
    @Environment(\.redactionReasons) private var redactionReasons

    var body: some View {
        Group {
            if redactionReasons.contains(.privacy) {
                Label("Hidden while locked", systemImage: "lock.fill")
                    .font(TallyTypography.subheadline.weight(.semibold))
            } else {
                Text(GlanceText.bandLabel(band))
                    .font(TallyTypography.screenTitle)
                    .minimumScaleFactor(GlanceMetrics.bandMinimumScale)
                    .lineLimit(1)
                    .privacySensitive()
            }
        }
        .foregroundStyle(TallyColor.textOnHero)
    }
}

/// Copy, as pure functions, so tests can check it without rendering.
enum GlanceText {
    static func bandLabel(_ band: GradeBand) -> String {
        switch band {
        case .aRange: "A range"
        case .bRange: "B range"
        case .cRange: "C range"
        case .dRange: "D range"
        case .fRange: "F range"
        case .passing: "Passing"
        case .failing: "Not passing"
        case .unknown: "No grade"
        }
    }

    /// What the Standing widget says when it has no band to show (plan 08 §4.4 row 14), or nil
    /// when it has one. "Choose to show grades" only when the student has not opted in: an
    /// opted-in student with no band is told why instead.
    static func standingMessage(_ grades: GlanceGradeSummary) -> (title: LocalizedStringResource, detail: LocalizedStringResource)? {
        switch grades {
        case .band:
            return nil
        case .notOptedIn:
            return (title: L10n.Glance.standingHiddenTitle(), detail: L10n.Glance.standingHiddenDetail())
        case .noneYet:
            return (title: L10n.Glance.standingNoneYetTitle(), detail: L10n.Glance.standingNoneYetDetail())
        case .notInCanvas:
            return (title: L10n.Glance.standingNotInCanvasTitle(), detail: L10n.Glance.standingNotInCanvasDetail())
        }
    }

    static func message(_ message: GlanceMessage) -> String {
        switch message {
        case .signedOut, .unavailable: "Open Tally to see what's due."
        case .waitingForFirstSync: "Open Tally to update."
        case .locked: "Unlock your iPhone to see what's next."
        }
    }

    /// "+2 more · 1 overdue"; `nil` when both are zero.
    static func counts(later: Int, overdue: Int) -> String? {
        let parts = [later > 0 ? "+\(later) more" : nil, overdue > 0 ? "\(overdue) overdue" : nil].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

enum GlanceMetrics {
    static let headerMarkSize: CGFloat = 20
    static let titleLineLimit = 3
    static let bandMinimumScale: CGFloat = 0.6
    static let placeholderLineHeight: CGFloat = 10
    /// The placeholder's bars, as fractions of the widget's width, and how strongly they show.
    static let placeholderWidths: [CGFloat] = [0.9, 0.6, 0.75]
    static let placeholderOpacity = 0.35
}

private struct GlanceHeader: View {
    let title: LocalizedStringKey

    var body: some View {
        HStack(spacing: TallySpacing.xs) {
            TMark(size: GlanceMetrics.headerMarkSize)
            Text(title)
                .font(TallyTypography.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(TallyColor.textOnHero2)
        }
    }
}

private struct NextUpSummaryView: View {
    let summary: GlanceSummary

    var body: some View {
        VStack(alignment: .leading, spacing: TallySpacing.xs) {
            if let item = summary.nextUp {
                Text(item.title)
                    .font(TallyTypography.cardTitle)
                    .foregroundStyle(TallyColor.textOnHero)
                    .lineLimit(GlanceMetrics.titleLineLimit)
                if let code = item.courseCode {
                    Text(code)
                        .font(TallyTypography.caption)
                        .foregroundStyle(TallyColor.textOnHero2)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                DueLine(item: item)
            } else {
                Text("Nothing to do right now")
                    .font(TallyTypography.cardTitle)
                    .foregroundStyle(TallyColor.textOnHero)
                Spacer(minLength: 0)
            }
            GlanceFooter(summary: summary, counts: GlanceText.counts(later: summary.laterCount, overdue: summary.overdueCount))
        }
    }
}

private struct StandingSummaryView: View {
    let summary: GlanceSummary

    var body: some View {
        VStack(alignment: .leading, spacing: TallySpacing.xs) {
            if let band = summary.standing {
                Spacer(minLength: 0)
                GradeBandBadge(band: band)
                Text("Average of your courses")
                    .font(TallyTypography.footnote)
                    .foregroundStyle(TallyColor.textOnHero2)
            } else if let message = GlanceText.standingMessage(summary.grades) {
                Text(message.title)
                    .font(TallyTypography.cardTitle)
                    .foregroundStyle(TallyColor.textOnHero)
                Text(message.detail)
                    .font(TallyTypography.footnote)
                    .foregroundStyle(TallyColor.textOnHero2)
            }
            Spacer(minLength: 0)
            GlanceFooter(summary: summary, counts: nil)
        }
    }
}

/// "Due today, 6:00 PM", "Due tomorrow, 6:00 PM", "Due Tuesday, 6:00 PM" or "Due Oct 14", in the
/// user's locale. The day was worked out for this entry's date (`GlanceTimelinePlanner`).
private struct DueLine: View {
    let item: GlanceSummary.Item

    var body: some View {
        Group {
            switch item.day {
            case .today:
                Text("Due today, \(item.dueAt, format: .dateTime.hour().minute())")
            case .tomorrow:
                Text("Due tomorrow, \(item.dueAt, format: .dateTime.hour().minute())")
            case .thisWeek:
                Text("Due \(item.dueAt, format: .dateTime.weekday(.wide)), \(item.dueAt, format: .dateTime.hour().minute())")
            case .later:
                Text("Due \(item.dueAt, format: .dateTime.month(.abbreviated).day())")
            }
        }
        .font(TallyTypography.footnote.weight(.semibold))
        .foregroundStyle(TallyColor.brandGold)
        .lineLimit(1)
    }
}

/// The glance's age once it is stale ("As of 2:14 PM", with the weekday when it is from an earlier
/// day: insights-at-a-glance.md §1.5), otherwise the counts, if any.
private struct GlanceFooter: View {
    let summary: GlanceSummary
    let counts: String?

    var body: some View {
        Group {
            if summary.isStale {
                if summary.asOfIsBeforeToday {
                    Text("As of \(summary.asOf, format: .dateTime.weekday(.abbreviated).hour().minute())")
                } else {
                    Text("As of \(summary.asOf, format: .dateTime.hour().minute())")
                }
            } else if let counts {
                Text(counts)
            }
        }
        .font(TallyTypography.caption)
        .foregroundStyle(TallyColor.textOnHero2)
        .lineLimit(1)
    }
}

private struct GlanceMessageText: View {
    let message: GlanceMessage

    var body: some View {
        Text(GlanceText.message(message))
            .font(TallyTypography.subheadline)
            .foregroundStyle(TallyColor.textOnHero)
    }
}

/// The placeholder and gallery layout: bars where the text goes, and no text, so it can never read
/// as real data.
private struct GlancePlaceholderLines: View {
    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: TallySpacing.sm) {
                ForEach(Array(GlanceMetrics.placeholderWidths.enumerated()), id: \.offset) { _, fraction in
                    Capsule()
                        .frame(width: proxy.size.width * fraction, height: GlanceMetrics.placeholderLineHeight)
                }
            }
        }
        .foregroundStyle(TallyColor.textOnHero2.opacity(GlanceMetrics.placeholderOpacity))
        .accessibilityHidden(true)
    }
}
