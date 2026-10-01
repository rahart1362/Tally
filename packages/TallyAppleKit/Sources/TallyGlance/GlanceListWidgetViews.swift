import SwiftUI
import TallyDesignSystem
import TallyStrings
import WidgetKit

/// "Due soon" (insights-at-a-glance.md §1.5, Home medium): the next three open items, each with its
/// course code and due time, and how many more are coming or overdue. No grades.
///
/// The spec's per-row "Done" button is not here: marking done writes to the student's sealed user
/// state, which only the app may do, and the app-side half is outside this work package (see the
/// M3-D report). A row is laid out so the button can sit at its trailing edge.
public struct DueSoonWidgetView: View {
    private let entry: GlanceEntry

    public init(entry: GlanceEntry) {
        self.entry = entry
    }

    public var body: some View {
        GlanceHomeLayout(title: L10n.Widgets.headerDueSoon()) {
            switch entry.content {
            case .placeholder:
                GlancePlaceholderLines()
            case .message(let message):
                GlanceMessageText(message: message)
            case .summary(let summary):
                GlanceItemList(summary: summary, rows: GlanceMetrics.dueSoonRows)
            }
        }
    }
}

/// "Week ahead" (insights-at-a-glance.md §1.5, Home large): a seven-day strip with each day's count
/// of open items ("Busy" on a heavy day, "—" past what the glance holds), then the next five items.
public struct WeekAheadWidgetView: View {
    private let entry: GlanceEntry

    public init(entry: GlanceEntry) {
        self.entry = entry
    }

    public var body: some View {
        GlanceHomeLayout(title: L10n.Widgets.headerWeekAhead()) {
            switch entry.content {
            case .placeholder:
                GlancePlaceholderLines()
            case .message(let message):
                GlanceMessageText(message: message)
            case .summary(let summary):
                VStack(alignment: .leading, spacing: TallySpacing.sm) {
                    WeekStrip(days: summary.week)
                    GlanceItemList(summary: summary, rows: GlanceMetrics.weekAheadRows)
                }
            }
        }
    }
}

/// Up to `rows` upcoming items, one line for the title and one for the course and due time, then
/// the footer.
struct GlanceItemList: View {
    let summary: GlanceSummary
    let rows: Int
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let style = GlanceStyle(renderingMode)
        VStack(alignment: .leading, spacing: TallySpacing.xs) {
            if summary.upcoming.isEmpty {
                Text(verbatim: GlanceText.resolve(L10n.Widgets.nothingSoon(), TallyLocale.effective))
                    .font(TallyTypography.cardTitle)
                    .foregroundStyle(style.primary)
            } else {
                ForEach(summary.upcoming.prefix(rows)) { item in
                    GlanceItemRow(item: item, hidesNames: summary.hidesCourseNames)
                }
            }
            Spacer(minLength: 0)
            GlanceFooter(summary: summary, shown: min(rows, summary.upcoming.count))
        }
    }
}

struct GlanceItemRow: View {
    let item: GlanceSummary.Item
    let hidesNames: Bool
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let style = GlanceStyle(renderingMode)
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: GlanceText.title(item, hidesNames: hidesNames))
                .font(TallyTypography.subheadline.weight(.semibold))
                .foregroundStyle(style.primary)
                .lineLimit(1)
                .widgetAccentable()
            HStack(spacing: TallySpacing.xs) {
                if let code = GlanceText.courseCode(item, hidesNames: hidesNames) {
                    Text(verbatim: code)
                        .foregroundStyle(style.secondary)
                }
                Text(verbatim: GlanceText.dueLine(item, calendar: .autoupdatingCurrent))
                    .foregroundStyle(style.accent)
            }
            .font(TallyTypography.caption)
            .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Seven day columns: the weekday, the count of open items due, and "Busy" (with a warning symbol)
/// on a heavy day. The words and numbers carry the meaning, never a colour (UX-WP-38).
struct WeekStrip: View {
    let days: [GlanceSummary.Day]
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let style = GlanceStyle(renderingMode)
        HStack(alignment: .top, spacing: TallySpacing.xs) {
            ForEach(days, id: \.start) { day in
                VStack(spacing: GlanceMetrics.dayColumnSpacing) {
                    Text(verbatim: GlanceText.weekdayShort(day.start, calendar: .autoupdatingCurrent, locale: TallyLocale.effective))
                        .font(TallyTypography.caption)
                        .foregroundStyle(style.secondary)
                    Text(verbatim: GlanceText.dayCount(day))
                        .font(TallyTypography.cardTitle)
                        .foregroundStyle(style.primary)
                        .minimumScaleFactor(GlanceMetrics.dayCountMinimumScale)
                        .widgetAccentable()
                    if day.isBusy {
                        Label {
                            Text(verbatim: GlanceText.busy())
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                        }
                        .labelStyle(.titleAndIcon)
                        .font(TallyTypography.caption)
                        .foregroundStyle(style.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(GlanceMetrics.dayCountMinimumScale)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
    }
}
