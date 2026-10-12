import SwiftUI
import TallyDesignSystem
import TallyStrings
import WidgetKit

// The Lock Screen accessories (insights-at-a-glance.md §1.5). PMO R10: no grade value ever appears
// in an accessory family. These views are built from the due items, the counts and the glance's
// age only; none of them reads `GlanceSummary.grades` or `courses` (a hosted test renders them
// with different grades and checks the pixels and the rendered text).

/// "Due today" (Lock `accessoryCircular`): a gauge whose centre is the number of open items still
/// due today; the ring fills as today's items are done (submitted or excused).
public struct DueTodayAccessoryView: View {
    private let entry: GlanceEntry
    // L10N-04 round 2 (gate-2 verdict, "Spanish widget renders"): see GlanceLocaleOverride.swift.
    @Environment(\.effectiveGlanceLocale) private var locale

    public init(entry: GlanceEntry) {
        self.entry = entry
    }

    public var body: some View {
        Group {
            switch entry.content {
            case .placeholder:
                TodayGauge(progress: 0, center: GlanceText.dash)
            case .message(let message):
                Text(verbatim: GlanceText.shortMessage(message, locale: locale))
                    .font(TallyTypography.caption)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(GlanceMetrics.accessoryMinimumScale)
            case .summary(let summary):
                TodayGauge(progress: summary.today.progress, center: GlanceText.number(summary.today.open, locale: locale))
            }
        }
        .containerBackground(for: .widget) {
            AccessoryWidgetBackground()
        }
    }
}

private struct TodayGauge: View {
    let progress: Double
    let center: String
    // L10N-04 round 2 (gate-2 verdict, "Spanish widget renders"): see GlanceLocaleOverride.swift.
    @Environment(\.effectiveGlanceLocale) private var locale

    var body: some View {
        Gauge(value: progress) {
            Text(verbatim: GlanceText.resolve(L10n.Widgets.dueTodayTitle(), locale))
        } currentValueLabel: {
            VStack(spacing: 0) {
                Text(verbatim: center)
                    .font(TallyTypography.sectionHeader)
                    .minimumScaleFactor(GlanceMetrics.accessoryMinimumScale)
                    .widgetAccentable()
                Text(verbatim: GlanceText.resolve(L10n.Widgets.todayCaption(), locale))
                    .font(TallyTypography.caption)
                    .minimumScaleFactor(GlanceMetrics.accessoryMinimumScale)
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }
}

/// "Next item" (Lock `accessoryRectangular`): "Lab Report 4", then "BIO 101 · 6:00 PM"; with "Hide
/// course names" on, "Assignment", then the time alone.
public struct NextItemAccessoryView: View {
    private let entry: GlanceEntry
    // L10N-04 round 2 (gate-2 verdict, "Spanish widget renders"): see GlanceLocaleOverride.swift.
    @Environment(\.effectiveGlanceLocale) private var locale

    public init(entry: GlanceEntry) {
        self.entry = entry
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch entry.content {
            case .placeholder:
                Capsule()
                    .frame(height: GlanceMetrics.placeholderLineHeight)
                    .opacity(GlanceMetrics.placeholderOpacity)
                    .accessibilityHidden(true)
            case .message(let message):
                Text(verbatim: GlanceText.shortMessage(message, locale: locale))
                    .font(TallyTypography.cardTitle)
                    .lineLimit(2)
            case .summary(let summary):
                if let item = summary.nextUp {
                    Text(verbatim: GlanceText.title(item, hidesNames: summary.hidesCourseNames, locale: locale))
                        .font(TallyTypography.cardTitle)
                        .lineLimit(2)
                        .widgetAccentable()
                    Text(verbatim: GlanceText.courseAndWhen(item, hidesNames: summary.hidesCourseNames,
                                                            calendar: .autoupdatingCurrent, locale: locale))
                        .font(TallyTypography.caption)
                        .lineLimit(1)
                } else {
                    Text(verbatim: GlanceText.resolve(L10n.Widgets.nothingSoon(), locale))
                        .font(TallyTypography.cardTitle)
                        .lineLimit(2)
                }
                if summary.isStale {
                    Text(verbatim: GlanceText.asOf(summary, calendar: .autoupdatingCurrent, locale: locale))
                        .font(TallyTypography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(for: .widget) {
            AccessoryWidgetBackground()
        }
    }
}

/// "Next due line" (Lock `accessoryInline`): "Next: Lab Report 4, 6:00 PM". One line of text; the
/// system styles and truncates it.
public struct NextDueInlineView: View {
    private let entry: GlanceEntry
    // L10N-04 round 2 (gate-2 verdict, "Spanish widget renders"): see GlanceLocaleOverride.swift.
    @Environment(\.effectiveGlanceLocale) private var locale

    public init(entry: GlanceEntry) {
        self.entry = entry
    }

    public var body: some View {
        Text(verbatim: line)
            .containerBackground(for: .widget) {
                Color.clear
            }
    }

    private var line: String {
        switch entry.content {
        case .placeholder:
            return GlanceText.dash
        case .message(let message):
            return GlanceText.shortMessage(message, locale: locale)
        case .summary(let summary):
            guard let item = summary.nextUp else { return GlanceText.resolve(L10n.Widgets.nothingSoon(), locale) }
            return GlanceText.inlineNext(item, hidesNames: summary.hidesCourseNames, calendar: .autoupdatingCurrent, locale: locale)
        }
    }
}

// MARK: - One view per widget kind, by family

/// The "Next up" kind: Home small (and StandBy), Lock Screen rectangular and inline.
public struct NextUpFamilyView: View {
    private let entry: GlanceEntry
    @Environment(\.widgetFamily) private var family

    public init(entry: GlanceEntry) {
        self.entry = entry
    }

    public var body: some View {
        switch family {
        case .accessoryRectangular:
            NextItemAccessoryView(entry: entry)
        case .accessoryInline:
            NextDueInlineView(entry: entry)
        default:
            NextUpWidgetView(entry: entry)
        }
    }
}

/// The "Standing" kind: Home small and medium.
public struct StandingFamilyView: View {
    private let entry: GlanceEntry
    @Environment(\.widgetFamily) private var family

    public init(entry: GlanceEntry) {
        self.entry = entry
    }

    public var body: some View {
        StandingWidgetView(entry: entry, family: family)
    }
}
