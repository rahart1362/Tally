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
    @ObservationIgnored private var computedInput: TrendInput?

    public init() {}

    /// Computes `input`'s per-course sparklines, unless it is the input already cached (perf:
    /// never recomputed for a render; the Dashboard never waits on this). The caller's task (each
    /// screen's `.task(id:)`) owns the work: cancelling it cancels the computation, exactly like
    /// `InsightsModel.load`.
    public func load(_ input: TrendInput, calendar: Calendar = .autoupdatingCurrent,
                     locale: Locale = .autoupdatingCurrent) async {
        guard input != computedInput else { return }
        do {
            let result = try await GradeTrend.compute(input, calendar: calendar, locale: locale)
            let formatter = ScreenFormatter(now: input.now, calendar: calendar, locale: locale)
            series = result.perCourse.compactMapValues { CourseSparklineBuilder.build($0, formatter: formatter) }
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

/// Builds `CourseSparklinePoints` from one course's trend series (pure; unit-tested).
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

/// The compact line beside a course's letter grade (PRD §2.B): about 44×16pt on the Courses card,
/// larger in the Course Detail header. The app's accent tint, no axes, no labels, a subtle dot at
/// the last point. One VoiceOver element whose label is the trend sentence; callers hide it
/// entirely when there is nothing to draw (`CourseSparklinePoints?` is `nil`), never a placeholder.
public struct CourseSparklineView: View {
    let points: CourseSparklinePoints
    var width: CGFloat = 44
    var height: CGFloat = 16

    public init(points: CourseSparklinePoints, width: CGFloat = 44, height: CGFloat = 16) {
        self.points = points
        self.width = width
        self.height = height
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
        let lastDate = points.points.last?.date
        Chart(points.points) { point in
            LineMark(x: .value("Day", point.date), y: .value("Percent", point.percent))
                .foregroundStyle(TallyColor.accent)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)
            if point.date == lastDate {
                PointMark(x: .value("Day", point.date), y: .value("Percent", point.percent))
                    .foregroundStyle(TallyColor.accent)
                    .symbolSize(16)
            }
        }
        .chartYScale(domain: Self.yDomain(points.points.map(\.percent)))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(width: width, height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(points.accessibilityLabel)
    }
}
