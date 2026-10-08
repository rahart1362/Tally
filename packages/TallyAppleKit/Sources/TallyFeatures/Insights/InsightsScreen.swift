import SwiftUI
import TallyDesignSystem
import TallyDomain
import TallyStrings

/// UX-WP-19 / ARC E05e: Insights (ux-ui.md §3.7.6; PMO R13, insights-at-a-glance.md §5.4), renamed
/// from "More". Each card title is a header with a one-line "what this means" subtitle.
///
/// - **Performance trend**: Swift Charts, a range picker, and an Audio Graph descriptor (A11Y-08).
///   Derived from graded history through `GradeWork` (`InsightsModel`); never a stored series (R9).
/// - **Category breakdown**: horizontal bars with direct labels (`chart.weights`).
/// - **Completion**, **Momentum** (the `flame` symbol, no emoji, the streak's definition stated),
///   **Needs a look** (courses with reasons) and **Heavy stretches** (the A7 overload rule).
struct InsightsScreen: View {
    @Environment(HomeModel.self) private var model
    @State private var insights = InsightsModel()
    @State private var range: TrendRange = .month

    var body: some View {
        let projection = model.insightsScreen
        Group {
            if model.courseCards.isEmpty {
                ContentUnavailableView(String(localized: L10n.Insights.emptyTitle()), systemImage: "chart.xyaxis.line",
                                       description: Text(L10n.Insights.emptyDescription()))
                    // ux-fp2 D20: centred when it fits, scrolling when it does not (AX5).
                    .tallyCenteredScrolling()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: TallySpacing.xxl) {
                        trendCard(notInCanvas: projection.trendIsNotInCanvas)
                        if !projection.categoryShares.isEmpty {
                            ScreenCard {
                                ScreenSectionHeader(title: L10n.Insights.categoryBreakdownHeader(),
                                                    subtitle: L10n.Insights.categoryBreakdownSubtitle())
                                CategoryWeightsChart(weights: projection.categoryShares,
                                                     title: String(localized: L10n.Insights.categoryBreakdownHeader()),
                                                     summary: projection.categorySummary)
                            }
                        }
                        completionCard(projection.completion)
                        momentumCard(projection.streak)
                        risksCard(projection.risks)
                        heavyCard(projection.heavyStretches)
                    }
                    .padding(.horizontal, TallySpacing.screenMargin)
                    .padding(.vertical, TallySpacing.lg)
                }
                .background(TallyColor.bgCanvas)
                .refreshable { await model.refreshUntilSettledOrDelayed() }
                // D01: content scrolled past the top stayed visible, blurred, under the inline
                // title and the status bar, even at rest. R4 (round 3): the large-title variant,
                // so the opaque fill never paints over "Insights" at rest.
                .tallyLargeTitleScreenChrome()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { FreshnessBreadcrumb() }
        .navigationTitle(String(localized: L10n.Insights.navigationTitle()))
        .task(id: projection.trendInput) { await insights.load(projection.trendInput) }
    }

    // MARK: - Cards

    /// Plan 08 §4.4 row 7: with no course to trend because the grades are kept outside Canvas,
    /// the card says so instead of offering ranges over nothing.
    @ViewBuilder
    private func trendCard(notInCanvas: Bool) -> some View {
        ScreenCard {
            ScreenSectionHeader(title: L10n.Insights.performanceTrendHeader(), subtitle: L10n.Insights.performanceTrendSubtitle())
            if notInCanvas {
                Text(L10n.Insights.trendNotInCanvas())
                    .font(TallyTypography.body)
                    .foregroundStyle(TallyColor.textSecondary)
            } else {
                trendContent
            }
        }
    }

    @ViewBuilder
    private var trendContent: some View {
        Picker(String(localized: L10n.Insights.trendRangePicker()), selection: $range) {
            ForEach(TrendRange.allCases) { range in
                Text(range.label).tag(range).accessibilityLabel(range.spokenLabel)
            }
        }
        .pickerStyle(.segmented)
        if let view = insights.trend?.ranges[range] {
            if view.hasEnoughData {
                TrendChart(view: view)
            } else {
                Text(view.summary)
                    .font(TallyTypography.body)
                    .foregroundStyle(TallyColor.textSecondary)
            }
        } else if insights.trendFailed {
            Text(L10n.Insights.trendFailed())
                .font(TallyTypography.body)
                .foregroundStyle(TallyColor.textSecondary)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 120)
        }
    }

    @ViewBuilder
    private func completionCard(_ completion: CompletionInsight?) -> some View {
        if let completion {
            ScreenCard {
                ScreenSectionHeader(title: L10n.Insights.completionHeader(), subtitle: L10n.Insights.completionSubtitle())
                Text(completion.headline)
                    .font(TallyTypography.cardTitle)
                    .foregroundStyle(TallyColor.textPrimary)
                ProgressView(value: completion.share)
                    .tint(TallyColor.accent)
                    .accessibilityHidden(true)
                Text(completion.detail)
                    .font(TallyTypography.footnote)
                    .foregroundStyle(TallyColor.textSecondary)
            }
        }
    }

    private func momentumCard(_ streak: StreakInsight) -> some View {
        ScreenCard {
            ScreenSectionHeader(title: L10n.Insights.momentumHeader(), subtitle: StreakInsight.definition)
            Label(streak.headline, systemImage: "flame")
                .font(TallyTypography.cardTitle)
                .foregroundStyle(TallyColor.textPrimary)
        }
    }

    @ViewBuilder
    private func risksCard(_ risks: [CourseRisk]) -> some View {
        ScreenCard {
            ScreenSectionHeader(title: L10n.Insights.risksHeader(), subtitle: L10n.Insights.risksSubtitle())
            if risks.isEmpty {
                Label(String(localized: L10n.Insights.risksEmpty()), systemImage: "checkmark.circle")
                    .font(TallyTypography.body)
                    .foregroundStyle(TallyColor.textPrimary)
            } else {
                ForEach(risks) { risk in
                    VStack(alignment: .leading, spacing: TallySpacing.xs) {
                        Text("\(risk.code) · \(risk.name)")
                            .font(TallyTypography.cardTitle)
                            .foregroundStyle(TallyColor.textPrimary)
                        StatusChip(symbol: risk.health.symbol, text: risk.health.label, tone: risk.health.tone)
                        ForEach(risk.reasons.indices, id: \.self) { index in
                            Text(risk.reasons[index])
                                .font(TallyTypography.footnote)
                                .foregroundStyle(TallyColor.textSecondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(risk.accessibilityLabel)
                    .accessibilityIdentifier("insights.risk")
                }
            }
        }
    }

    private func heavyCard(_ stretches: [HeavyStretch]) -> some View {
        ScreenCard {
            ScreenSectionHeader(title: L10n.Insights.heavyHeader(), subtitle: L10n.Insights.heavySubtitle())
            if stretches.isEmpty {
                Label(String(localized: L10n.Insights.heavyEmpty()), systemImage: "calendar")
                    .font(TallyTypography.body)
                    .foregroundStyle(TallyColor.textPrimary)
            } else {
                ForEach(stretches) { stretch in
                    VStack(alignment: .leading, spacing: TallySpacing.xs) {
                        Label(stretch.headline, systemImage: "calendar.badge.exclamationmark")
                            .font(TallyTypography.cardTitle)
                            .foregroundStyle(TallyColor.textPrimary)
                        Text(stretch.detail)
                            .font(TallyTypography.footnote)
                            .foregroundStyle(TallyColor.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
