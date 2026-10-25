import SwiftUI
import TallyDesignSystem
import TallyDomain
import TallyStrings

/// Course Detail's segments (ux-ui.md §3.7.3): no "People" tab; instructor contact is in Overview.
nonisolated enum CourseDetailSegment: String, CaseIterable, Identifiable {
    case overview, assignments, grades

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .overview: L10n.CourseDetail.segmentOverview()
        case .assignments: L10n.CourseDetail.segmentAssignments()
        case .grades: L10n.CourseDetail.segmentGrades()
        }
    }
}

/// UX-WP-15 / ARC E05b: Course Detail (ux-ui.md §3.7.3), a plain page pushed from Courses. It reads
/// `HomeModel.courseDetails`, built off the main actor; the category percentages come from
/// `CourseGradesModel` (the domain engine through `GradeWork`), and the what-if sheet from
/// `WhatIfModel`. The grade distribution shows only when Canvas gave score statistics, and it never
/// has in this build.
struct CourseDetailView: View {
    let courseID: CanvasID<Course>
    /// UX-SPARK: the same `CourseSparklineModel` instance `CoursesScreen` owns and loads, passed
    /// through `navigationDestination` so the hero's sparkline is never a separate computation.
    let sparklines: CourseSparklineModel
    @Environment(HomeModel.self) private var model
    @Environment(\.locale) private var locale
    @State private var segment: CourseDetailSegment = .overview
    @State private var grades = CourseGradesModel()
    /// Built by the What-If button's action, never in a view initialiser (perf-app-runtime.md §3 item 6).
    @State private var whatIf: WhatIfModel?

    var body: some View {
        Group {
            if let detail = model.courseDetails[courseID] {
                content(detail)
            } else {
                TallyUnavailableView(Text(L10n.CourseDetail.unavailableTitle()), systemImage: "books.vertical",
                                     description: Text(L10n.CourseDetail.unavailableDescription()))
                    // ux-fp2 D20: centred when it fits, scrolling when it does not (AX5), with the
                    // screen's own D01 chrome, since it can now scroll under the bar.
                    .tallyCenteredScrolling()
                    .tallyScreenChrome()
            }
        }
        .navigationTitle(model.courseDetails[courseID]?.name ?? String(localized: L10n.CourseDetail.navigationTitleFallback()))
        .navigationBarTitleDisplayMode(.inline)
        // Idea 9: Handoff to the Mac/iPad browser, the same URL "Open in Canvas" already builds
        // below. `nil` while sample data or an unsafe/missing URL both skips creating the activity
        // and retires one already published (CanvasHandoffActivity.webpageURL's doc comment).
        .userActivity(CanvasHandoffActivity.activityType,
                      element: CanvasHandoffActivity.webpageURL(for: model.courseDetails[courseID]?.canvasURL,
                                                                  accountHost: model.account.host,
                                                                  isSampleData: model.isSampleData)) { webpageURL, activity in
            CanvasHandoffActivity.configure(activity, webpageURL: webpageURL)
        }
    }

    private func content(_ detail: CourseDetailProjection) -> some View {
        List {
            Section {
                CourseHeroCard(detail: detail, sparkline: sparklines.series[detail.id])
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            Section {
                SegmentPicker(selection: $segment)
            }
            // D31 round 2: applied to the Section, which reaches every row inside it.
            .tallyRow()
            switch segment {
            case .overview: overview(detail)
            case .assignments: assignments(detail)
            case .grades: gradeTable(detail)
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await model.refreshUntilSettledOrDelayed() }
        // D27/D31: 16 pt edges and the Tally dark palette, matching the ScrollView tabs. The hero
        // section's own `.listRowBackground(Color.clear)` above still overrides this default.
        .tallyList()
        // D01: content scrolled past the top stayed visible, blurred, under the inline title, the
        // toolbar buttons and the status bar, even at rest.
        .tallyScreenChrome()
        .task(id: detail.gradeInput) { await grades.load(detail.gradeInput) }
        .sheet(isPresented: Binding(get: { whatIf != nil }, set: { if !$0 { whatIf = nil } })) {
            if let whatIf {
                // Idea 6 (FEAT-4): the sheet's "Save as goal" button, wired to the same per-course
                // goal storage the Overview section below reads and writes.
                WhatIfSheet(model: whatIf, onSaveGoal: { model.setCourseGoal($0, for: detail.id) })
            }
        }
        .toolbar {
            // Plan 08 XG-04 (G-3): the course's "grades kept outside Canvas" answer.
            ToolbarItem(placement: .topBarTrailing) {
                GradeOverrideMenu(courseID: detail.id)
            }
            // Sample data has no real Canvas to open (ASC-14).
            if !model.isSampleData, let url = detail.canvasURL {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        // A one-shot open: the Canvas Student app, else the browser (R20).
                        Task { await CanvasLinkOpener.open(url, accountHost: model.account.host, preference: model.canvasLinkPreference) }
                    } label: {
                        // L10N-03a's finding (its report §1.2): every already-CI-verified `L10n.*` use
                        // reaches `Text(L10n.…)` or `String(localized: L10n.…)`, never a bare
                        // `LocalizedStringResource` passed to another SwiftUI initializer directly, to
                        // avoid an unverified-overload compile risk with no local Xcode to check it.
                        Label { Text(L10n.CourseDetail.openInCanvas()) } icon: { Image(systemName: "safari") }
                    }
                }
            }
        }
    }

    // MARK: - Overview

    @ViewBuilder
    private func overview(_ detail: CourseDetailProjection) -> some View {
        // Plan 08 §4.4 row 5 and §4.5: the bubble's content, inline, for a course whose grades are
        // kept outside Canvas (the hero shows the dash).
        if case .keptOutside(let scope) = detail.grade.notInCanvas {
            Section {
                GradeInfoBubble(scope: scope)
                    .padding(.vertical, TallySpacing.sm)
            }
            // D31 round 2: applied to the Section, which reaches every row inside it.
            .tallyRow()
        }
        if let next = detail.nextDueText {
            Section {
                Text(next).font(TallyTypography.body)
            } header: {
                Text(L10n.CourseDetail.nextDueHeader())
                    .tallySectionText()
            }
            .tallyRow()
        }
        if !detail.recentGraded.isEmpty || detail.recentGradesNote != nil {
            Section {
                if let note = detail.recentGradesNote {
                    Text(verbatim: note)
                        .font(TallyTypography.body)
                        .foregroundStyle(TallyColor.textSecondary)
                }
                ForEach(detail.recentGraded) { item in
                    // ux-fp2 D02: from AX1 up the score goes under the title instead of beside it,
                    // on one line ("93.2/100" read "9 / 3.2/10 / 0" at AX5).
                    TallyReflowStack(alignment: .firstTextBaseline, spacing: TallySpacing.md) {
                        VStack(alignment: .leading, spacing: TallySpacing.xs) {
                            Text(item.title).font(TallyTypography.body)
                            if let posted = item.postedText {
                                Text(posted)
                                    .font(TallyTypography.footnote)
                                    .foregroundStyle(TallyColor.textSecondary)
                            }
                        }
                        TallyReflowSpacer(minLength: TallySpacing.sm)
                        StatusChip(symbol: "checkmark.seal", text: item.scoreText)
                            .valueStyle()
                            .tallyReflowValue()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(item.accessibilityLabel)
                    // D13: the separator started under the score chip's text, leaving a short,
                    // ragged hairline at the right edge; the whole row is the separator's leading
                    // edge instead.
                    .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                }
            } header: {
                Text(L10n.CourseDetail.recentGradesHeader())
                    .tallySectionText()
            }
            .tallyRow()
        }
        if !detail.weights.isEmpty {
            Section {
                CategoryWeightsChart(weights: detail.weights, title: String(localized: L10n.CourseDetail.categoryWeightsHeader()),
                                     summary: detail.weightsSummary)
                    .padding(.vertical, TallySpacing.sm)
            } header: {
                Text(L10n.CourseDetail.categoryWeightsHeader())
                    .tallySectionText()
            } footer: {
                Text(detail.weightsAreInstructorSet
                     ? L10n.CourseDetail.weightsSetByInstructor()
                     : L10n.CourseDetail.weightsPointsBased())
                    .tallySectionText()
            }
            .tallyRow()
        }
        // ux-ui.md §3.5: only when Canvas returns score statistics, never invented.
        if let distribution = detail.distribution {
            Section {
                Text(L10n.CourseDetail.gradeDistributionSentence(
                    Self.percent(distribution.minimum, locale: locale), Self.percent(distribution.maximum, locale: locale),
                    Self.percent(distribution.mean, locale: locale), Self.percent(distribution.yours, locale: locale)))
                    .accessibilityIdentifier("chart.distribution")
            } header: {
                Text(L10n.CourseDetail.gradeDistributionHeader())
                    .tallySectionText()
            }
            .tallyRow()
        }
        CourseGoalSection(courseID: detail.id)
        Section {
            if let setup = detail.whatIf {
                Button {
                    whatIf = WhatIfModel(setup: setup)
                } label: {
                    whatIfLabel
                }
                .accessibilityIdentifier("courseDetail.whatIf")
            } else if let reason = detail.whatIfUnavailable {
                // Plan 08 §4.4 row 6: disabled, with its explanation, rather than gone without a word.
                if reason.showsDisabledButton {
                    Button {} label: { whatIfLabel }
                        .disabled(true)
                        .accessibilityIdentifier("courseDetail.whatIf.disabled")
                }
                Text(reason.text)
                    .font(TallyTypography.footnote)
                    .foregroundStyle(TallyColor.textSecondary)
            }
        } header: {
            Text(L10n.CourseDetail.whatIfHeader())
                .tallySectionText()
        } footer: {
            if detail.whatIf != nil {
                Text(L10n.CourseDetail.whatIfFooter())
                    .tallySectionText()
            }
        }
        .tallyRow()
        if !detail.instructors.isEmpty {
            Section {
                ForEach(detail.instructors.indices, id: \.self) { index in
                    Label(detail.instructors[index], systemImage: "person")
                }
            } header: {
                Text(detail.instructors.count == 1 ? L10n.CourseDetail.instructorsHeaderOne() : L10n.CourseDetail.instructorsHeaderOther())
                    .tallySectionText()
            }
            .tallyRow()
        }
    }

    private var whatIfLabel: some View {
        Label {
            // UX1-21: `whatIfButtonNoBreak()` is the same text with a non-breaking hyphen in
            // "What-If", which broke as "Try What- / If Scores" at AX5 on both phones.
            // `whatIfButton()` itself is unchanged.
            Text(L10n.CourseDetail.whatIfButtonNoBreak())
        } icon: {
            Image(systemName: "flask")
        }
    }

    // MARK: - Assignments

    @ViewBuilder
    private func assignments(_ detail: CourseDetailProjection) -> some View {
        if detail.sections.isEmpty {
            Section {
                Text(L10n.CourseDetail.noAssignmentsYet())
                    .foregroundStyle(TallyColor.textSecondary)
            }
            .tallyRow()
        }
        ForEach(detail.sections) { section in
            Section {
                ForEach(section.rows) { row in
                    // ux-fp2 D02: from AX1 up the status chip and the score go under the title,
                    // each on one line.
                    TallyReflowStack(alignment: .top, spacing: TallySpacing.md) {
                        VStack(alignment: .leading, spacing: TallySpacing.xs) {
                            Text(row.title).font(TallyTypography.body)
                            if let due = row.dueText {
                                Text(due)
                                    .font(TallyTypography.footnote)
                                    .foregroundStyle(TallyColor.textSecondary)
                            }
                        }
                        TallyReflowSpacer(minLength: TallySpacing.sm)
                        TallyReflowValueColumn(spacing: TallySpacing.xs) {
                            if let status = row.status {
                                StatusChip(symbol: status.symbol, text: status.label, tone: status.tone)
                            }
                            if let score = row.scoreText {
                                Text(score)
                                    .font(TallyTypography.subheadline)
                                    .foregroundStyle(TallyColor.textPrimary)
                                    .monospacedDigit()
                                    .tallyReflowValue()
                            }
                        }
                        .layoutPriority(1)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(row.accessibilityLabel)
                }
            } header: {
                // D07: was `Section(section.title)`'s own default header text (the same
                // under-contrast grey); an explicit header lets it take `tallySectionText()`.
                Text(section.title)
                    .tallySectionText()
            }
            .tallyRow()
        }
    }

    // MARK: - Grades

    @ViewBuilder
    private func gradeTable(_ detail: CourseDetailProjection) -> some View {
        Section {
            ForEach(detail.categories) { category in
                // ux-fp2 D02: the same row rule ("Lab Re- / ports" beside "90.7%" at AX5).
                TallyReflowStack(alignment: .firstTextBaseline, spacing: TallySpacing.md) {
                    VStack(alignment: .leading, spacing: TallySpacing.xs) {
                        Text(category.name).font(TallyTypography.body)
                        if let weightText = category.weightText {
                            Text(weightText)
                                .font(TallyTypography.footnote)
                                .foregroundStyle(TallyColor.textSecondary)
                        }
                    }
                    TallyReflowSpacer(minLength: TallySpacing.sm)
                    // Plan 08 §4.4 row 5: names only for a course whose grades are not in Canvas.
                    if detail.grade.notInCanvas == nil {
                        Text(categoryPercent(category, in: detail))
                            .font(TallyTypography.subheadline)
                            .foregroundStyle(TallyColor.textPrimary)
                            .monospacedDigit()
                            .tallyReflowValue()
                    }
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text(L10n.CourseDetail.categoriesHeader())
                .tallySectionText()
        } footer: {
            Group {
                switch detail.grade.notInCanvas {
                case .keptOutside?:
                    Text(L10n.CourseDetail.notInCanvasLine())
                case .notGraded?:
                    Text(L10n.Grades.notGradedDetail())
                case nil:
                    if detail.showsCategoryPercentages {
                        Text(L10n.CourseDetail.currentGradeCountsGradedOnly())
                    } else if let hiddenReason = detail.grade.hiddenReason {
                        Text(verbatim: hiddenReason)
                    } else {
                        Text(L10n.CourseDetail.lettersOnlyFooter())
                    }
                }
            }
            .tallySectionText()
        }
        .tallyRow()
    }

    private func categoryPercent(_ category: CategoryRow, in detail: CourseDetailProjection) -> String {
        guard detail.showsCategoryPercentages else { return String(localized: L10n.CourseDetail.categoryHidden()) }
        guard let percent = grades.categoryPercents[category.id] else {
            return String(localized: L10n.CourseDetail.categoryNoGradesYet())
        }
        return Self.percent(percent, locale: locale)
    }

    /// §3.3 "Percent": `.percent` FormatStyle, not a hand-appended "%", so the sign's position and
    /// spacing follow the locale (`percentText`/`spokenPercent`/`shareText`'s own fix, via
    /// `TallyFormat`, is in `ScreenFormatter.swift`; this helper duplicates only the 1-decimal case
    /// those functions already prove byte-identical for en_US, since this view holds no
    /// `ScreenFormatter` to call them on).
    private static func percent(_ value: Double, locale: Locale) -> String {
        value.formatted(.percent.scale(1).precision(.fractionLength(1)).locale(locale))
    }
}

/// Idea 2 (FEAT-4): the student's own per-course grade goal — a small entry point that wires the
/// existing dormant goal math (`CourseHealthRules.evaluate`'s `goal` parameter, via `HomeModel`)
/// so the course's health chip and "why" reasons reflect it. A plain `Stepper`, the same pattern
/// `WhatIfGoalSection`'s own goal-percent control already uses (ux-ui.md §3.7.3); "Set a goal"
/// starts it at `WhatIfModel.defaultGoalPercent` (90%), persisted at once like every other
/// per-course answer on this screen (`GradeOverrideMenu`, below).
private struct CourseGoalSection: View {
    let courseID: CanvasID<Course>
    @Environment(HomeModel.self) private var model
    @Environment(\.locale) private var locale

    private var goal: Double? { model.courseGoal(for: courseID) }

    var body: some View {
        Section {
            if let goal {
                Stepper(value: Binding(get: { goal }, set: { model.setCourseGoal($0, for: courseID) }),
                        in: 50...100, step: 1) {
                    Text(L10n.CourseDetail.goalStepperLabel(Self.percentText(goal, locale: locale)))
                }
                .accessibilityIdentifier("courseDetail.goal.stepper")
                Button(role: .destructive) {
                    model.setCourseGoal(nil, for: courseID)
                    AccessibilityAnnouncer.announce(String(localized: L10n.CourseDetail.goalRemovedConfirmation()))
                } label: {
                    Text(L10n.CourseDetail.goalRemove())
                }
                .accessibilityIdentifier("courseDetail.goal.remove")
            } else {
                Button {
                    model.setCourseGoal(WhatIfModel.defaultGoalPercent, for: courseID)
                } label: {
                    Label { Text(L10n.CourseDetail.goalSetButton()) } icon: { Image(systemName: "target") }
                }
                .accessibilityIdentifier("courseDetail.goal.set")
            }
        } header: {
            Text(L10n.CourseDetail.goalHeader()).tallySectionText()
        } footer: {
            Text(L10n.CourseDetail.goalFooter()).tallySectionText()
        }
        // D31 round 2: applied to the Section, which reaches every row inside it.
        .tallyRow()
    }

    /// "90%" (§3.3 "Percent"): the stepper's step is 1, so this is already a whole number.
    private static func percentText(_ value: Double, locale: Locale) -> String {
        value.formatted(.percent.scale(1).precision(.fractionLength(0)).locale(locale))
    }
}

/// Plan 08 XG-04 (owner decision G-3): Course Detail's menu holds "This course's grades are kept
/// outside Canvas: Automatic / Yes / No". The answer is the student's (`HomeModel`, kept with the
/// course order); a change re-projects every screen at once and, for a signed-in account, rewrites
/// the widget's glance.
struct GradeOverrideMenu: View {
    let courseID: CanvasID<Course>
    @Environment(HomeModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    /// UX1-19: at AX5 the nested menu (a 4-line title, then "Automatic"/"Yes"/"No") cut its own
    /// options on the smallest iPhone — "Yes" half cut, "No" never shown; a system menu never
    /// scrolls. Below the accessibility sizes the menu is unchanged. UX2-10: a `confirmationDialog`
    /// first replaced it at those sizes, but iOS 26 draws that as the same fixed-width anchored
    /// popover and cut the third choice too, so a plain sheet (`TallyOptionsSheet`) replaces it at
    /// AX1 and up instead.
    @State private var isChoiceDialogPresented = false

    private var choice: Binding<GradeOverrideChoice> {
        Binding(
            get: { GradeOverrideChoice(model.gradeAvailabilityOverride(for: courseID)) },
            set: { model.setGradeAvailabilityOverride($0.override, for: courseID) })
    }

    var body: some View {
        Menu {
            if typeSize.isAccessibilitySize {
                Button(String(localized: L10n.GradeOverride.menuRowTitle())) {
                    isChoiceDialogPresented = true
                }
                .accessibilityIdentifier("courseDetail.gradesOutsideCanvas")
            } else {
                // UX1-22: a `Picker` nested inside this Menu rendered as its own one-item submenu
                // ("Grades kept outside Canvas" › Automatic/Yes/No) -- two taps for the only
                // action this toolbar button holds. Flattened: the three choices are the menu's
                // own content, under a section titled with the same question, so the first tap
                // shows them directly.
                Section(String(localized: L10n.GradeOverride.menuRowTitle())) {
                    ForEach(GradeOverrideChoice.allCases) { option in
                        Button {
                            choice.wrappedValue = option
                        } label: {
                            if option == choice.wrappedValue {
                                // L10N-03a's finding (its report §1.2): a bare
                                // `LocalizedStringResource` is never passed to another SwiftUI
                                // initializer directly (here, `Label(_:systemImage:)`, which has
                                // no such overload) to avoid an unverified-overload compile risk
                                // with no local Xcode to check it.
                                Label { Text(option.title) } icon: { Image(systemName: "checkmark") }
                            } else {
                                Text(option.title)
                            }
                        }
                        // L10N-04: a stable id per choice (the Audit tour looked these up by
                        // their English label — "Automatic" — which Spanish changes).
                        .accessibilityIdentifier("courseDetail.gradesOutsideCanvas.\(option.rawValue)")
                    }
                }
            }
        } label: {
            Label {
                Text(L10n.GradeOverride.menu())
            } icon: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .accessibilityIdentifier("courseDetail.menu")
        // UX2-10 (continuing UX1-19): at AX5 this `confirmationDialog` still cut the third choice
        // ("Tracked in Canvas" sliced on the smallest iPhone, missing on Pro Max) -- iOS 26 draws it
        // as an anchored popover. Below AX1 it is unchanged; at AX1 and up the same three choices
        // present in a plain sheet instead (`TallyOptionsSheet`, D03's AX1+ pattern).
        .confirmationDialog(Text(L10n.GradeOverride.menuRowTitle()), isPresented: Binding(
            get: { isChoiceDialogPresented && !typeSize.isAccessibilitySize },
            set: { shown in if !shown { isChoiceDialogPresented = false } }
        ), titleVisibility: .visible) {
            ForEach(GradeOverrideChoice.allCases) { option in
                Button(String(localized: option.title)) {
                    choice.wrappedValue = option
                }
                .accessibilityIdentifier("courseDetail.gradesOutsideCanvas.\(option.rawValue)")
            }
        }
        .sheet(isPresented: Binding(
            get: { isChoiceDialogPresented && typeSize.isAccessibilitySize },
            set: { shown in if !shown { isChoiceDialogPresented = false } }
        )) {
            TallyOptionsSheet(
                title: String(localized: L10n.GradeOverride.menuRowTitle()),
                options: GradeOverrideChoice.allCases.map { option in
                    TallyOptionsSheet.Option(
                        id: option.rawValue, title: String(localized: option.title),
                        isSelected: option == choice.wrappedValue,
                        accessibilityIdentifier: "courseDetail.gradesOutsideCanvas.\(option.rawValue)") {
                        choice.wrappedValue = option
                    }
                },
                cancelTitle: String(localized: L10n.Settings.cancel()),
                cancelAccessibilityIdentifier: "courseDetail.gradesOutsideCanvas.cancel",
                dismiss: { isChoiceDialogPresented = false })
        }
    }
}

/// The three answers to "This course's grades are kept outside Canvas" (plan 08 G-3), and the
/// override each one stores: Automatic stores none.
nonisolated enum GradeOverrideChoice: String, CaseIterable, Identifiable, Sendable {
    case automatic, yes, no

    var id: Self { self }

    init(_ override: GradeAvailabilityOverride?) {
        switch override {
        case nil: self = .automatic
        case .keptOutsideCanvas?: self = .yes
        case .inCanvas?: self = .no
        }
    }

    var override: GradeAvailabilityOverride? {
        switch self {
        case .automatic: nil
        case .yes: .keptOutsideCanvas
        case .no: .inCanvas
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .automatic: L10n.GradeOverride.automatic()
        // UX1-22 (pending owner approval): reworded from the frozen "Yes"/"No" -- answers to a
        // question nobody now reads aloud in the flattened menu -- as statements instead.
        case .yes: L10n.GradeOverride.keptOutsideCanvas()
        case .no: L10n.GradeOverride.trackedInCanvas()
        }
    }
}

/// Overview · Assignments · Grades, as `ux-ui.md` §3.7.3 specifies: a segmented control at every
/// size. A menu variant tried at the accessibility sizes had its "Show" label flagged by the audit
/// (run 36454544581), so it was dropped; how the segmented control reads at those sizes is
/// unverified (the large-text UI tests were retired).
private struct SegmentPicker: View {
    @Binding var selection: CourseDetailSegment

    var body: some View {
        Picker(String(localized: L10n.CourseDetail.segmentedControlAccessibilityLabel()), selection: $selection) {
            ForEach(CourseDetailSegment.allCases) { segment in
                // L10N-04: a stable, language-independent id per segment (the Audit tour looked
                // these up by their English label — "Grades" — which Spanish changes).
                Text(segment.title).tag(segment)
                    .accessibilityIdentifier("courseDetail.segment.\(segment.rawValue)")
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("courseDetail.segments")
    }
}

/// The course hero (ux-ui.md §3.4: the navy hero card in the content layer, course variant with a
/// course-colour stripe), one VoiceOver element.
struct CourseHeroCard: View {
    let detail: CourseDetailProjection
    /// UX-SPARK: `nil` when the course has no sparkline (fewer than two graded days, or its grade
    /// is not in Canvas as a percentage) — the hero then shows nothing extra.
    var sparkline: CourseSparklinePoints?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .top, spacing: TallySpacing.md) {
            CourseColorMark(paletteIndex: detail.paletteIndex, style: .bar)
            // UX-SPARK-2: two zones — the grade block (unchanged width rules: a Spacer beside it
            // took half, and at AX XXXL "Needs attention" was cut short, run 36454544581's audit)
            // and, when there is one, the trend filling the rest, vertically centred. At
            // accessibility sizes the trend moves below instead (the same reflow rule every other
            // two-part row on this screen uses), so it never competes with the grade block's width.
            TallyReflowStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: TallySpacing.sm) {
                    Text(detail.code)
                        .font(TallyTypography.footnote)
                        .foregroundStyle(TallyColor.textOnHero2)
                    grade
                    if !detail.health.isSaidByTheGrade {
                        Label(detail.health.label, systemImage: detail.health.symbol)
                            // ux-fp2 D11: the hero is a `List` row, whose icon column left a wide gap.
                            .labelStyle(.tallyCompact)
                            .font(TallyTypography.footnote)
                            .foregroundStyle(TallyColor.textOnHero2)
                    }
                }
                if let sparkline {
                    TallyReflowSpacer(minLength: 0)
                    CourseSparklineView(points: sparkline, width: nil, height: CourseSparklineView.heroHeight,
                                        tint: TallyColor.brandGold, background: .hero)
                        .padding(.leading, typeSize.isAccessibilitySize ? 0 : TallySpacing.md)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("courseDetail.sparkline")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(TallySpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        // ux-fp6 D33: the shared hero background + dark-only hairline. See `tallyHeroBackground()`.
        .tallyHeroBackground()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(detail.heroLabel)
        .accessibilityIdentifier("courseDetail.hero")
    }

    /// UX-SPARK-2: the sparkline moved out to its own zone (`body`), so this is the plain grade
    /// row it was before UX-SPARK ever tucked a sparkline beside it.
    @ViewBuilder
    private var grade: some View {
        if let notInCanvas = detail.grade.notInCanvas {
            // Plan 08 §4.4 row 5: the dash and its caption; the card below explains (the hero is
            // one VoiceOver element, whose label says "Grade not in Canvas").
            VStack(alignment: .leading, spacing: TallySpacing.xs) {
                Text(verbatim: GradeNotInCanvas.dash)
                    .font(.system(.largeTitle, design: .serif).bold())
                    .foregroundStyle(TallyColor.textOnHero)
                Text(verbatim: notInCanvas.caption)
                    .font(TallyTypography.footnote)
                    .foregroundStyle(TallyColor.textOnHero2)
            }
        } else if let percent = detail.grade.percentText {
            HStack(alignment: .firstTextBaseline, spacing: TallySpacing.sm) {
                Text(percent)
                    .font(.system(.largeTitle, design: .serif).bold())
                    .foregroundStyle(TallyColor.textOnHero)
                    .monospacedDigit()
                if let letter = detail.grade.letter {
                    Text(letter)
                        .font(TallyTypography.sectionHeader)
                        .foregroundStyle(TallyColor.brandGold)
                }
            }
        } else if let letter = detail.grade.letter {
            Text(letter)
                .font(.system(.largeTitle, design: .serif).bold())
                .foregroundStyle(TallyColor.textOnHero)
        } else {
            VStack(alignment: .leading, spacing: TallySpacing.xs) {
                Text(L10n.Grades.noGradeYet())
                    .font(TallyTypography.sectionHeader)
                    .foregroundStyle(TallyColor.textOnHero)
                if let reason = detail.grade.hiddenReason {
                    Text(reason)
                        .font(TallyTypography.footnote)
                        .foregroundStyle(TallyColor.textOnHero2)
                }
            }
        }
    }
}
