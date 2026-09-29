import SwiftUI
import TallyDesignSystem
import TallyDomain

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
                ContentUnavailableView("No insights yet", systemImage: "chart.xyaxis.line",
                                       description: Text("Insights appear once your courses have graded work."))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: TallySpacing.xxl) {
                        trendCard
                        if !projection.categoryShares.isEmpty {
                            ScreenCard {
                                ScreenSectionHeader(title: "Category breakdown",
                                                    subtitle: "What your grades are made of, on average across your courses.")
                                CategoryWeightsChart(weights: projection.categoryShares, title: "Category breakdown",
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
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { FreshnessBreadcrumb() }
        .navigationTitle("Insights")
        .task(id: projection.trendInput) { await insights.load(projection.trendInput) }
    }

    // MARK: - Cards

    private var trendCard: some View {
        ScreenCard {
            ScreenSectionHeader(title: "Performance trend",
                                subtitle: "Average of your courses, from when each grade was posted.")
            Picker("Range", selection: $range) {
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
                Text("The trend couldn't be worked out.")
                    .font(TallyTypography.body)
                    .foregroundStyle(TallyColor.textSecondary)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
    }

    @ViewBuilder
    private func completionCard(_ completion: CompletionInsight?) -> some View {
        if let completion {
            ScreenCard {
                ScreenSectionHeader(title: "Completion", subtitle: "Past-due work you turned in on time this term.")
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
            ScreenSectionHeader(title: "Momentum", subtitle: StreakInsight.definition)
            Label(streak.headline, systemImage: "flame")
                .font(TallyTypography.cardTitle)
                .foregroundStyle(TallyColor.textPrimary)
        }
    }

    @ViewBuilder
    private func risksCard(_ risks: [CourseRisk]) -> some View {
        ScreenCard {
            ScreenSectionHeader(title: "Needs a look", subtitle: "Courses at risk or close to a line, and why.")
            if risks.isEmpty {
                Label("Every course is on track.", systemImage: "checkmark.circle")
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
            ScreenSectionHeader(title: "Heavy stretches", subtitle: "Two-day windows with a lot due in the next 10 days.")
            if stretches.isEmpty {
                Label("No heavy stretches coming up.", systemImage: "calendar")
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
