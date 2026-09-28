import SwiftUI
import TallyDesignSystem
import TallyDomain

/// UX-WP-13: the Dashboard, over the glance/snapshot (ux-ui.md §3.7.1, insights-at-a-glance.md
/// §1). Built purely from parameters — the same view serves a signed-in session and ASC-14's
/// sample mode (`SampleDataRootView`), differing only in what they pass in.
public struct DashboardView: View {
    let snapshot: CanvasSnapshot?
    let digest: ChangeDigest?
    let digestAsOf: Date?
    let freshness: FreshnessState
    let studentDisplayName: String?
    let onRefresh: () async -> Void

    public init(
        snapshot: CanvasSnapshot?, digest: ChangeDigest?, digestAsOf: Date?, freshness: FreshnessState,
        studentDisplayName: String? = nil, onRefresh: @escaping () async -> Void
    ) {
        self.snapshot = snapshot
        self.digest = digest
        self.digestAsOf = digestAsOf
        self.freshness = freshness
        self.studentDisplayName = studentDisplayName
        self.onRefresh = onRefresh
    }

    private var state: DashboardViewState {
        guard let snapshot else { return .empty }
        return DashboardBuilder.build(from: snapshot, digest: digest, digestAsOf: digestAsOf, now: Date())
    }

    public var body: some View {
        // Computed ONCE per body evaluation: `state` re-runs the full DashboardBuilder pipeline
        // (PriorityScore/AlertEngine over every assignment) every time it's read, and the
        // previous version of this file read it six separate times in one body. Same for the
        // freshness presentation, read fresh below instead of re-deriving it in every section.
        let currentState = state
        let presentation = FreshnessPresenter.present(freshness, now: Date())
        return ScrollView {
            VStack(alignment: .leading, spacing: TallySpacing.xxl) {
                // The stale breadcrumb (ux-ui.md §3.3), as a plain leading element rather than
                // `.safeAreaBar` — this screen's own top-of-scroll content, not a floating bar.
                if let breadcrumb = presentation.longText {
                    FreshnessBreadcrumb(text: breadcrumb)
                }
                header
                if snapshot == nil {
                    ContentUnavailableView("No dashboard yet", systemImage: "house",
                                           description: Text("Sign in, or explore with sample data, to see your dashboard."))
                        .padding(.top, TallySpacing.xxxl)
                } else {
                    HeroSection(hero: currentState.hero, presentation: presentation, onRefresh: onRefresh)
                    if let summary = currentState.changeDigestSummary {
                        ChangeDigestChip(summary: summary)
                    }
                    NextUpSection(items: currentState.nextUp)
                    NeedsAttentionSection(items: currentState.needsAttention)
                    WeekAheadSection(days: currentState.weekAhead)
                    DueSoonSection(items: currentState.dueSoon)
                }
            }
            .padding(.horizontal, TallySpacing.screenMargin)
            .padding(.bottom, TallySpacing.xxxl)
        }
        .background(TallyColor.bgCanvas)
        .refreshable { await onRefresh() }
        .navigationTitle("Dashboard")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: TallySpacing.xs) {
            if let name = studentDisplayName {
                Text("Good \(timeOfDayGreeting), \(name)")
                    .font(TallyTypography.subheadline)
                    .foregroundStyle(TallyColor.textSecondary)
            }
        }
    }

    private var timeOfDayGreeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 0..<12: "morning"
        case 12..<17: "afternoon"
        default: "evening"
        }
    }
}

// MARK: - Hero ("Average of N courses")

private struct HeroSection: View {
    let hero: DashboardViewState.Hero
    let presentation: FreshnessPresenter.Presentation
    let onRefresh: () async -> Void

    var body: some View {
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

            HStack {
                Text(presentation.shortText)
                    .font(TallyTypography.footnote)
                    .foregroundStyle(TallyColor.textOnHero2)
                Spacer()
                Button {
                    Task { await onRefresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 44, height: 44)
                }
                .disabled(presentation.action == .none)
                .accessibilityLabel("Refresh")
            }
        }
        .padding(TallySpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TallyColor.bgBrand, in: RoundedRectangle(cornerRadius: TallyRadius.hero, style: .continuous))
        .accessibilityElement(children: .combine)
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
    let items: [DashboardViewState.NextUpItem]

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
    let items: [DashboardViewState.AttentionItem]

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
    let days: [DashboardViewState.WeekDay]

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
    let items: [DashboardViewState.DueItem]

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

/// UX-WP-06: the subtle stale breadcrumb (ux-ui.md §3.3). Shown only via `.safeAreaBar(edge:
/// .top)` when `FreshnessPresenter` produces a `longText` (delayed/offline/failed/authExpired
/// with saved data on screen).
struct FreshnessBreadcrumb: View {
    let text: String
    var body: some View {
        Text(text)
            .font(TallyTypography.footnote)
            .foregroundStyle(TallyColor.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, TallySpacing.screenMargin)
            .padding(.vertical, TallySpacing.sm)
            .background(.orange.opacity(0.16))
            .accessibilityAddTraits(.updatesFrequently)
    }
}
