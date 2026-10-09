import Charts
import Foundation
import Observation
import SwiftUI
import TallyDesignSystem
import TallyDomain
import TallyStrings

/// The trend sparkline next to a course's letter grade (UX-SPARK, PRD §2.B): a compact line over
/// the course's own graded history, derived from the same per-day engine recomputation
/// `GradeTrend` uses for the Insights average (PMO R9: never a separate, locally-kept series).
/// Shown on the Courses card (`CourseCardView`) and the Course Detail header (`CourseHeroCard`);
/// both read the same `CourseSparklineModel` instance so the computation runs once per snapshot,
/// off the main actor, and is never repeated for a render.
///
/// UX-SPARK-2 (owner review, 2026-10-04): also caches the Dashboard hero's overall trend
/// (`overall`) — the same term-range series `GradeTrend` already returns for Insights'
/// "Performance trend" — from the very same `GradeTrend.compute` call, never a second pass.
@MainActor
@Observable
public final class CourseSparklineModel {
    /// Explicit and nonisolated (plan 06 A2; swiftlang/swift#88036), matching `InsightsModel`.
    nonisolated deinit {}

    /// Each course's sparkline, ready to draw. A course absent here shows none: fewer than
    /// `GradeTrend.minimumPoints` graded days, or its grade is not `.available` (kept outside
    /// Canvas, not graded in Canvas, hidden by the instructor, letters only, or not yet posted —
    /// the same courses `TrendInput` already leaves out of the Insights average).
    public private(set) var series: [CanvasID<Course>: CourseSparklinePoints] = [:]
    /// UX-SPARK-2: the Dashboard hero's overall trend (PRD §2.A "overall grade and trend line") —
    /// the term-range series Insights' "Performance trend" shows, `nil` under
    /// `GradeTrend.minimumPoints`. Computed here (never on `DashboardView`'s body) so the hero's
    /// paint is never delayed: the caller's `.task(id:)` runs this after the first render.
    public private(set) var overall: CourseSparklinePoints?
    @ObservationIgnored private var computedInput: TrendInput?

    public init() {}

    /// Computes `input`'s per-course sparklines and the overall trend, unless it is the input
    /// already cached (perf: never recomputed for a render; the Dashboard never waits on this).
    /// The caller's task (each screen's `.task(id:)`) owns the work: cancelling it cancels the
    /// computation, exactly like `InsightsModel.load`.
    public func load(_ input: TrendInput, calendar: Calendar = .autoupdatingCurrent,
                     locale: Locale = .autoupdatingCurrent) async {
        guard input != computedInput else { return }
        do {
            let result = try await GradeTrend.compute(input, calendar: calendar, locale: locale)
            let formatter = ScreenFormatter(now: input.now, calendar: calendar, locale: locale)
            series = result.perCourse.compactMapValues { CourseSparklineBuilder.build($0, formatter: formatter) }
            overall = result.ranges[.term].flatMap { CourseSparklineBuilder.build($0.points, formatter: formatter) }
            computedInput = input
        } catch is CancellationError {
            return
        } catch {
            // Decorative: leave whatever was cached. A course simply shows no sparkline.
        }
    }
}

/// One course's sparkline: its points, ready for `CourseSparklineView`, and the sentence VoiceOver
/// reads for it.
public nonisolated struct CourseSparklinePoints: Equatable, Sendable {
    public let points: [TrendPoint]
    public let accessibilityLabel: String
}

/// Builds `CourseSparklinePoints` from one course's trend series (pure; unit-tested). Also builds
/// the Dashboard hero's overall-trend points (UX-SPARK-2): the function takes any `[TrendPoint]`
/// series, course-specific or the overall average, with the same two-point guard either way.
public nonisolated enum CourseSparklineBuilder {
    /// A change smaller than this, in points, reads as "steady" — the same threshold the Insights
    /// trend sentence uses.
    static let steadyThreshold = 0.05

    /// `nil` when `series` has fewer than `GradeTrend.minimumPoints` points: the sparkline does not
    /// show at all, never a placeholder (ux-ui.md §3.2.3). `GradeTrend.compute` already applies
    /// this threshold before handing out `perCourse`; the guard here makes this builder correct on
    /// its own too.
    public static func build(_ series: [TrendPoint], formatter: ScreenFormatter) -> CourseSparklinePoints? {
        guard series.count >= GradeTrend.minimumPoints, let first = series.first, let last = series.last else {
            return nil
        }
        return CourseSparklinePoints(points: series,
                                     accessibilityLabel: summary(first: first.percent, last: last.percent, locale: formatter.locale))
    }

    /// "Trend: up from 82.0 to 87.2 percent", "Trend: down from …", "Trend: steady at …". Each
    /// direction is its own whole-sentence key (word order varies by language), the pattern
    /// `GradeTrend.summary` uses for the Insights trend; this sentence names no range (the
    /// sparkline is always the whole term) and states "percent" once for the whole span.
    static func summary(first: Double, last: Double, locale: Locale) -> String {
        let change = last - first
        if abs(change) < steadyThreshold {
            return L10n.string(L10n.Courses.sparklineTrendSteady, numberText(last, locale: locale))
        }
        let firstText = numberText(first, locale: locale)
        let lastText = numberText(last, locale: locale)
        return change > 0
            ? L10n.string(L10n.Courses.sparklineTrendUp, firstText, lastText)
            : L10n.string(L10n.Courses.sparklineTrendDown, firstText, lastText)
    }

    /// "82.0": a percentage's bare number, one decimal, the same precision
    /// `ScreenFormatter.spokenPercent` uses, but with no unit word (the sentence above states
    /// "percent" once, for the whole from-to span).
    static func numberText(_ percent: Double, locale: Locale) -> String {
        percent.formatted(.number.precision(.fractionLength(1)).locale(locale))
    }
}

/// UX-SPARK-2 (owner-approved redesign, variant F with variant E's hollow end ring,
/// `~/Documents/Tally-marketing/design/spark-variants2.png`): straight segments, a point per
/// posted day, a hollow end ring, faint gridlines, no glow, no axes, no labels. One VoiceOver
/// element whose label is the trend sentence; callers hide it entirely when there is nothing to
/// draw (`CourseSparklinePoints?` is `nil`), never a placeholder.
public enum CourseSparklineStyle {
    /// The line's weight at the default type size, in points; scales with `maximumTypeScale`.
    public static let lineWidth: CGFloat = 2
    /// Each posted day's point diameter at the default type size, in points.
    public static let pointDiameter: CGFloat = 3
    /// The end-of-line hollow ring's diameter at the default type size, in points.
    public static let endRingDiameter: CGFloat = 8
    /// The end ring's stroke weight at the default type size, in points.
    public static let endRingStrokeWidth: CGFloat = 2
    /// D14: how far the sparkline may grow with Dynamic Type. `@ScaledMetric` alone is unbounded,
    /// and at AX5 the line was a hairline under a 3× grade letter; capped about 2× keeps it
    /// legible without crowding the grade beside it.
    public static let maximumTypeScale: CGFloat = 2
    /// Horizontal gridlines drawn across the plotted range (interior quartiles, never at the
    /// edges, where they would sit on top of the line's own extremes).
    public static let horizontalGridlineCount = 3
    /// Cream (`TallyColor.brandCream`) on the navy heroes, at this opacity.
    public static let horizontalGridlineOpacityOnHero = 0.10
    /// Silver (`TallyColor.separator`) on a light card, at this opacity.
    public static let horizontalGridlineOpacityOnCard = 0.25
    /// The faint weekly vertical columns, on the navy heroes.
    public static let verticalGridlineOpacityOnHero = 0.06
    /// The faint weekly vertical columns, on a light card.
    public static let verticalGridlineOpacityOnCard = 0.15

    /// Three interior values, evenly spaced across `domain` (quartiles): the "3 faint horizontal
    /// gridlines" the owner's mock-up shows, never drawn at the domain's own edges (the line's
    /// own extremes already mark those).
    public static func horizontalGridValues(_ domain: ClosedRange<Double>) -> [Double] {
        let step = (domain.upperBound - domain.lowerBound) / 4
        return (1...3).map { domain.lowerBound + step * Double($0) }
    }

    /// Dates roughly a week apart between `start` and `end` (exclusive of both), for the faint
    /// vertical week columns. Pure and deterministic: stepping from `start` rather than aligning
    /// to the calendar's first weekday, which is close enough for a decorative background grid.
    public static func weekColumnDates(from start: Date, to end: Date, calendar: Calendar) -> [Date] {
        guard end > start else { return [] }
        var dates: [Date] = []
        var cursor = start
        while let next = calendar.date(byAdding: .day, value: 7, to: cursor), next < end {
            dates.append(next)
            cursor = next
        }
        return dates
    }
}

/// Which surface a sparkline is drawn on: the navy hero (Dashboard, Course Detail) or a light
/// card (Courses). Selects the gridline tint/opacity and the end ring's fill, so the line never
/// shows through its hollow centre.
public enum SparklineBackground: Sendable {
    case hero
    case card

    var horizontalGridlineColor: Color {
        switch self {
        case .hero: TallyColor.brandCream.opacity(CourseSparklineStyle.horizontalGridlineOpacityOnHero)
        case .card: TallyColor.separator.opacity(CourseSparklineStyle.horizontalGridlineOpacityOnCard)
        }
    }

    var verticalGridlineColor: Color {
        switch self {
        case .hero: TallyColor.brandCream.opacity(CourseSparklineStyle.verticalGridlineOpacityOnHero)
        case .card: TallyColor.separator.opacity(CourseSparklineStyle.verticalGridlineOpacityOnCard)
        }
    }

    /// The end ring's fill, so the line's own colour never shows through its hollow centre.
    var ringFill: Color {
        switch self {
        case .hero: TallyColor.bgBrand
        case .card: TallyColor.bgCard
        }
    }
}

/// The trend sparkline (UX-SPARK-2): straight segments between posted days, a small point at
/// each, a hollow ring at the end, faint gridlines, no axes, no labels, no glow. Used beside a
/// course's letter grade (Courses card) and filling the remaining width beside the grade block on
/// the Dashboard and Course Detail heroes.
public struct CourseSparklineView: View {
    /// The Courses card's dedicated trend column, in points, at the default type size.
    public static let courseCardSize = CGSize(width: 96, height: 32)
    /// The Dashboard and Course Detail heroes' trend height, in points, at the default type size;
    /// its width is whatever the hero's two-zone layout leaves beside the grade block (`width:
    /// nil`).
    public static let heroHeight: CGFloat = 56

    let points: CourseSparklinePoints
    private let baseWidth: CGFloat?
    private let baseHeight: CGFloat
    let tint: Color
    let background: SparklineBackground
    /// D14: scales both dimensions and the line/point/ring weights with Dynamic Type, capped at
    /// `CourseSparklineStyle.maximumTypeScale`.
    @ScaledMetric(relativeTo: .footnote) private var typeScale: CGFloat = 1

    /// - Parameters:
    ///   - width: `nil` fills whatever width the caller's layout leaves (the hero's two-zone
    ///     layout); a fixed value (the Courses card's dedicated column) is scaled with Dynamic
    ///     Type like every other dimension here.
    public init(points: CourseSparklinePoints, width: CGFloat? = CourseSparklineView.courseCardSize.width,
                height: CGFloat = CourseSparklineView.courseCardSize.height, tint: Color = TallyColor.accent,
                background: SparklineBackground = .card) {
        self.points = points
        self.baseWidth = width
        self.baseHeight = height
        self.tint = tint
        self.background = background
    }

    private var scale: CGFloat { min(typeScale, CourseSparklineStyle.maximumTypeScale) }
    private var height: CGFloat { baseHeight * scale }
    private var width: CGFloat? { baseWidth.map { $0 * scale } }
    private var strokeWidth: CGFloat { CourseSparklineStyle.lineWidth * scale }

    private var pointSymbolArea: CGFloat {
        let diameter = CourseSparklineStyle.pointDiameter * scale
        return diameter * diameter
    }

    /// The vertical range: the series' own lowest and highest values, padded like the Insights
    /// trend (`GradeTrend.axisPadding`, in percentage points), so a real move shows as a slope and a
    /// steady course stays flat. Swift Charts' default domain starts at 0, which flattened every
    /// line (owner review, 2026-10-03).
    static func yDomain(_ percents: [Double]) -> ClosedRange<Double> {
        guard let low = percents.min(), let high = percents.max() else { return 0...100 }
        return (low - GradeTrend.axisPadding)...(high + GradeTrend.axisPadding)
    }

    public var body: some View {
        let percents = points.points.map(\.percent)
        let domain = Self.yDomain(percents)
        let firstDate = points.points.first?.date ?? Date()
        let lastDate = points.points.last?.date ?? firstDate
        let range = domain.upperBound - domain.lowerBound
        let endFraction = range > 0 ? ((percents.last ?? domain.lowerBound) - domain.lowerBound) / range : 1

        Chart {
            ForEach(CourseSparklineStyle.horizontalGridValues(domain), id: \.self) { value in
                RuleMark(y: .value("Grid", value))
                    .foregroundStyle(background.horizontalGridlineColor)
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
            ForEach(CourseSparklineStyle.weekColumnDates(from: firstDate, to: lastDate, calendar: .autoupdatingCurrent),
                   id: \.self) { date in
                RuleMark(x: .value("Week", date))
                    .foregroundStyle(background.verticalGridlineColor)
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
            ForEach(points.points) { point in
                // The owner rejected smooth curves at thumbnail size ("a wiggly tail ending in a
                // blob") and strong glow: straight segments, no shadow, no area fill.
                LineMark(x: .value("Day", point.date), y: .value("Percent", point.percent))
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.linear)
                PointMark(x: .value("Day", point.date), y: .value("Percent", point.percent))
                    .foregroundStyle(tint)
                    .symbolSize(pointSymbolArea)
            }
        }
        // A tight domain on both axes (no Swift Charts auto-padding), so the last point always
        // lands exactly at the trailing edge: the hollow ring below is positioned from that, with
        // no need to read the chart's own coordinate space back.
        .chartXScale(domain: firstDate...lastDate)
        .chartYScale(domain: domain)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(width: width, height: height)
        .overlay(alignment: .trailing) {
            endRing
                .offset(y: height * (1 - endFraction) - height / 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(points.accessibilityLabel)
    }

    /// The hollow end ring: a stroke in the line's colour, filled with the surface's own
    /// background so the line never shows through its centre (no glow, no halo).
    private var endRing: some View {
        let diameter = CourseSparklineStyle.endRingDiameter * scale
        return Circle()
            .fill(background.ringFill)
            .overlay(Circle().strokeBorder(tint, lineWidth: CourseSparklineStyle.endRingStrokeWidth * scale))
            .frame(width: diameter, height: diameter)
    }
}
