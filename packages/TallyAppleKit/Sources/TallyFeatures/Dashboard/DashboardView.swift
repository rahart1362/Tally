import SwiftUI
import TallyDesignSystem
import TallyDomain

/// UX-WP-13: the Dashboard (ux-ui.md §3.7.1, insights-at-a-glance.md §1). It renders
/// `HomeModel`'s already-built `DashboardProjection` and computes nothing in `body`
/// (perf-app-runtime.md §3 item 4): no builder, no clock, no calendar, no sorting. Freshness
/// lives in leaf views (`FreshnessFooter`, `FreshnessBreadcrumb`), so a refresh that changes only
/// freshness never re-evaluates this body (`HomeRenderTests`).
struct DashboardView: View {
    @Environment(HomeModel.self) private var model
    #if DEBUG
    @Environment(\.bodyEvaluationCounter) private var bodyCounter
    #endif

    var body: some View {
        #if DEBUG
        let _ = bodyCounter?.record("DashboardView")
        #endif
        ScrollView {
            VStack(alignment: .leading, spacing: TallySpacing.xxl) {
                FreshnessBreadcrumb()
                header
                switch model.phase {
                case .loading:
                    DashboardLoadingView()
                case .failed:
                    ContentUnavailableView("No dashboard yet", systemImage: "house",
                                           description: Text("Sign in, or explore with sample data, to see your dashboard."))
                        .padding(.top, TallySpacing.xxxl)
                case .loaded:
                    HeroSection(hero: model.dashboard.hero)
                    if let summary = model.dashboard.changeDigestSummary {
                        ChangeDigestChip(summary: summary)
                    }
                    NextUpSection(items: model.dashboard.nextUp)
                    NeedsAttentionSection(items: model.dashboard.needsAttention)
                    WeekAheadSection(days: model.dashboard.weekAhead)
                    DueSoonSection(items: model.dashboard.dueSoon)
                }
            }
            .padding(.horizontal, TallySpacing.screenMargin)
            .padding(.bottom, TallySpacing.xxxl)
        }
        .background(TallyColor.bgCanvas)
        // Awaits the model-owned refresh until it settles or the live budget passes; never ties
        // the run to this view's task (plan 06 row 7, SH-2).
        .refreshable { await model.requestRefresh() } // MUTATION MS3: the spinner stops at once
        .navigationTitle("Dashboard")
    }

    @ViewBuilder
    private var header: some View {
        if let name = model.studentDisplayName {
            Text("Good \(model.greeting.rawValue), \(name)")
                .font(TallyTypography.subheadline)
                .foregroundStyle(TallyColor.textSecondary)
        }
    }
}

/// The first-load skeleton: the hero's shape with a progress indicator, never fabricated values.
private struct DashboardLoadingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: TallySpacing.md) {
            ProgressView()
                .tint(TallyColor.textOnHero)
            Text("Loading your dashboard…")
                .font(TallyTypography.footnote)
                .foregroundStyle(TallyColor.textOnHero2)
        }
        .padding(TallySpacing.lg)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .background(TallyColor.bgBrand, in: RoundedRectangle(cornerRadius: TallyRadius.hero, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Hero ("Average of N courses")

/// Its freshness line and refresh button are a separate leaf (`FreshnessFooter`), so a change of
/// freshness re-renders that footer only.
private struct HeroSection: View {
    let hero: DashboardProjection.Hero

    var body: some View {
        VStack(alignment: .leading, spacing: TallySpacing.md) {
            VStack(alignment: .leading, spacing: TallySpacing.md) {
                Text("Average of \(hero.courseCount) course\(hero.courseCount == 1 ? "" : "s")")
                    .font(TallyTypography.footnote)
                    .foregroundStyle(TallyColor.textOnHero2)

                if let percent = hero.overallPercent {
                    HStack(alignment: .firstTextBaseline, spacing: TallySpacing.sm) {
                        Text(percent.formatted(.number.precision(.fractionLength(1))) + "%")
                            .font(.system(.largeTitle, design: .serif).bold())
                            .foregroundStyle(TallyColor.textOnHero)
                            .monospacedDigit()
                        if let band = hero.overallBand {
                            Text(bandLabel(band))
                                .font(TallyTypography.sectionHeader)
                                .foregroundStyle(TallyColor.brandGold)
                        }
                    }
                } else {
                    Text("No grades to show yet")
                        .font(TallyTypography.body)
                        .foregroundStyle(TallyColor.textOnHero2)
                }
            }
            // The figures read as one element; the footer's refresh button stays its own element
            // (perf-app-runtime.md §3 item 7: never combine children that include a control).
            .accessibilityElement(children: .combine)

            FreshnessFooter()
        }
        .padding(TallySpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TallyColor.bgBrand, in: RoundedRectangle(cornerRadius: TallyRadius.hero, style: .continuous))
    }

    private func bandLabel(_ band: GradeBand) -> String {
        switch band {
        case .aRange: "A"
        case .bRange: "B"
        case .cRange: "C"
        case .dRange: "D"
        case .fRange: "F"
        case .passing: "Passing"
        case .failing: "Failing"
        case .unknown: ""
        }
    }
}

// MARK: - Next up

private struct NextUpSection: View {
    let items: [DashboardProjection.NextUpItem]

    var body: some View {
        VStack(alignment: .leading, spacing: TallySpacing.sm) {
            SectionHeader(title: "Next up")
            if items.isEmpty {
                Text("Nothing to do right now").font(TallyTypography.body).foregroundStyle(TallyColor.textSecondary)
            } else {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: TallySpacing.xs) {
                        HStack {
                            Text(item.title).font(TallyTypography.cardTitle)
                            Spacer()
                            Text(bandWord(item.band)).font(TallyTypography.caption).foregroundStyle(TallyColor.textSecondary)
                        }
                        Text(item.reason).font(TallyTypography.footnote).foregroundStyle(TallyColor.textSecondary)
                    }
                    .padding(TallySpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(TallyColor.bgCard, in: RoundedRectangle(cornerRadius: TallyRadius.card, style: .continuous))
                }
            }
        }
    }

    private func bandWord(_ band: PriorityScore.Band) -> String {
        switch band {
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        }
    }
}

// MARK: - Needs attention

private struct NeedsAttentionSection: View {
    let items: [DashboardProjection.AttentionItem]

    var body: some View {
        VStack(alignment: .leading, spacing: TallySpacing.sm) {
            SectionHeader(title: "Needs attention")
            if items.isEmpty {
                Text("All clear").font(TallyTypography.body).foregroundStyle(TallyColor.textSecondary)
            } else {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: TallySpacing.md) {
                        Image(systemName: severityIcon(item.severity))
                            .foregroundStyle(severityColor(item.severity))
                        VStack(alignment: .leading, spacing: TallySpacing.xs) {
                            Text(item.title).font(TallyTypography.cardTitle)
                            if let subtitle = item.subtitle {
                                Text(subtitle).font(TallyTypography.footnote).foregroundStyle(TallyColor.textSecondary)
                            }
                        }
                    }
                    .padding(TallySpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(TallyColor.bgCard, in: RoundedRectangle(cornerRadius: TallyRadius.card, style: .continuous))
                }
            }
        }
    }

    private func severityIcon(_ severity: AlertSeverity) -> String {
        switch severity {
        case .critical, .high: "exclamationmark.triangle.fill"
        case .medium: "exclamationmark.circle"
        case .info: "info.circle"
        }
    }

    private func severityColor(_ severity: AlertSeverity) -> Color {
        switch severity {
        case .critical, .high: .red
        case .medium: .orange
        case .info: TallyColor.textSecondary
        }
    }
}

// MARK: - Week ahead

private struct WeekAheadSection: View {
    let days: [DashboardProjection.WeekDay]

    var body: some View {
        VStack(alignment: .leading, spacing: TallySpacing.sm) {
            SectionHeader(title: "Week ahead")
            HStack(spacing: TallySpacing.sm) {
                ForEach(days) { day in
                    VStack(spacing: TallySpacing.xs) {
                        Text(day.date.formatted(.dateTime.weekday(.narrow)))
                            .font(TallyTypography.caption)
                            .foregroundStyle(TallyColor.textSecondary)
                        Text("\(day.dueCount)")
                            .font(TallyTypography.cardTitle)
                            .foregroundStyle(day.isBusy ? .orange : TallyColor.textPrimary)
                        if day.isBusy {
                            Image(systemName: "exclamationmark.triangle").font(.caption2).foregroundStyle(.orange)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(TallySpacing.md)
            .background(TallyColor.bgCard, in: RoundedRectangle(cornerRadius: TallyRadius.card, style: .continuous))
        }
    }
}

// MARK: - Due soon

private struct DueSoonSection: View {
    let items: [DashboardProjection.DueItem]

    var body: some View {
        VStack(alignment: .leading, spacing: TallySpacing.sm) {
            SectionHeader(title: "Due soon")
            if items.isEmpty {
                Text("Nothing due in the next 7 days").font(TallyTypography.body).foregroundStyle(TallyColor.textSecondary)
            } else {
                ForEach(items) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: TallySpacing.xs) {
                            Text(item.title).font(TallyTypography.cardTitle)
                            if let code = item.courseCode {
                                Text(code).font(TallyTypography.footnote).foregroundStyle(TallyColor.textSecondary)
                            }
                        }
                        Spacer()
                        if let due = item.dueAt {
                            Text(due.formatted(date: .omitted, time: .shortened))
                                .font(TallyTypography.footnote)
                                .foregroundStyle(TallyColor.textSecondary)
                        }
                    }
                    .padding(TallySpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(TallyColor.bgCard, in: RoundedRectangle(cornerRadius: TallyRadius.card, style: .continuous))
                }
            }
        }
    }
}

// MARK: - Small shared pieces

private struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(TallyTypography.sectionHeader)
            .foregroundStyle(TallyColor.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct ChangeDigestChip: View {
    let summary: String
    var body: some View {
        HStack {
            Image(systemName: "sparkles")
            Text(summary)
            Spacer()
        }
        .font(TallyTypography.footnote)
        .foregroundStyle(TallyColor.accent)
        .padding(.horizontal, TallySpacing.md)
        .padding(.vertical, TallySpacing.sm)
        .background(TallyColor.bgCard, in: Capsule())
    }
}
