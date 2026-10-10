import SwiftUI
import TallyDesignSystem
import TallyDomain
import TallyStore
import TallyStrings
import WidgetKit

/// The widget kinds, for `WidgetCenter.reloadTimelines(ofKind:)`. A kind is a placed widget's
/// identity: never rename one (FAM-11 adds a configuration parameter, not a kind).
public enum GlanceWidgetKind {
    /// "Next up": Home small, and the Lock Screen's rectangular and inline accessories. WP-E01's
    /// placeholder widget used this kind string, so a widget already placed carries over.
    public static let nextUp = "TallyGlanceWidget"
    /// "Standing" (opt-in grades): Home small and medium.
    public static let standing = "TallyStandingWidget"
    /// "Due soon": Home medium.
    public static let dueSoon = "TallyDueSoonWidget"
    /// "Week ahead": Home large.
    public static let weekAhead = "TallyWeekAheadWidget"
    /// "Due today": the Lock Screen's circular gauge.
    public static let dueToday = "TallyDueTodayWidget"

    public static let all = [nextUp, standing, dueSoon, weekAhead, dueToday]
}

/// The Control Center controls' kinds (integrations.md §2.5).
public enum GlanceControlKind {
    public static let refresh = "TallyRefreshControl"
    public static let nextUp = "TallyNextUpControl"
}

/// "Next up" (insights-at-a-glance.md §1.5, Home small; StandBy shows it too): the next open
/// item's title, course code and due time, and how many more are coming or overdue. It never shows
/// a grade.
public struct NextUpWidgetView: View {
    private let entry: GlanceEntry

    public init(entry: GlanceEntry) {
        self.entry = entry
    }

    public var body: some View {
        GlanceHomeLayout(title: L10n.Widgets.headerNextUp()) {
            switch entry.content {
            case .placeholder:
                GlancePlaceholderLines()
            case .message(let message):
                GlanceMessageText(message: message)
            case .summary(let summary):
                NextUpSummaryView(summary: summary)
            }
        }
    }
}

/// "Standing" (insights-at-a-glance.md §1.5, opt-in): the overall grade band, with the Dashboard
/// hero's caption ("Average of 3 courses", "2 courses not included"); the medium size adds a row
/// per course, "—" for a course whose grades are not in Canvas (plan 08 XG-02). The glance carries
/// grades only when the user chose to show them in widgets (PMO R10, `UserState.showGradesInGlance`),
/// and every grade is privacy-sensitive: hidden while the iPhone is locked (`GradeBandBadge`).
/// Without a band it says why (plan 08 §4.4 row 14).
public struct StandingWidgetView: View {
    private let entry: GlanceEntry
    private let family: WidgetFamily
    @Environment(\.redactionReasons) private var redactionReasons

    /// `family` comes from the widget's environment (`StandingFamilyView`); tests pass it.
    public init(entry: GlanceEntry, family: WidgetFamily = .systemSmall) {
        self.entry = entry
        self.family = family
    }

    public var body: some View {
        GlanceHomeLayout(title: L10n.Widgets.headerStanding()) {
            switch entry.content {
            case .placeholder:
                GlancePlaceholderLines()
            case .message(let message):
                GlanceMessageText(message: message)
            case .summary(let summary):
                if family == .systemMedium, !redactionReasons.contains(.privacy), !summary.courses.isEmpty {
                    HStack(alignment: .top, spacing: TallySpacing.md) {
                        StandingSummaryView(summary: summary)
                        StandingCourseRows(courses: summary.courses)
                    }
                } else {
                    StandingSummaryView(summary: summary)
                }
            }
        }
    }
}

/// The one grade band a widget shows. PMO R10: grades are opt-in (the glance has none otherwise)
/// and redacted while the iPhone is locked. Two layers: when the environment carries the `.privacy`
/// redaction reason (WidgetKit's locked rendering), the band is not drawn at all and a fixed,
/// readable "Hidden while locked" line takes its place, the same for every band; and the band text
/// itself is `.privacySensitive()`, so WidgetKit's own redaction also hides it.
struct GradeBandBadge: View {
    let band: GradeBand
    @Environment(\.redactionReasons) private var redactionReasons
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        Group {
            if redactionReasons.contains(.privacy) {
                Label {
                    Text(verbatim: GlanceText.resolve(L10n.Widgets.hiddenWhileLocked(), TallyLocale.effective))
                } icon: {
                    Image(systemName: "lock.fill")
                }
                .font(TallyTypography.subheadline.weight(.semibold))
            } else {
                Text(verbatim: GlanceText.bandLabel(band))
                    .font(TallyTypography.screenTitle)
                    .minimumScaleFactor(GlanceMetrics.bandMinimumScale)
                    .lineLimit(1)
                    .privacySensitive()
                    .widgetAccentable()
            }
        }
        .foregroundStyle(GlanceStyle(renderingMode).primary)
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
    /// "Due soon" lists this many items (insights-at-a-glance.md §1.5: "3 items").
    static let dueSoonRows = 3
    /// "Week ahead" lists this many items under its strip ("top 5 items").
    static let weekAheadRows = 5
    /// The medium Standing widget lists at most this many courses.
    static let standingCourseRows = 4
    static let dayCountMinimumScale: CGFloat = 0.7
    /// The gap between a week-strip column's weekday, count and "Busy" lines.
    static let dayColumnSpacing: CGFloat = 2
    /// How far a Lock Screen accessory's text may shrink to fit before it truncates.
    static let accessoryMinimumScale: CGFloat = 0.6
}

/// The widgets' foreground styles per rendering mode (integrations.md §2.2, UX-WP-38). In full
/// colour, the brand palette; where the system tints the widget (accented on a tinted or clear Home
/// Screen and in StandBy, vibrant on the Lock Screen) it keeps only each view's opacity, so the
/// hierarchical styles carry the emphasis there, and words and codes carry the meaning: no colour
/// alone ever does.
struct GlanceStyle {
    let mode: WidgetRenderingMode

    init(_ mode: WidgetRenderingMode) {
        self.mode = mode
    }

    private var isFullColor: Bool { mode == .fullColor }

    var primary: AnyShapeStyle { isFullColor ? AnyShapeStyle(TallyColor.textOnHero) : AnyShapeStyle(.primary) }
    var secondary: AnyShapeStyle { isFullColor ? AnyShapeStyle(TallyColor.textOnHero2) : AnyShapeStyle(.secondary) }
    /// The due line and the busy marker: gold in full colour, plain emphasis otherwise.
    var accent: AnyShapeStyle { isFullColor ? AnyShapeStyle(TallyColor.brandGold) : AnyShapeStyle(.primary) }
}

/// The Home widgets' frame: the T-mark header, the content, and the brand background, which the
/// system removes in StandBy and on a tinted or clear Home Screen (keep it a container background).
struct GlanceHomeLayout<Content: View>: View {
    let title: LocalizedStringResource
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: TallySpacing.xs) {
            GlanceHeader(title: title)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(TallyColor.bgBrand, for: .widget)
    }
}

private struct GlanceHeader: View {
    let title: LocalizedStringResource
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        HStack(spacing: TallySpacing.xs) {
            TMark(size: GlanceMetrics.headerMarkSize)
                .widgetAccentable()
            Text(verbatim: GlanceText.resolve(title, TallyLocale.effective))
                .font(TallyTypography.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(GlanceStyle(renderingMode).secondary)
        }
    }
}

private struct NextUpSummaryView: View {
    let summary: GlanceSummary
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let style = GlanceStyle(renderingMode)
        VStack(alignment: .leading, spacing: TallySpacing.xs) {
            if let item = summary.nextUp {
                Text(verbatim: GlanceText.title(item, hidesNames: summary.hidesCourseNames))
                    .font(TallyTypography.cardTitle)
                    .foregroundStyle(style.primary)
                    .lineLimit(GlanceMetrics.titleLineLimit)
                    .widgetAccentable()
                if let code = GlanceText.courseCode(item, hidesNames: summary.hidesCourseNames) {
                    Text(verbatim: code)
                        .font(TallyTypography.caption)
                        .foregroundStyle(style.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                GlanceDueLine(item: item)
            } else {
                Text(verbatim: GlanceText.resolve(L10n.Widgets.nothingNow(), TallyLocale.effective))
                    .font(TallyTypography.cardTitle)
                    .foregroundStyle(style.primary)
                Spacer(minLength: 0)
            }
            GlanceFooter(summary: summary, shown: 1)
        }
    }
}

private struct StandingSummaryView: View {
    let summary: GlanceSummary
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let style = GlanceStyle(renderingMode)
        VStack(alignment: .leading, spacing: TallySpacing.xs) {
            if let band = summary.standing {
                Spacer(minLength: 0)
                GradeBandBadge(band: band)
                // N1: at the small widget's real 16 pt margins, a single line truncates
                // "N courses not included" ("3 courses not includ…"). Copy is frozen, so this
                // wraps instead of shortening or cutting it off: `lineLimit(2)` on both captions
                // (either one can be the long one, depending on the student's course count), plus
                // `layoutPriority(1)` so the two `Spacer(minLength: 0)`s in this VStack (above the
                // badge, below the captions) give up their space to a caption that needs a second
                // line before the caption itself is squeezed down to one and forced to truncate.
                // `layoutPriority` alone (without it, confirmed on the smallest phone's 158 pt
                // widget — narrower than Pro Max's 170 pt, so "Average of N courses" needs 2 lines
                // there too): the two default-priority `Spacer`s and the captions were negotiated
                // together, and a `Spacer(minLength: 0)` doesn't reliably reach its floor of 0
                // first just because its minimum is lower — it only does when nothing else outranks
                // it. Confirmed by measuring the smallest-phone render's own row bands before this
                // fix: the gap above the badge held onto ~16 pt it didn't need, while "Average of 2
                // courses" below was squeezed to one line and truncated.
                ForEach(GlanceText.standingCaptions(summary), id: \.self) { caption in
                    Text(verbatim: caption)
                        .font(TallyTypography.footnote)
                        .foregroundStyle(style.secondary)
                        .lineLimit(2)
                        .layoutPriority(1)
                }
            } else if let message = GlanceText.standingMessage(summary.grades) {
                if summary.grades == .notInCanvas {
                    // Plan 08 §4.5: the dash, then the caption.
                    Text(verbatim: GlanceText.dash)
                        .font(TallyTypography.screenTitle)
                        .foregroundStyle(style.primary)
                }
                Text(message.title)
                    .font(TallyTypography.cardTitle)
                    .foregroundStyle(style.primary)
                Text(message.detail)
                    .font(TallyTypography.footnote)
                    .foregroundStyle(style.secondary)
            }
            Spacer(minLength: 0)
            GlanceFooter(summary: summary, shown: nil)
        }
    }
}

/// The medium Standing widget's course rows: the course code, then its band or "—" with why.
/// Drawn only while the widget is not redacted for privacy (`StandingWidgetView`); each band is
/// privacy-sensitive as well.
private struct StandingCourseRows: View {
    let courses: [GlanceSummary.CourseStanding]
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let style = GlanceStyle(renderingMode)
        VStack(alignment: .leading, spacing: TallySpacing.xs) {
            ForEach(courses.prefix(GlanceMetrics.standingCourseRows)) { course in
                let value = GlanceText.courseValue(course.value)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: TallySpacing.xs) {
                        Text(verbatim: course.code)
                            .font(TallyTypography.caption.weight(.semibold))
                            .foregroundStyle(style.secondary)
                            .lineLimit(1)
                        Spacer(minLength: TallySpacing.xs)
                        Text(verbatim: value.value)
                            .font(TallyTypography.caption.weight(.semibold))
                            .foregroundStyle(style.primary)
                            .lineLimit(1)
                            .privacySensitive()
                    }
                    if let caption = value.caption {
                        Text(verbatim: caption)
                            .font(TallyTypography.caption)
                            .foregroundStyle(style.secondary)
                            .lineLimit(1)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// "Due today, 6:00 PM", "Due tomorrow, 6:00 PM", "Due Tuesday, 6:00 PM" or "Due Oct 14", in the
/// user's locale. The day was worked out for this entry's date (`GlanceTimelinePlanner`).
struct GlanceDueLine: View {
    let item: GlanceSummary.Item
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        Text(verbatim: GlanceText.dueLine(item, calendar: .autoupdatingCurrent))
            .font(TallyTypography.footnote.weight(.semibold))
            .foregroundStyle(GlanceStyle(renderingMode).accent)
            .lineLimit(1)
    }
}

/// The glance's age once it is stale ("As of 2:14 PM", with the weekday when it is from an earlier
/// day: insights-at-a-glance.md §1.5), otherwise the counts after the `shown` items, if any
/// (`shown` nil: no counts, as on the Standing widget).
struct GlanceFooter: View {
    let summary: GlanceSummary
    let shown: Int?
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        if let text = footerText {
            Text(verbatim: text)
                .font(TallyTypography.caption)
                .foregroundStyle(GlanceStyle(renderingMode).secondary)
                .lineLimit(1)
        }
    }

    private var footerText: String? {
        if let shown { return GlanceText.footer(summary, shown: shown, calendar: .autoupdatingCurrent) }
        return summary.isStale ? GlanceText.asOf(summary, calendar: .autoupdatingCurrent) : nil
    }
}

struct GlanceMessageText: View {
    let message: GlanceMessage
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        Text(verbatim: GlanceText.message(message))
            .font(TallyTypography.subheadline)
            .foregroundStyle(GlanceStyle(renderingMode).primary)
    }
}

/// The placeholder and gallery layout: bars where the text goes, and no text, so it can never read
/// as real data.
struct GlancePlaceholderLines: View {
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
