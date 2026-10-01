import SwiftUI
import TallyDesignSystem
import TallyDomain
import TallyStrings

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
                    ContentUnavailableView(String(localized: L10n.Dashboard.failedTitle()), systemImage: "house",
                                           description: Text(L10n.Dashboard.failedDescription()))
                        .padding(.top, TallySpacing.xxxl)
                case .glance:
                    // perf-app-runtime.md §2.4 L4 (decision D-P1): the sealed glance's hero count and
                    // due-soon rows paint first; the rest are skeletons until the full projection.
                    HeroSection(hero: model.dashboard.hero, isGlance: true)
                        .onAppear { LaunchSignpost.glancePainted() }
                    GlanceSkeletonSection(title: L10n.Dashboard.nextUpHeader())
                    GlanceSkeletonSection(title: L10n.Dashboard.needsAttentionHeader())
                    DueSoonSection(items: model.dashboard.dueSoon)
                case .loaded:
                    HeroSection(hero: model.dashboard.hero)
                        .onAppear { LaunchSignpost.glancePainted() }
                    if let summary = model.dashboard.changeDigestSummary {
                        ChangeDigestChip(summary: summary)
                    }
                    NextUpSection(items: model.dashboard.nextUp)
                    NeedsAttentionSection(items: model.dashboard.needsAttention)
                    // M3-C (UX-WP-12): the reminders tip, once work is due; renders nothing otherwise.
                    RemindersTip(hasUpcomingDueItem: !model.dashboard.dueSoon.isEmpty, isSampleData: model.isSampleData)
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
        .refreshable { await model.refreshUntilSettledOrDelayed() }
        .navigationTitle(String(localized: L10n.Dashboard.navigationTitle()))
    }

    @ViewBuilder
    private var header: some View {
        if let name = model.studentDisplayName {
            Text(L10n.Dashboard.greeting(Self.greetingWord(model.greeting), name))
                .font(TallyTypography.subheadline)
                .foregroundStyle(TallyColor.textSecondary)
        }
    }

    /// `HomeProjection.Greeting`'s raw value is itself the English word ("morning"/"afternoon"/
    /// "evening"); `HomeProjection.swift` is not this stream's file, so this switches on the case
    /// (not its `rawValue`) rather than editing that enum to add a localized label.
    private static func greetingWord(_ greeting: HomeProjection.Greeting) -> String {
        switch greeting {
        case .morning: String(localized: L10n.Dashboard.greetingMorning())
        case .afternoon: String(localized: L10n.Dashboard.greetingAfternoon())
        case .evening: String(localized: L10n.Dashboard.greetingEvening())
        }
    }
}

/// The first-load skeleton: the hero's shape with a progress indicator, never fabricated values.
private struct DashboardLoadingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: TallySpacing.md) {
            ProgressView()
                .tint(TallyColor.textOnHero)
            Text(L10n.Dashboard.loading())
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
///
/// Plan 08 G-5 (XG-03): under the figures, "2 courses not included ⓘ" when some courses are left
/// out of the average (the bubble lists each with its reason), or, when nothing can be averaged and
/// the school does not appear to keep grades in Canvas, a dash and "Grades aren't in Canvas ⓘ".
/// A11Y-07's single hero element keeps its label ("Average of 5 courses, 88.3%"); in the
/// not-in-Canvas variant the dash is hidden from VoiceOver, which reads the caption and then the
/// labelled ⓘ button (a control is never combined into the figures' element).
struct HeroSection: View {
    let hero: DashboardProjection.Hero
    /// The launch's glance paint: the percentage is a skeleton until the full projection.
    var isGlance = false
    @State private var showsInfo = false
    @Environment(\.locale) private var locale

    var body: some View {
        let caption = HeroCaption(hero)
        VStack(alignment: .leading, spacing: TallySpacing.md) {
            VStack(alignment: .leading, spacing: TallySpacing.md) {
                // Plan 08 L10N-01 exemplar: a plural key in the TallyStrings catalog, same English text.
                // Plan 08 G-5 (XG-02): N counts only the courses averaged; with none, there is no
                // average to caption.
                if hero.averagedCount > 0 {
                    Text(L10n.Dashboard.averageOfCourses(hero.averagedCount))
                        .font(TallyTypography.footnote)
                        .foregroundStyle(TallyColor.textOnHero2)
                }

                if hero.overallPercent == nil, hero.averagedCount > 0, isGlance {
                    // The glance carries no percentage (encryption.md §3.3): a skeleton, never "0%".
                    Text("00.0%")
                        .font(.system(.largeTitle, design: .serif).bold())
                        .foregroundStyle(TallyColor.textOnHero)
                        .redacted(reason: .placeholder)
                        .accessibilityHidden(true)
                } else if let percent = hero.overallPercent {
                    HStack(alignment: .firstTextBaseline, spacing: TallySpacing.sm) {
                        // §3.3 "Percent": `.percent` FormatStyle, not a hand-appended "%".
                        Text(percent.formatted(.percent.scale(1).precision(.fractionLength(1)).locale(locale)))
                            .font(.system(.largeTitle, design: .serif).bold())
                            .foregroundStyle(TallyColor.textOnHero)
                            .monospacedDigit()
                        if let band = hero.overallBand {
                            Text(bandLabel(band))
                                .font(TallyTypography.sectionHeader)
                                .foregroundStyle(TallyColor.brandGold)
                        }
                    }
                } else if caption == .notInCanvas {
                    Text(verbatim: GradeNotInCanvas.dash)
                        .font(.system(.largeTitle, design: .serif).bold())
                        .foregroundStyle(TallyColor.textOnHero)
                } else {
                    Text(L10n.Dashboard.noGradesYet())
                        .font(TallyTypography.body)
                        .foregroundStyle(TallyColor.textOnHero2)
                }
            }
            // The figures read as one element; the footer's refresh button stays its own element
            // (perf-app-runtime.md §3 item 7: never combine children that include a control).
            .accessibilityElement(children: .combine)
            // The dash says nothing VoiceOver should read: the caption below does.
            .accessibilityHidden(caption == .notInCanvas)

            if caption != .noRow {
                captionRow(caption)
            }

            FreshnessFooter()
        }
        .padding(TallySpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TallyColor.bgBrand, in: RoundedRectangle(cornerRadius: TallyRadius.hero, style: .continuous))
    }

    @ViewBuilder
    private func captionRow(_ caption: HeroCaption) -> some View {
        switch caption {
        case .noRow:
            EmptyView()
        case .notIncluded(let count):
            HStack(spacing: 0) {
                Text(L10n.Dashboard.coursesNotIncluded(count))
                    .font(TallyTypography.footnote)
                    .foregroundStyle(TallyColor.textOnHero2)
                GradeInfoButton(label: Text(L10n.Dashboard.notIncludedButton()), isPresented: $showsInfo) {
                    GradeInfoBubble(title: L10n.Dashboard.notIncludedTitle(),
                                    offersTellMySchool: hero.exclusions[.keptOutsideCanvas] != nil) {
                        HeroExclusionList()
                    }
                }
                .tint(TallyColor.textOnHero)
                // The glance has no course rows to list: the button waits for the projection.
                .disabled(isGlance)
            }
        case .notInCanvas:
            HStack(spacing: 0) {
                Text(L10n.Dashboard.heroNotInCanvas())
                    .font(TallyTypography.footnote)
                    .foregroundStyle(TallyColor.textOnHero2)
                GradeInfoButton(label: Text(L10n.Dashboard.notInCanvasButton()), isPresented: $showsInfo) {
                    GradeInfoBubble(scope: .school)
                }
                .tint(TallyColor.textOnHero)
            }
        }
    }

    /// §3.3 "Letter grades": the letters are Canvas's own grading scheme and stay untranslated;
    /// "Passing"/"Failing" (a pass/fail course's band) are words, and are catalog keys.
    private func bandLabel(_ band: GradeBand) -> String {
        switch band {
        case .aRange: "A"
        case .bRange: "B"
        case .cRange: "C"
        case .dRange: "D"
        case .fRange: "F"
        case .passing: String(localized: L10n.Dashboard.bandPassing())
        case .failing: String(localized: L10n.Dashboard.bandFailing())
        case .unknown: ""
        }
    }
}

/// Which caption row the hero shows under its figures (plan 08 G-5). Pure, so hosted tests pin it.
nonisolated enum HeroCaption: Equatable, Sendable {
    /// Every course is averaged (the flagship), or there is nothing to caption.
    case noRow
    /// Some courses are averaged and `count` are left out: "2 courses not included ⓘ".
    case notIncluded(Int)
    /// Nothing is averaged and the school does not appear to keep grades in Canvas: the dash and
    /// "Grades aren't in Canvas ⓘ".
    case notInCanvas

    init(_ hero: DashboardProjection.Hero) {
        let excluded = hero.courseCount - hero.averagedCount
        if hero.averagedCount > 0 {
            self = excluded > 0 ? .notIncluded(excluded) : .noRow
        } else {
            self = hero.school == .noneInCanvas ? .notInCanvas : .noRow
        }
    }
}

/// The courses left out of the average, each with its reason: the Home course rows (plan 08 §4.4
/// row 17) through `HeroExclusion`, in Canvas order. Read when the bubble opens, never in the
/// Dashboard's own body.
struct HeroExclusionList: View {
    @Environment(HomeModel.self) private var model: HomeModel?

    var body: some View {
        let courses = model?.courses ?? []
        VStack(alignment: .leading, spacing: TallySpacing.sm) {
            ForEach(courses.indices, id: \.self) { index in
                if let reason = HeroExclusion.reason(HeroExclusion.status(of: courses[index])) {
                    HStack(alignment: .firstTextBaseline, spacing: TallySpacing.sm) {
                        Text(verbatim: courses[index].code)
                            .font(TallyTypography.cardTitle)
                            .foregroundStyle(TallyColor.textPrimary)
                        Spacer(minLength: TallySpacing.sm)
                        Text(reason)
                            .font(TallyTypography.footnote)
                            .foregroundStyle(TallyColor.textSecondary)
                            .multilineTextAlignment(.trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

// MARK: - Glance skeletons

/// A section the glance cannot fill (it carries no priorities or alerts): its header and two
/// redacted rows, never fabricated values.
private struct GlanceSkeletonSection: View {
    let title: LocalizedStringResource

    var body: some View {
        VStack(alignment: .leading, spacing: TallySpacing.sm) {
            SectionHeader(title: title)
            ForEach(0..<2, id: \.self) { _ in
                Text(L10n.Dashboard.skeletonRow())
                    .font(TallyTypography.cardTitle)
                    .padding(TallySpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(TallyColor.bgCard, in: RoundedRectangle(cornerRadius: TallyRadius.card, style: .continuous))
                    .redacted(reason: .placeholder)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(L10n.Dashboard.skeletonSectionSpoken(String(localized: title))))
    }
}

// MARK: - Next up

private struct NextUpSection: View {
    let items: [DashboardProjection.NextUpItem]

    var body: some View {
        VStack(alignment: .leading, spacing: TallySpacing.sm) {
            SectionHeader(title: L10n.Dashboard.nextUpHeader())
            if items.isEmpty {
                Text(L10n.Dashboard.nextUpEmpty()).font(TallyTypography.body).foregroundStyle(TallyColor.textSecondary)
            } else {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: TallySpacing.xs) {
                        HStack {
                            Text(item.title).font(TallyTypography.cardTitle)
                            Spacer()
                            Text(bandWord(item.band)).font(TallyTypography.caption).foregroundStyle(TallyColor.textSecondary)
                        }
                        // Plan 08 L10N-02: the reason's factors, phrased in the student's language.
                        Text(verbatim: DashboardText.reason(item.reasonFactors, courseCode: item.courseCode))
                            .font(TallyTypography.footnote).foregroundStyle(TallyColor.textSecondary)
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
        case .high: String(localized: L10n.Dashboard.bandHigh())
        case .medium: String(localized: L10n.Dashboard.bandMedium())
        case .low: String(localized: L10n.Dashboard.bandLow())
        }
    }
}

// MARK: - Needs attention

private struct NeedsAttentionSection: View {
    let items: [DashboardProjection.AttentionItem]

    var body: some View {
        VStack(alignment: .leading, spacing: TallySpacing.sm) {
            SectionHeader(title: L10n.Dashboard.needsAttentionHeader())
            if items.isEmpty {
                Text(L10n.Dashboard.needsAttentionEmpty()).font(TallyTypography.body).foregroundStyle(TallyColor.textSecondary)
            } else {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: TallySpacing.md) {
                        Image(systemName: severityIcon(item.severity))
                            .foregroundStyle(severityColor(item.severity))
                        // Plan 08 L10N-02: the row's content, phrased in the student's language.
                        VStack(alignment: .leading, spacing: TallySpacing.xs) {
                            Text(verbatim: DashboardText.attentionTitle(item.content)).font(TallyTypography.cardTitle)
                            Text(verbatim: DashboardText.attentionSubtitle(item.content))
                                .font(TallyTypography.footnote).foregroundStyle(TallyColor.textSecondary)
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
            SectionHeader(title: L10n.Dashboard.weekAheadHeader())
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
            SectionHeader(title: L10n.Dashboard.dueSoonHeader())
            if items.isEmpty {
                Text(L10n.Dashboard.dueSoonEmpty()).font(TallyTypography.body).foregroundStyle(TallyColor.textSecondary)
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
    let title: LocalizedStringResource
    var body: some View {
        Text(title)
            .font(TallyTypography.sectionHeader)
            .foregroundStyle(TallyColor.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct ChangeDigestChip: View {
    let summary: DashboardProjection.ChangeSummary
    var body: some View {
        HStack {
            Image(systemName: "sparkles")
            // Plan 08 L10N-02: "6 changes since 2:13 PM", in the student's language and locale.
            Text(verbatim: DashboardText.changeSummary(summary))
            Spacer()
        }
        .font(TallyTypography.footnote)
        .foregroundStyle(TallyColor.accent)
        .padding(.horizontal, TallySpacing.md)
        .padding(.vertical, TallySpacing.sm)
        .background(TallyColor.bgCard, in: Capsule())
    }
}
