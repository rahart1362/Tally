import Accessibility
import Charts
import SwiftUI
import TallyDesignSystem
import TallyStrings

/// Category weights as horizontal bars with direct labels (ux-ui.md §3.5, replacing the mockup's
/// donut, which relies on colour and a legend). One accessibility element with a label, a value
/// and an Audio Graph descriptor (A11Y-08: `chart.weights`).
struct CategoryWeightsChart: View {
    let weights: [CategoryWeight]
    let title: String
    let summary: String
    /// Each bar's row, scaled with Dynamic Type so the category names never clip.
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 36

    var body: some View {
        Chart(weights) { weight in
            BarMark(x: .value("Share", min(weight.share, 1) * 100), y: .value("Category", weight.name))
                .foregroundStyle(TallyColor.accent)
                .annotation(position: .trailing, alignment: .leading) {
                    Text(weight.shareText)
                        .font(TallyTypography.caption)
                        .foregroundStyle(TallyColor.textSecondary)
                }
        }
        .chartXScale(domain: 0.0...100.0)
        .chartXAxis(.hidden)
        // D07: the category names are the chart's y-axis value labels, drawn by Swift Charts in
        // the system secondary grey by default (3.44:1 on white); style them like every other
        // secondary label.
        .chartYAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .foregroundStyle(TallyColor.textSecondary)
            }
        }
        .frame(height: CGFloat(max(weights.count, 1)) * rowHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(summary)
        .accessibilityChartDescriptor(CategoryChartDescriptor(title: title, summary: summary, weights: weights))
        .accessibilityIdentifier("chart.weights")
    }
}

/// The grade trend (ux-ui.md §3.5 "Trend chart": `LineMark` + `PointMark`, y-axis in %), with its
/// sentence as the VoiceOver value and an Audio Graph descriptor (A11Y-08: `chart.trend`). Lines
/// thicken under Increase Contrast.
///
/// ux-fp2 D19 (S2): at the accessibility sizes the x-axis's date labels had no room and collapsed to
/// "S… S… S… …". From AX1 up the axis keeps its grid lines without labels, and one caption under the
/// chart names the range it covers ("Sep 7 – Oct 7", in the student's locale).
struct TrendChart: View {
    let view: TrendRangeView
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 180

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: TallySpacing.xs) {
                chart
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisGridLine()
                        }
                    }
                    .frame(height: height)
                    .modifier(TrendChartAccessibility(view: view))
                Text(view.start..<max(view.end, view.start), format: .interval.month(.abbreviated).day())
                    .font(TallyTypography.caption)
                    .foregroundStyle(TallyColor.textSecondary)
                    .accessibilityIdentifier("chart.trend.range")
            }
        } else {
            chart
                .frame(height: height)
                .modifier(TrendChartAccessibility(view: view))
        }
    }

    private var chart: some View {
        Chart(view.points) { point in
            LineMark(x: .value("Date", point.date), y: .value("Percent", point.percent))
                .lineStyle(StrokeStyle(lineWidth: contrast == .increased ? 3 : 2.4))
                .foregroundStyle(TallyColor.accent)
            PointMark(x: .value("Date", point.date), y: .value("Percent", point.percent))
                .foregroundStyle(TallyColor.accent)
        }
        .chartXScale(domain: view.start...max(view.end, view.start))
        .chartYScale(domain: view.lowerPercent...max(view.upperPercent, view.lowerPercent + 1))
    }
}

/// The trend chart's single VoiceOver element (A11Y-08), the same at every text size.
private struct TrendChartAccessibility: ViewModifier {
    let view: TrendRangeView

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(L10n.Insights.performanceTrendHeader()))
            .accessibilityValue(view.summary)
            .accessibilityChartDescriptor(TrendChartDescriptor(view: view))
            .accessibilityIdentifier("chart.trend")
    }
}

/// Audio Graphs for the category chart. `nonisolated`: the accessibility system builds it on demand.
nonisolated struct CategoryChartDescriptor: AXChartDescriptorRepresentable {
    let title: String
    let summary: String
    let weights: [CategoryWeight]

    func makeChartDescriptor() -> AXChartDescriptor {
        let xAxis = AXCategoricalDataAxisDescriptor(title: String(localized: L10n.Insights.categoryShareAxisCategory()),
                                                    categoryOrder: weights.map(\.name))
        let yAxis = AXNumericDataAxisDescriptor(
            title: String(localized: L10n.Insights.categoryShareAxisTitle()), range: 0...100, gridlinePositions: [],
            valueDescriptionProvider: { @Sendable value in
                String(localized: L10n.Insights.spokenPercent(value.formatted(.number.precision(.fractionLength(0)))))
            })
        let series = AXDataSeriesDescriptor(name: title, isContinuous: false,
                                            dataPoints: weights.map { AXDataPoint(x: $0.name, y: $0.share * 100) })
        return AXChartDescriptor(title: title, summary: summary, xAxis: xAxis, yAxis: yAxis, additionalAxes: [],
                                 series: [series])
    }
}

/// Audio Graphs for the trend.
nonisolated struct TrendChartDescriptor: AXChartDescriptorRepresentable {
    let view: TrendRangeView

    func makeChartDescriptor() -> AXChartDescriptor {
        let start = view.start.timeIntervalSince1970
        let end = max(view.end.timeIntervalSince1970, start)
        let xAxis = AXNumericDataAxisDescriptor(
            title: String(localized: L10n.Insights.spokenDate()), range: start...end, gridlinePositions: [],
            valueDescriptionProvider: { @Sendable value in
                Date(timeIntervalSince1970: value).formatted(date: .abbreviated, time: .omitted)
            })
        let upper = max(view.upperPercent, view.lowerPercent + 1)
        let yAxis = AXNumericDataAxisDescriptor(
            title: String(localized: L10n.Insights.trendAxisAverageShort()), range: view.lowerPercent...upper, gridlinePositions: [],
            valueDescriptionProvider: { @Sendable value in
                String(localized: L10n.Insights.spokenPercent(value.formatted(.number.precision(.fractionLength(1)))))
            })
        let series = AXDataSeriesDescriptor(
            name: String(localized: L10n.Insights.trendAxisAverage()), isContinuous: true,
            dataPoints: view.points.map { AXDataPoint(x: $0.date.timeIntervalSince1970, y: $0.percent) })
        return AXChartDescriptor(title: String(localized: L10n.Insights.performanceTrendHeader()), summary: view.summary,
                                 xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [series])
    }
}
