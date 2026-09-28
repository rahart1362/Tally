import Accessibility
import Charts
import SwiftUI
import TallyDesignSystem

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
struct TrendChart: View {
    let view: TrendRangeView
    @Environment(\.colorSchemeContrast) private var contrast
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 180

    var body: some View {
        Chart(view.points) { point in
            LineMark(x: .value("Date", point.date), y: .value("Percent", point.percent))
                .lineStyle(StrokeStyle(lineWidth: contrast == .increased ? 3 : 2.4))
                .foregroundStyle(TallyColor.accent)
            PointMark(x: .value("Date", point.date), y: .value("Percent", point.percent))
                .foregroundStyle(TallyColor.accent)
        }
        .chartXScale(domain: view.start...max(view.end, view.start))
        .chartYScale(domain: view.lowerPercent...max(view.upperPercent, view.lowerPercent + 1))
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Performance trend")
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
        let xAxis = AXCategoricalDataAxisDescriptor(title: "Category", categoryOrder: weights.map(\.name))
        let yAxis = AXNumericDataAxisDescriptor(title: "Share of grade", range: 0...100, gridlinePositions: [],
                                                valueDescriptionProvider: { @Sendable value in
                                                    value.formatted(.number.precision(.fractionLength(0))) + " percent"
                                                })
        let series = AXDataSeriesDescriptor(name: title, isContinuous: false,
                                            dataPoints: weights.map { AXDataPoint(x: $0.name, y: $0.share * 100) })
        return AXChartDescriptor(title: title, summary: title, xAxis: xAxis, yAxis: yAxis, additionalAxes: [],
                                 series: [series])
    }
}

/// Audio Graphs for the trend.
nonisolated struct TrendChartDescriptor: AXChartDescriptorRepresentable {
    let view: TrendRangeView

    func makeChartDescriptor() -> AXChartDescriptor {
        let start = view.start.timeIntervalSince1970
        let end = max(view.end.timeIntervalSince1970, start)
        let xAxis = AXNumericDataAxisDescriptor(title: "Date", range: start...end, gridlinePositions: [],
                                                valueDescriptionProvider: { @Sendable value in
                                                    Date(timeIntervalSince1970: value).formatted(date: .abbreviated, time: .omitted)
                                                })
        let upper = max(view.upperPercent, view.lowerPercent + 1)
        let yAxis = AXNumericDataAxisDescriptor(title: "Average", range: view.lowerPercent...upper, gridlinePositions: [],
                                                valueDescriptionProvider: { @Sendable value in
                                                    value.formatted(.number.precision(.fractionLength(1))) + " percent"
                                                })
        let series = AXDataSeriesDescriptor(
            name: "Average of your courses", isContinuous: true,
            dataPoints: view.points.map { AXDataPoint(x: $0.date.timeIntervalSince1970, y: $0.percent) })
        return AXChartDescriptor(title: "Trend", summary: view.summary, xAxis: xAxis, yAxis: yAxis,
                                 additionalAxes: [], series: [series])
    }
}
