import Foundation
import Observation
import TallyDomain

/// The trend chart's ranges (ux-ui.md §3.5: "range picker 1M / 3M / Term").
public nonisolated enum TrendRange: String, CaseIterable, Identifiable, Equatable, Sendable {
    case month, quarter, term

    public var id: Self { self }

    public var label: String {
        switch self {
        case .month: "1M"
        case .quarter: "3M"
        case .term: "Term"
        }
    }

    public var spokenLabel: String {
        switch self {
        case .month: "Last month"
        case .quarter: "Last 3 months"
        case .term: "This term"
        }
    }

    /// `nil`: from the start of the term (or the first graded work).
    var days: Int? {
        switch self {
        case .month: 30
        case .quarter: 90
        case .term: nil
        }
    }
}

public nonisolated struct TrendPoint: Identifiable, Equatable, Sendable {
    public var id: Date { date }
    public let date: Date
    public let percent: Double
}

/// One range of the trend chart: its points, axis bounds and the sentence VoiceOver reads (and
/// Audio Graphs summarise), e.g. "Up from 82.0 to 87.2 percent over the last month".
public nonisolated struct TrendRangeView: Equatable, Sendable {
    public let points: [TrendPoint]
    public let summary: String
    public let start: Date
    public let end: Date
    public let lowerPercent: Double
    public let upperPercent: Double
    public var hasEnoughData: Bool { points.count >= GradeTrend.minimumPoints }
}

public nonisolated struct GradeTrendResult: Equatable, Sendable {
    public let ranges: [TrendRange: TrendRangeView]
}

/// The overall-average trend (ux-ui.md §3.7.6 "Performance trend"), derived from graded history
/// (PMO R9: "derived from graded-submission history returned by Canvas; no local time series is
/// kept"). For each day on which a score was posted, each course's current score is recomputed
/// by the domain grade engine as if only the scores posted by the end of that day were posted; the
/// day's point is the mean over the courses that had a score, the same "Average of N courses" rule
/// as the Dashboard hero (owner O9). Every engine call goes through `GradeWork`: off the main
/// actor, and cancellable between calls.
public nonisolated enum GradeTrend {
    /// Fewer points than this read as "Trend appears after a couple of graded assignments"
    /// (ux-ui.md §3.2.3).
    static let minimumPoints = 2
    /// A change smaller than this, in points, reads as "steady".
    static let steadyThreshold = 0.05
    /// Padding above and below the plotted values, in points.
    static let axisPadding = 2.0

    @concurrent
    public static func compute(_ input: TrendInput, calendar: Calendar, locale: Locale) async throws -> GradeTrendResult {
        var courseSeries: [[(day: Date, score: Double)]] = []
        for course in input.courses {
            let days = Set(course.postedAt.values.map { calendar.startOfDay(for: $0) }).sorted()
            var series: [(day: Date, score: Double)] = []
            for day in days {
                try Task.checkCancellation()
                guard let end = calendar.date(byAdding: .day, value: 1, to: day) else { continue }
                if let score = try await GradeWork.scores(for: inputAsOf(course, postedBefore: end)).currentScore {
                    series.append((day, score))
                }
            }
            courseSeries.append(series)
        }
        let overall = average(courseSeries)
        let formatter = ScreenFormatter(now: input.now, calendar: calendar, locale: locale)
        var ranges: [TrendRange: TrendRangeView] = [:]
        for range in TrendRange.allCases {
            ranges[range] = view(of: overall, range: range, termStart: input.termStart, formatter: formatter)
        }
        return GradeTrendResult(ranges: ranges)
    }

    /// `course.input` with every score posted at or after `end` treated as not yet posted.
    static func inputAsOf(_ course: TrendInput.CourseHistory, postedBefore end: Date) -> GradeInput {
        var input = course.input
        input.items = input.items.map { item in
            guard let posted = course.postedAt[item.id], posted >= end else { return item }
            var item = item
            item.submission?.posted = false
            return item
        }
        return input
    }

    /// At each day any course changed, the mean of every course's latest score so far.
    static func average(_ courses: [[(day: Date, score: Double)]]) -> [TrendPoint] {
        let days = Set(courses.flatMap { $0.map(\.day) }).sorted()
        var cursor = Array(repeating: 0, count: courses.count)
        var latest = [Double?](repeating: nil, count: courses.count)
        return days.compactMap { day in
            for (index, series) in courses.enumerated() {
                while cursor[index] < series.count, series[cursor[index]].day <= day {
                    latest[index] = series[cursor[index]].score
                    cursor[index] += 1
                }
            }
            let known = latest.compactMap { $0 }
            guard !known.isEmpty else { return nil }
            return TrendPoint(date: day, percent: known.reduce(0, +) / Double(known.count))
        }
    }

    static func view(of points: [TrendPoint], range: TrendRange, termStart: Date?, formatter: ScreenFormatter) -> TrendRangeView {
        let end = formatter.now
        let start: Date = {
            if let days = range.days {
                return formatter.calendar.date(byAdding: .day, value: -days, to: formatter.calendar.startOfDay(for: end)) ?? end
            }
            return min(termStart ?? points.first?.date ?? end, points.first?.date ?? end)
        }()
        var inRange = points.filter { $0.date >= start && $0.date <= end }
        // The value the range opens with: the last point before it, carried to its start.
        if let before = points.last(where: { $0.date < start }), inRange.first?.date != start {
            inRange.insert(TrendPoint(date: start, percent: before.percent), at: 0)
        }
        let values = inRange.map(\.percent)
        let lower = ((values.min() ?? 0) - axisPadding).rounded(.down)
        let upper = ((values.max() ?? 100) + axisPadding).rounded(.up)
        return TrendRangeView(points: inRange, summary: summary(inRange, range: range, formatter: formatter),
                              start: start, end: end, lowerPercent: max(0, lower), upperPercent: upper)
    }

    static func summary(_ points: [TrendPoint], range: TrendRange, formatter: ScreenFormatter) -> String {
        guard points.count >= minimumPoints, let first = points.first, let last = points.last else {
            return "Trend appears after a couple of graded assignments."
        }
        let span = range == .term ? "this term" : range == .month ? "over the last month" : "over the last 3 months"
        let change = last.percent - first.percent
        if abs(change) < steadyThreshold {
            return "Steady at \(formatter.spokenPercent(last.percent)) \(span)"
        }
        let direction = change > 0 ? "Up" : "Down"
        return "\(direction) from \(formatter.spokenPercent(first.percent)) to \(formatter.spokenPercent(last.percent)) \(span)"
    }
}

/// The Insights tab's grade-derived state (the trend), computed off the main actor through
/// `GradeTrend`/`GradeWork` whenever the projection's trend input changes.
@MainActor
@Observable
public final class InsightsModel {
    /// Explicit and nonisolated (plan 06 A2; swiftlang/swift#88036).
    nonisolated deinit {}

    public private(set) var trend: GradeTrendResult?
    public private(set) var trendFailed = false
    @ObservationIgnored private var computedInput: TrendInput?

    public init() {}

    /// Computes the trend for `input`, unless it is the input already on screen. The caller's task
    /// (the view's `.task(id:)`) owns the work: cancelling it cancels the computation.
    public func load(_ input: TrendInput, calendar: Calendar = .autoupdatingCurrent,
                     locale: Locale = .autoupdatingCurrent) async {
        guard input != computedInput else { return }
        do {
            let result = try await GradeTrend.compute(input, calendar: calendar, locale: locale)
            trend = result
            trendFailed = false
            computedInput = input
        } catch is CancellationError {
            return
        } catch {
            trendFailed = true
        }
    }
}
