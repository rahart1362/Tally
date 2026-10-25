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
    /// UX-SPARK-2: the hero's overall trend (PRD §2.A), computed off the main actor and cached by
    /// snapshot (`CourseSparklineModel`, shared with the Courses tab's own cache pattern). Loaded
    /// by `.task(id:)` below, after the first paint — it never delays `Launch.GlancePaint`.
    @State private var trend = CourseSparklineModel()
    /// UX1-35: hides `header`'s greeting in parent mode, where the switcher above already names
    /// the student.
    @Environment(\.isParentModeHome) private var isParentModeHome
    /// UX1-11: the tab root's own content margin, read from the container width so Pro Max's
    /// large title and this screen's hero/cards/headers share one left edge (20 pt on a wide
    /// phone, else the static 16 pt) instead of the title alone picking up the system's wider
    /// margin.
    @State private var screenMargin: CGFloat = TallySpacing.screenMargin
    /// Idea 10 ("Add this week to Calendar"): the draft the system's per-item sheet is showing,
    /// and the rest of the week's drafts still to walk through once it closes.
    @State private var weekAddDraft: CalendarEventDraft?
    @State private var weekAddQueue: [CalendarEventDraft] = []
    /// Idea 11 ("Send my week"): `UserState.hideCourseNamesInNotifications` (R10), read directly
    /// rather than through `SettingsModel` -- this screen only ever reads it, like
    /// `ReminderPipeline` does off the main actor. Loaded once per appearance, like `trend` above;
    /// a setting changed in Settings and shared again in the very same visit, without ever
    /// backgrounding or refreshing the app in between, would still share by the value this screen
    /// loaded before that change (the same visit-scoped staleness `trend` already accepts).
    @State private var hideCourseNamesInShare = false

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
                    // ux-fp2 D20: inside this ScrollView the system view reports the visible height,
                    // not its content's; `TallyUnavailableView` is as tall as its content at AX sizes.
                    TallyUnavailableView(Text(L10n.Dashboard.failedTitle()), systemImage: "house",
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
                    HeroSection(hero: model.dashboard.hero, overall: trend.overall)
                        .onAppear { LaunchSignpost.glancePainted() }
                    if let summary = model.dashboard.changeDigestSummary {
                        ChangeDigestChip(summary: summary)
                    }
                    NextUpSection(items: model.dashboard.nextUp)
                    NeedsAttentionSection(items: model.dashboard.needsAttention)
                    // M3-C (UX-WP-12): the reminders tip, once work is due; renders nothing otherwise.
                    RemindersTip(hasUpcomingDueItem: !model.dashboard.dueSoon.isEmpty, isSampleData: model.isSampleData)
                    // EB-20b: the Home's own copy of Settings > Subscription's renewal-reminder
                    // banner, for a student who never opens Settings; renders nothing unless a
                    // reminder is due and notifications are off.
                    RenewalReminderHomeBanner()
                    WeekAheadSection(days: model.dashboard.weekAhead,
                                     onAddWeek: { startAddingWeek(model.dashboard.weekAhead) },
                                     shareText: WeekShareText.text(days: model.dashboard.weekAhead,
                                                                   hideCourseNames: hideCourseNamesInShare))
                    // Idea 3 (`ideas1/report.md` "Surface \"Momentum\" streak on the Dashboard"):
                    // the existing Insights streak, reused verbatim. Renders nothing without a
                    // current streak, or in parent mode (`MomentumStreakRow`).
                    MomentumStreakRow(streak: model.insightsScreen.streak, isParentModeHome: isParentModeHome)
                    DueSoonSection(items: model.dashboard.dueSoon)
                }
            }
            .padding(.horizontal, screenMargin)
            .padding(.bottom, TallySpacing.xxxl)
        }
        .background(TallyColor.bgCanvas)
        .tallyReadsScreenMargin(into: $screenMargin)
        // UX-SPARK-2: the same trend input the Courses tab's sparklines use; this task runs after
        // the first paint and is cancelled/retried exactly like `CoursesScreen`'s.
        .task(id: model.insightsScreen.trendInput) { await trend.load(model.insightsScreen.trendInput) }
        // Idea 11: loaded once per appearance, like `trend` above.
        .task { hideCourseNamesInShare = await model.userState.load().hideCourseNamesInNotifications }
        // Awaits the model-owned refresh until it settles or the live budget passes; never ties
        // the run to this view's task (plan 06 row 7, SH-2).
        .refreshable { await model.refreshUntilSettledOrDelayed() }
        // D01: content scrolled past the top stayed visible, blurred, under the inline title and
        // the status bar, even at rest at the bottom of the scroll. R4 (round 3): the large-title
        // variant, so the opaque fill never paints over "Dashboard" at rest.
        .tallyLargeTitleScreenChrome()
        .navigationTitle(String(localized: L10n.Dashboard.navigationTitle()))
        // Idea 10: walks the queue one system sheet at a time -- each one is its own
        // zero-permission confirm (R6); this only decides what opens next. Cancelling one item
        // (the system editor's own Cancel) still advances to the next, the same as a tap on
        // "Add": a bulk walk that stopped dead on the first skip would defeat the point of it.
        .sheet(item: $weekAddDraft) { draft in
            AddToCalendarView(draft: draft) { advanceWeekAddQueue() }
                .ignoresSafeArea()
        }
    }

    /// Idea 10: queues every draft but the first (shown at once) behind it.
    private func startAddingWeek(_ days: [DashboardProjection.WeekDay]) {
        var queue = WeekAheadCalendarDraft.drafts(for: days, accountHost: model.account.host)
        guard !queue.isEmpty else { return }
        weekAddDraft = queue.removeFirst()
        weekAddQueue = queue
    }

    private func advanceWeekAddQueue() {
        guard !weekAddQueue.isEmpty else {
            weekAddDraft = nil
            return
        }
        weekAddDraft = weekAddQueue.removeFirst()
    }

    @ViewBuilder
    private var header: some View {
        // UX1-35: in parent mode the switcher right above already names the student ("Rowan
        // Sample"), so repeating it here ("Good afternoon, Rowan Sample") on every leg greeted
        // the parent with the student's own name instead of the parent's.
        if !isParentModeHome, let name = model.studentDisplayName {
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
        // ux-fp6 D33: the shared hero background + dark-only hairline. See `tallyHeroBackground()`.
        .tallyHeroBackground()
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
    /// UX-SPARK-2: the overall trend (PRD §2.A), `nil` under `GradeTrend.minimumPoints` or while
    /// still loading (never a placeholder) — the grade block then keeps the row's full width.
    var overall: CourseSparklinePoints?
    @State private var showsInfo = false
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let caption = HeroCaption(hero)
        VStack(alignment: .leading, spacing: TallySpacing.md) {
            // UX-SPARK-2: two zones — the figures on the left (unchanged) and, once there is a
            // trend to show, it fills the rest, vertically centred; at accessibility sizes it
            // moves below instead (the same reflow rule every other two-part row on this screen
            // uses).
            TallyReflowStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: TallySpacing.md) {
                    // Plan 08 L10N-01 exemplar: a plural key in the TallyStrings catalog, same English text.
                    // Plan 08 G-5 (XG-02): N counts only the courses averaged; with none, there is no
                    // average to caption.
                    if hero.averagedCount > 0 {
                        // L10N-04: a stable id (the Audit tour used this English text — "Average
                        // of 5 courses" — as its "the projection landed" signal, which Spanish
                        // changes to "Promedio de 5 cursos").
                        Text(L10n.Dashboard.averageOfCourses(hero.averagedCount))
                            .font(TallyTypography.footnote)
                            .foregroundStyle(TallyColor.textOnHero2)
                            .accessibilityIdentifier("dashboard.hero.averageOfCourses")
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

                // The trend only ever shows over a real percentage, never the glance's skeleton.
                if !isGlance, hero.overallPercent != nil, let overall {
                    TallyReflowSpacer(minLength: 0)
                    CourseSparklineView(points: overall, width: nil, height: CourseSparklineView.heroHeight,
                                        tint: TallyColor.brandGold, background: .hero)
                        .padding(.leading, typeSize.isAccessibilitySize ? 0 : TallySpacing.md)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("dashboard.sparkline")
                }
            }
            // The figures (and, with one, the trend) read as one element — A11Y-07: the trend
            // sentence (the sparkline's own accessibility label) is appended automatically, in
            // document order, rather than a separate element. The footer's refresh button stays
            // its own element (perf-app-runtime.md §3 item 7: never combine children that include
            // a control).
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
        // ux-fp6 D33: the shared hero background + dark-only hairline. See `tallyHeroBackground()`.
        .tallyHeroBackground()
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
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let courses = model?.courses ?? []
        VStack(alignment: .leading, spacing: TallySpacing.sm) {
            ForEach(courses.indices, id: \.self) { index in
                if let reason = HeroExclusion.reason(HeroExclusion.status(of: courses[index])) {
                    // ux-fp2 D02: the course code never breaks; from AX1 up the reason goes under it.
                    TallyReflowStack(alignment: .firstTextBaseline, spacing: TallySpacing.sm) {
                        Text(verbatim: courses[index].code)
                            .font(TallyTypography.cardTitle)
                            .foregroundStyle(TallyColor.textPrimary)
                            .tallyReflowValue()
                        TallyReflowSpacer(minLength: TallySpacing.sm)
                        Text(reason)
                            .font(TallyTypography.footnote)
                            .foregroundStyle(TallyColor.textSecondary)
                            .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

// MARK: - Momentum streak (Idea 3: ideas1/report.md "Surface \"Momentum\" streak on the Dashboard")

/// Whether the Dashboard's one-line streak row shows, and what it says. Pure, so
/// `DashboardMomentumStreakTests` pins it without SwiftUI (the same pattern `HeroCaption` above
/// uses). The streak itself (`StreakInsight.days`/`.headline`) is computed once, in the
/// projection layer, by `InsightsBuilder.streak` (`HomeProjector.project(now:)` ->
/// `ScreenProjections.build` -> `InsightsProjection.streak`) — this only decides whether that
/// already-computed, already-localized value is shown here.
nonisolated enum DashboardMomentumStreak: Equatable, Sendable {
    /// `StreakInsight.headline`, unchanged: the existing `L10n.Insights.streakDays` string.
    case row(String)
    /// No current streak (`days == 0`), or parent mode: the brief calls for NOT parent mode
    /// "unless the report shows a parent-appropriate streak" — it doesn't — and for hiding the
    /// line rather than showing `L10n.Insights.streakNone` on the Dashboard.
    case hidden

    init(_ streak: StreakInsight, isParentModeHome: Bool) {
        self = (!isParentModeHome && streak.days > 0) ? .row(streak.headline) : .hidden
    }
}

/// One line, under Week-ahead, reusing `StreakInsight`'s own headline verbatim — zero new copy.
/// Renders nothing when `DashboardMomentumStreak` says to hide it (the `RemindersTip` pattern).
private struct MomentumStreakRow: View {
    let streak: StreakInsight
    let isParentModeHome: Bool

    var body: some View {
        if case .row(let headline) = DashboardMomentumStreak(streak, isParentModeHome: isParentModeHome) {
            Label(headline, systemImage: "flame")
                .font(TallyTypography.footnote)
                .foregroundStyle(TallyColor.textSecondary)
                .accessibilityIdentifier("dashboard.momentumStreak")
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
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: TallySpacing.sm) {
            SectionHeader(title: L10n.Dashboard.nextUpHeader())
            if items.isEmpty {
                Text(L10n.Dashboard.nextUpEmpty()).font(TallyTypography.body).foregroundStyle(TallyColor.textSecondary)
            } else {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: TallySpacing.xs) {
                        // ux-fp2 D02: below AX1 the band sits beside the title, as before; from AX1
                        // up the title takes the full width (it hyphenated in a narrow column beside
                        // the band, "Integra- / tion" at AX5) and the band ends the card: title,
                        // then reason, then band.
                        TallyReflowStack {
                            Text(item.title).font(TallyTypography.cardTitle)
                            TallyReflowSpacer()
                            if !typeSize.isAccessibilitySize {
                                band(item)
                            }
                        }
                        // Plan 08 L10N-02: the reason's factors, phrased in the student's language.
                        // D15: 48 h+ out, the due-date clause reads as a day (or, within the week,
                        // day-and-time) instead of ballooning into "Due in 396h" — `item.dueAt`
                        // lets it reuse the same frozen sentence Courses/To-Do show.
                        Text(verbatim: DashboardText.reason(item.reasonFactors, courseCode: item.courseCode,
                                                            dueAt: item.dueAt, locale: locale))
                            .font(TallyTypography.footnote).foregroundStyle(TallyColor.textSecondary)
                        if typeSize.isAccessibilitySize {
                            band(item)
                        }
                    }
                    .padding(TallySpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(TallyColor.bgCard, in: RoundedRectangle(cornerRadius: TallyRadius.card, style: .continuous))
                }
            }
        }
    }

    /// UX1-15: a bare grey caption ("High"/"Medium"/"Low") on every card read as noise, three
    /// identical "High" rows in a row, and was a different treatment from To-Do's flag + word
    /// chip for the same priority. High reuses that chip; Medium/Low drop the label (the reason
    /// line above already explains the row without repeating its rank).
    @ViewBuilder
    private func band(_ item: DashboardProjection.NextUpItem) -> some View {
        if item.band == .high {
            StatusChip(symbol: "flag", text: L10n.Dashboard.bandHigh(), tone: .warning)
                .tallyReflowValue()
        }
    }
}

// MARK: - Needs attention

private struct NeedsAttentionSection: View {
    let items: [DashboardProjection.AttentionItem]
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: TallySpacing.sm) {
            SectionHeader(title: L10n.Dashboard.needsAttentionHeader())
            if items.isEmpty {
                Text(L10n.Dashboard.needsAttentionEmpty()).font(TallyTypography.body).foregroundStyle(TallyColor.textSecondary)
            } else {
                ForEach(items) { item in
                    // ux-fp2 follow-up (FP-3): the icon column squeezed the title at AX5, which
                    // hyphenated long words ("Respira- / tion"). From AX1 up the icon sits above
                    // the text instead, which then takes the row's full width.
                    let layout = typeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: TallySpacing.xs))
                        : AnyLayout(HStackLayout(alignment: .top, spacing: TallySpacing.md))
                    layout {
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
    /// Idea 10 ("Add this week to Calendar"): starts walking the week's due items through the
    /// system's per-item calendar sheet, one at a time.
    let onAddWeek: () -> Void
    /// Idea 11 ("Send my week"): the plain-text summary `ShareLink` shares.
    let shareText: String
    /// R1/D09 (round 2): every column reserves this HEIGHT for the glyph row, busy or not — never
    /// the glyph's own WIDTH, which is what forced every Week-ahead column to be at least as wide
    /// as the AX5 icon (7 × 49 pt columns = 415 pt on a 390 pt screen; Gate 2's `R1-overflow.jpg`).
    @ScaledMetric(relativeTo: .caption2) private var glyphRowHeight: CGFloat = 14

    /// Both new rows need at least one due item this week to act on; an empty week has nothing to
    /// add or share.
    private var hasItemsThisWeek: Bool { days.contains { !$0.items.isEmpty } }
    /// UX1-16: every column reading "0" with nothing to mark today or explain the zeros; Due
    /// Soon's own empty line, right after this section, already says "nothing due soon."
    private var isAllZero: Bool { days.allSatisfy { $0.dueCount == 0 } }

    @ViewBuilder
    var body: some View {
        if !isAllZero {
            VStack(alignment: .leading, spacing: TallySpacing.sm) {
                SectionHeader(title: L10n.Dashboard.weekAheadHeader())
                // UX2-14: the day strip and (when there's something to act on) the Week-ahead
                // actions now share one card -- a divider, then the footer row -- instead of the
                // actions sitting below it as orphan text with no glyphs of their own.
                VStack(spacing: 0) {
                    // D09: `.center` (the default) pulled a busy column about 8 pt higher than its
                    // neighbours, since its extra glyph row made it taller; `.top` plus a row every
                    // column reserves the same HEIGHT for (round 2: never the WIDTH — R1) keeps every
                    // column's three rows aligned, at std and AX5 alike.
                    HStack(alignment: .top, spacing: TallySpacing.sm) {
                        ForEach(days) { day in
                            VStack(spacing: TallySpacing.xs) {
                                // UX1-16: the strip had no "today" marker and no dates, just seven
                                // narrow weekday letters (two "S", two "T" in the same week) --
                                // bolding and ringing the one column that is today, as Calendar's own
                                // week strip does, gives the reader a fixed point to read the rest from.
                                Text(day.date.formatted(.dateTime.weekday(.narrow)))
                                    .font(TallyTypography.caption)
                                    .fontWeight(day.isToday ? .semibold : .regular)
                                    .foregroundStyle(day.isToday ? TallyColor.accent : TallyColor.textSecondary)
                                // UX2-03 (regression from UX1-16): capped at AX1 the same way the
                                // glyph row below already caps the busy icon -- uncapped, the ring and
                                // the day number collided with their neighbours at AX5 (the layout
                                // check's own overlap finding: column "W, 14, 8" at x 15.3-81.7
                                // overlapping "T, 15, 2" at x 76.3). Pulled into its own `WeekDayMark`
                                // because `@ScaledMetric` reads the environment of the view that owns
                                // it, so the cap has to sit on an ANCESTOR of the view that computes the
                                // diameter, not merely on a sibling inside the same body.
                                WeekDayMark(day: day)
                                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                                Text("\(day.dueCount)")
                                    .font(TallyTypography.cardTitle)
                                    .foregroundStyle(day.isBusy ? TallyColor.warning : TallyColor.textPrimary)
                                // R1 (round 2): a zero-WIDTH spacer reserves the row's height for every
                                // column, busy or not — the glyph itself draws only on busy days, as an
                                // overlay that cannot widen the column (SwiftUI reports `.overlay`'s size
                                // as the base view's, not the overlaid content's). Capped at
                                // `.accessibility1` so the overlaid icon never balloons past a size that
                                // would crowd the rows above and below it at AX5.
                                Color.clear
                                    .frame(width: 0, height: glyphRowHeight)
                                    .overlay {
                                        if day.isBusy {
                                            Image(systemName: "exclamationmark.triangle")
                                                .font(.caption2)
                                                .foregroundStyle(TallyColor.warning)
                                                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                                        }
                                    }
                            }
                            // R1: lets every column shrink together instead of the row's width being the
                            // sum of each column's own natural (glyph-driven) width.
                            .frame(minWidth: 0, maxWidth: .infinity)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(TallySpacing.md)
                    if hasItemsThisWeek {
                        Divider()
                        WeekAheadActionsRow(onAddWeek: onAddWeek, shareText: shareText)
                    }
                }
                .background(TallyColor.bgCard, in: RoundedRectangle(cornerRadius: TallyRadius.card, style: .continuous))
            }
        }
    }
}

/// UX2-03: the Week ahead strip's day-number ring, on its own so an ancestor
/// `.dynamicTypeSize(...DynamicTypeSize.accessibility1)` modifier can cap `diameter` at AX1 --
/// `@ScaledMetric` reads the environment of the view that declares it, so the cap has to be
/// applied where this view is instantiated, not inside its own body. See `WeekAheadSection`.
private struct WeekDayMark: View {
    let day: DashboardProjection.WeekDay
    /// UX1-16: the day-number ring, the same role as Calendar's week strip's own day mark.
    @ScaledMetric(relativeTo: .caption2) private var diameter: CGFloat = 18

    var body: some View {
        Text(day.date.formatted(.dateTime.day()))
            .font(.caption2)
            .foregroundStyle(TallyColor.textSecondary)
            .frame(width: diameter, height: diameter)
            .overlay {
                if day.isToday {
                    Circle().strokeBorder(TallyColor.accent, lineWidth: 1.5)
                }
            }
    }
}

/// UX2-14: "Add This Week to Calendar" and "Send My Week" as a footer row inside the Week-ahead
/// card, below a divider from the day strip, instead of sitting outside the card as orphan text with
/// no glyphs of their own. Side by side at std, each a tappable area at least 44 pt tall;
/// `TallyReflowStack` stacks them (D02's pattern) once the accessibility sizes leave no room for two
/// columns.
private struct WeekAheadActionsRow: View {
    let onAddWeek: () -> Void
    let shareText: String

    var body: some View {
        TallyReflowStack(spacing: TallySpacing.sm) {
            Button(action: onAddWeek) {
                Label { Text(L10n.Dashboard.addWeekButton()) } icon: { Image(systemName: "calendar.badge.plus") }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityIdentifier("dashboard.addWeekToCalendar")
            ShareLink(item: shareText) {
                Label { Text(L10n.Dashboard.shareWeekButton()) } icon: { Image(systemName: "square.and.arrow.up") }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityIdentifier("dashboard.shareWeek")
        }
        .font(TallyTypography.subheadline)
        .padding(TallySpacing.md)
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
                    // ux-fp2 D02: from AX1 up the time goes under the title and course code, each
                    // on one line ("11:00 P / M" and "MATH / 122" at AX5).
                    TallyReflowStack {
                        VStack(alignment: .leading, spacing: TallySpacing.xs) {
                            Text(item.title).font(TallyTypography.cardTitle)
                            if let code = item.courseCode {
                                Text(code)
                                    .font(TallyTypography.footnote)
                                    .foregroundStyle(TallyColor.textSecondary)
                                    .tallyReflowValue()
                            }
                        }
                        TallyReflowSpacer()
                        if let due = item.dueAt {
                            // UX1-12: the section spans up to 7 days, but a bare time read as
                            // "today" regardless ("9:00 AM" for a Monday-morning item seen on a
                            // Sunday evening). `isToday` was decided where the projection's `now`
                            // already is (`DashboardProjection.dueSoon`); formatting the day name
                            // itself needs no clock of its own.
                            Text(item.isToday ? due.formatted(date: .omitted, time: .shortened)
                                 : due.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                                .font(TallyTypography.footnote)
                                .foregroundStyle(TallyColor.textSecondary)
                                .tallyReflowValue()
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
