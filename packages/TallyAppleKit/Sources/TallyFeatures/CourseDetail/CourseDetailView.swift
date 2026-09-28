import SwiftUI
import TallyDesignSystem
import TallyDomain

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
                Picker("Show", selection: $segment) {
                    ForEach(CourseDetailSegment.allCases) { segment in
                        Text(segment.title).tag(segment)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("courseDetail.segments")
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
        if let next = detail.nextDueText {
            Section("Next due") {
                Text(next).font(TallyTypography.body)
            }
        }
        if !detail.recentGraded.isEmpty {
            Section("Recent grades") {
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
                    Label("Try What-If Scores", systemImage: "flask")
                }
                .accessibilityIdentifier("courseDetail.whatIf")
            } else {
                Text(Self.whatIfUnavailable(detail))
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
                        Text(category.weightText)
                            .font(TallyTypography.footnote)
                            .foregroundStyle(TallyColor.textSecondary)
                    }
                    Spacer(minLength: TallySpacing.sm)
                    Text(categoryPercent(category, in: detail))
                        .font(TallyTypography.subheadline)
                        .foregroundStyle(TallyColor.textPrimary)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text("Categories")
        } footer: {
            Text(detail.showsCategoryPercentages
                 ? "Current grade counts graded work only."
                 : (detail.grade.hiddenReason ?? "This course shows letter grades only."))
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

    private static func whatIfUnavailable(_ detail: CourseDetailProjection) -> String {
        if let reason = detail.grade.hiddenReason, !detail.showsCategoryPercentages {
            return "What-if isn't available: \(reason.lowercased())"
        }
        if !detail.showsCategoryPercentages {
            return "What-if isn't available for a course that shows letter grades only."
        }
        return "Everything in this course has a score, so there is nothing to try."
    }
}

/// The course hero (ux-ui.md §3.4: the navy hero card in the content layer, course variant with a
/// course-colour stripe), one VoiceOver element.
struct CourseHeroCard: View {
    let detail: CourseDetailProjection

    var body: some View {
        HStack(alignment: .top, spacing: TallySpacing.md) {
            CourseColorMark(paletteIndex: detail.paletteIndex, style: .bar)
            VStack(alignment: .leading, spacing: TallySpacing.sm) {
                Text(detail.code)
                    .font(TallyTypography.footnote)
                    .foregroundStyle(TallyColor.textOnHero2)
                grade
                if detail.health != .noGradeYet {
                    Label(detail.health.label, systemImage: detail.health.symbol)
                        .font(TallyTypography.footnote)
                        .foregroundStyle(TallyColor.textOnHero2)
                }
            }
            Spacer(minLength: 0)
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
        if let percent = detail.grade.percentText {
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
                Text("No grade yet")
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
