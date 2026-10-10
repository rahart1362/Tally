import SwiftUI
import TallyDesignSystem
import TallyStore
import TallyStrings
import WidgetKit

/// "Due soon" (insights-at-a-glance.md §1.5, Home medium): the next three open items, each with its
/// course code and due time, and how many more are coming or overdue. No grades.
///
/// M3-D2 (m3d-report.md §6 option A): each row's trailing edge can carry a "Mark Done" button, but
/// this view never names `MarkDoneIntent` itself — that type lives in the Xcode target
/// (`TallyWidgets/Shared/`), compiled separately into the app and the widget extension so each can
/// supply its own `perform()`, and this package cannot depend on either target. `trailingButton`
/// is the injection point: the widget bundle (`TallyWidgets.swift`) passes a closure that builds the
/// real button, given the item's opaque ID and its already-localized, already-"Hide course names"
/// aware accessibility label (`GlanceText.title`, `L10n.Widgets.markDoneButton`), so the caller
/// needs no `TallyStrings` dependency of its own and can never show a title the row itself is
/// hiding. The default draws nothing, which is what every other caller (and every existing
/// snapshot) still gets.
public struct DueSoonWidgetView: View {
    private let entry: GlanceEntry
    private let trailingButton: (_ itemID: String, _ accessibilityLabel: String) -> AnyView

    public init(entry: GlanceEntry,
               trailingButton: @escaping (_ itemID: String, _ accessibilityLabel: String) -> AnyView = { _, _ in AnyView(EmptyView()) }) {
        self.entry = entry
        self.trailingButton = trailingButton
    }

    public var body: some View {
        GlanceHomeLayout(title: L10n.Widgets.headerDueSoon()) {
            switch entry.content {
            case .placeholder:
                GlancePlaceholderLines()
            case .message(let message):
                GlanceMessageText(message: message)
            case .summary(let summary):
                GlanceItemList(summary: summary, rows: GlanceMetrics.dueSoonRows, trailingButton: trailingButton)
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
                // D23: on a typical glance (a handful of upcoming items, nowhere near
                // `GlanceMetrics.weekAheadRows`), the large widget's content is naturally much
                // shorter than its 382 pt canvas. `GlanceItemList`'s own trailing `Spacer` already
                // reaches the widget's real bottom edge (so the footer was never adrift — it
                // landed on the last pixel, which is what the audit's own composited evidence
                // shows), but that put the *entire* ~100 pt+ of slack into one gap between the
                // last row and "N overdue", reading as a half-built widget. A second `Spacer`
                // between the strip and the list splits that one dead block into two smaller,
                // deliberate-looking gaps instead — "distribute the spacing" (`defects.md`), not
                // dependent on how many items a given glance happens to have.
                VStack(alignment: .leading, spacing: TallySpacing.sm) {
                    GlanceWeekStrip(days: summary.week)
                    Spacer(minLength: TallySpacing.lg)
                    GlanceItemList(summary: summary, rows: GlanceMetrics.weekAheadRows)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }
}

/// Up to `rows` upcoming items, one line for the title and one for the course and due time, then
/// the footer.
struct GlanceItemList: View {
    let summary: GlanceSummary
    let rows: Int
    var trailingButton: (_ itemID: String, _ accessibilityLabel: String) -> AnyView = { _, _ in AnyView(EmptyView()) }
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
                    GlanceItemRow(item: item, hidesNames: summary.hidesCourseNames, trailing: markDoneButton(for: item))
                }
            }
            Spacer(minLength: 0)
            GlanceFooter(summary: summary, shown: min(rows, summary.upcoming.count))
        }
    }

    /// The "Mark Done" button only on an assignment row: only an assignment can be marked done
    /// (`GlancePlannerID`), so a quiz, discussion or planner-note row shows no button rather than
    /// an inert one (owner, 2026-10-03; M3-D2 report O2).
    private func markDoneButton(for item: GlanceSummary.Item) -> AnyView {
        guard GlancePlannerID.assignmentID(item.id) != nil else { return AnyView(EmptyView()) }
        let title = GlanceText.title(item, hidesNames: summary.hidesCourseNames)
        return trailingButton(item.id, GlanceText.resolve(L10n.Widgets.markDoneButton(title), TallyLocale.effective))
    }
}

struct GlanceItemRow: View {
    let item: GlanceSummary.Item
    let hidesNames: Bool
    /// M3-D2: the "Mark Done" button, or nothing (`EmptyView`, the default). Laid out as a sibling
    /// of the title/course/due-time group, never inside its `.accessibilityElement(children:
    /// .combine)`, so VoiceOver can still reach the button as its own stop.
    var trailing: AnyView = AnyView(EmptyView())
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let style = GlanceStyle(renderingMode)
        HStack(alignment: .firstTextBaseline, spacing: TallySpacing.xs) {
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
            Spacer(minLength: 0)
            trailing
        }
    }
}

/// Seven day columns: the weekday, the count of open items due, and "Busy" (with a warning symbol)
/// on a heavy day. The words and numbers carry the meaning, never a colour (UX-WP-38).
struct GlanceWeekStrip: View {
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
