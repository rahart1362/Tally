import SwiftUI
import TallyDesignSystem
import TallyDomain
import TallyStrings

/// Course Detail's segments (ux-ui.md §3.7.3): no "People" tab; instructor contact is in Overview.
nonisolated enum CourseDetailSegment: String, CaseIterable, Identifiable {
    case overview, assignments, grades

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .assignments: "Assignments"
        case .grades: "Grades"
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
    @Environment(HomeModel.self) private var model
    @State private var segment: CourseDetailSegment = .overview
    @State private var grades = CourseGradesModel()
    /// Built by the What-If button's action, never in a view initialiser (perf-app-runtime.md §3 item 6).
    @State private var whatIf: WhatIfModel?

    var body: some View {
        Group {
            if let detail = model.courseDetails[courseID] {
                content(detail)
            } else {
                ContentUnavailableView("Course unavailable", systemImage: "books.vertical",
                                       description: Text("This course isn't in your latest Canvas data."))
            }
        }
        .navigationTitle(model.courseDetails[courseID]?.name ?? "Course")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ detail: CourseDetailProjection) -> some View {
        List {
            Section {
                CourseHeroCard(detail: detail)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            Section {
                SegmentPicker(selection: $segment)
            }
            switch segment {
            case .overview: overview(detail)
            case .assignments: assignments(detail)
            case .grades: gradeTable(detail)
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await model.refreshUntilSettledOrDelayed() }
        .task(id: detail.gradeInput) { await grades.load(detail.gradeInput) }
        .sheet(isPresented: Binding(get: { whatIf != nil }, set: { if !$0 { whatIf = nil } })) {
            if let whatIf {
                WhatIfSheet(model: whatIf)
            }
        }
        .toolbar {
            // Sample data has no real Canvas to open (ASC-14).
            if !model.isSampleData, let url = detail.canvasURL {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        // A one-shot open: the Canvas Student app, else the browser (R20).
                        Task { await CanvasLinkOpener.open(url) }
                    } label: {
                        Label("Open in Canvas", systemImage: "safari")
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
        }
        if let next = detail.nextDueText {
            Section("Next due") {
                Text(next).font(TallyTypography.body)
            }
        }
        if !detail.recentGraded.isEmpty || detail.recentGradesNote != nil {
            Section("Recent grades") {
                if let note = detail.recentGradesNote {
                    Text(verbatim: note)
                        .font(TallyTypography.body)
                        .foregroundStyle(TallyColor.textSecondary)
                }
                ForEach(detail.recentGraded) { item in
                    HStack(alignment: .firstTextBaseline, spacing: TallySpacing.md) {
                        VStack(alignment: .leading, spacing: TallySpacing.xs) {
                            Text(item.title).font(TallyTypography.body)
                            if let posted = item.postedText {
                                Text(posted)
                                    .font(TallyTypography.footnote)
                                    .foregroundStyle(TallyColor.textSecondary)
                            }
                        }
                        Spacer(minLength: TallySpacing.sm)
                        StatusChip(symbol: "checkmark.seal", text: item.scoreText)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(item.accessibilityLabel)
                }
            }
        }
        if !detail.weights.isEmpty {
            Section {
                CategoryWeightsChart(weights: detail.weights, title: "Category weights", summary: detail.weightsSummary)
                    .padding(.vertical, TallySpacing.sm)
            } header: {
                Text("Category weights")
            } footer: {
                Text(detail.weightsAreInstructorSet
                     ? "Set by your instructor."
                     : "This course adds up points, so each category's share is its share of the points.")
            }
        }
        // ux-ui.md §3.5: only when Canvas returns score statistics, never invented.
        if let distribution = detail.distribution {
            Section("Grade distribution") {
                Text("Class range \(Self.percent(distribution.minimum))–\(Self.percent(distribution.maximum)), "
                     + "average \(Self.percent(distribution.mean)). You: \(Self.percent(distribution.yours)).")
                    .accessibilityIdentifier("chart.distribution")
            }
        }
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
                Text(verbatim: reason.text)
                    .font(TallyTypography.footnote)
                    .foregroundStyle(TallyColor.textSecondary)
            }
        } header: {
            Text("What-If")
        } footer: {
            if detail.whatIf != nil {
                Text("See how scores on work that isn't graded yet would change your grade. Nothing is sent to Canvas.")
            }
        }
        if !detail.instructors.isEmpty {
            Section {
                ForEach(detail.instructors.indices, id: \.self) { index in
                    Label(detail.instructors[index], systemImage: "person")
                }
            } header: {
                Text(detail.instructors.count == 1 ? "Instructor" : "Instructors")
            }
        }
    }

    private var whatIfLabel: some View {
        Label {
            Text(L10n.CourseDetail.whatIfButton())
        } icon: {
            Image(systemName: "flask")
        }
    }

    // MARK: - Assignments

    @ViewBuilder
    private func assignments(_ detail: CourseDetailProjection) -> some View {
        if detail.sections.isEmpty {
            Section {
                Text("No assignments in Canvas yet.")
                    .foregroundStyle(TallyColor.textSecondary)
            }
        }
        ForEach(detail.sections) { section in
            Section(section.title) {
                ForEach(section.rows) { row in
                    HStack(alignment: .top, spacing: TallySpacing.md) {
                        VStack(alignment: .leading, spacing: TallySpacing.xs) {
                            Text(row.title).font(TallyTypography.body)
                            if let due = row.dueText {
                                Text(due)
                                    .font(TallyTypography.footnote)
                                    .foregroundStyle(TallyColor.textSecondary)
                            }
                        }
                        Spacer(minLength: TallySpacing.sm)
                        VStack(alignment: .trailing, spacing: TallySpacing.xs) {
                            if let status = row.status {
                                StatusChip(symbol: status.symbol, text: status.label, tone: status.tone)
                            }
                            if let score = row.scoreText {
                                Text(score)
                                    .font(TallyTypography.subheadline)
                                    .foregroundStyle(TallyColor.textPrimary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(row.accessibilityLabel)
                }
            }
        }
    }

    // MARK: - Grades

    @ViewBuilder
    private func gradeTable(_ detail: CourseDetailProjection) -> some View {
        Section {
            ForEach(detail.categories) { category in
                HStack(alignment: .firstTextBaseline, spacing: TallySpacing.md) {
                    VStack(alignment: .leading, spacing: TallySpacing.xs) {
                        Text(category.name).font(TallyTypography.body)
                        if let weightText = category.weightText {
                            Text(weightText)
                                .font(TallyTypography.footnote)
                                .foregroundStyle(TallyColor.textSecondary)
                        }
                    }
                    Spacer(minLength: TallySpacing.sm)
                    // Plan 08 §4.4 row 5: names only for a course whose grades are not in Canvas.
                    if detail.grade.notInCanvas == nil {
                        Text(categoryPercent(category, in: detail))
                            .font(TallyTypography.subheadline)
                            .foregroundStyle(TallyColor.textPrimary)
                            .monospacedDigit()
                    }
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text("Categories")
        } footer: {
            switch detail.grade.notInCanvas {
            case .keptOutside?:
                Text(L10n.CourseDetail.notInCanvasLine())
            case .notGraded?:
                Text(L10n.Grades.notGradedDetail())
            case nil:
                Text(detail.showsCategoryPercentages
                     ? "Current grade counts graded work only."
                     : (detail.grade.hiddenReason ?? "This course shows letter grades only."))
            }
        }
    }

    private func categoryPercent(_ category: CategoryRow, in detail: CourseDetailProjection) -> String {
        guard detail.showsCategoryPercentages else { return "Hidden" }
        guard let percent = grades.categoryPercents[category.id] else { return "No grades yet" }
        return Self.percent(percent)
    }

    private static func percent(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + "%"
    }
}

/// Overview · Assignments · Grades, as `ux-ui.md` §3.7.3 specifies: a segmented control at every
/// size. A menu variant tried at the accessibility sizes had its "Show" label flagged by the audit
/// (run 36454544581), so it was dropped; how the segmented control reads at those sizes is
/// unverified (the large-text UI tests were retired).
private struct SegmentPicker: View {
    @Binding var selection: CourseDetailSegment

    var body: some View {
        Picker("Show", selection: $selection) {
            ForEach(CourseDetailSegment.allCases) { segment in
                Text(segment.title).tag(segment)
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

    var body: some View {
        HStack(alignment: .top, spacing: TallySpacing.md) {
            CourseColorMark(paletteIndex: detail.paletteIndex, style: .bar)
            // The text column takes all the width there is (a Spacer beside it took half, and at
            // AX XXXL "Needs attention" was cut short: run 36454544581's audit).
            VStack(alignment: .leading, spacing: TallySpacing.sm) {
                Text(detail.code)
                    .font(TallyTypography.footnote)
                    .foregroundStyle(TallyColor.textOnHero2)
                grade
                if !detail.health.isSaidByTheGrade {
                    Label(detail.health.label, systemImage: detail.health.symbol)
                        .font(TallyTypography.footnote)
                        .foregroundStyle(TallyColor.textOnHero2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(TallySpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TallyColor.bgBrand, in: RoundedRectangle(cornerRadius: TallyRadius.hero, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(detail.heroLabel)
        .accessibilityIdentifier("courseDetail.hero")
    }

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
