import SwiftUI
import TallyDesignSystem
import TallyDomain
import TallyStrings

/// UX-WP-14 / ARC E05a: the Courses tab (ux-ui.md §3.7.2). A plain list of `HomeModel.courseCards`,
/// already built, ordered and formatted off the main actor; the body only lays them out.
///
/// - **Edit** reorders the list; `HomeModel.moveCourses` keeps the order locally, so every later
///   projection shows it. There is no "+": courses come from Canvas.
/// - A card opens Course Detail with a standard push (a plain page, never a navigation container,
///   perf-app-runtime.md §3).
struct CoursesScreen: View {
    @Environment(HomeModel.self) private var model
    @State private var editMode: EditMode = .inactive
    /// Plan 08 §4.5: the card whose ⓘ bubble is open (its button, or the card's VoiceOver action).
    @State private var infoCourse: CanvasID<Course>?
    /// UX-SPARK: each course's trend sparkline, computed once per snapshot off the main actor and
    /// shared with Course Detail (passed through `navigationDestination` below), so neither
    /// screen recomputes it.
    @State private var sparklines = CourseSparklineModel()

    var body: some View {
        Group {
            if model.courseCards.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(model.courseCards) { card in
                        // One VoiceOver element per card (ux-ui.md §3.7.2): the link's own label.
                        NavigationLink(value: card.id) {
                            CourseCardView(card: card, sparkline: sparklines.series[card.id],
                                          isInfoPresented: infoBinding(for: card.id))
                        }
                        .accessibilityLabel(card.accessibilityLabel)
                        .accessibilityIdentifier("course.card")
                        // The card is one element, so its ⓘ button is reached as the card's action.
                        .accessibilityActions {
                            if let label = card.infoButtonLabel {
                                Button {
                                    infoCourse = card.id
                                } label: {
                                    Text(verbatim: label)
                                }
                            }
                        }
                    }
                    .onMove { source, destination in
                        model.moveCourses(fromOffsets: source, toOffset: destination)
                    }
                    // D31 round 2: `.listRowBackground` on the `List` itself never reached the
                    // rows; `tallyRow()` on the `ForEach` reaches every row it generates. Must come
                    // AFTER `.onMove`: that modifier needs `ForEach`'s own `DynamicViewContent`
                    // conformance, which a `View`-returning modifier like this one does not keep.
                    .tallyRow()
                }
                .listStyle(.insetGrouped)
                .environment(\.editMode, $editMode)
                .refreshable { await model.refreshUntilSettledOrDelayed() }
                // D27/D31: 16 pt edges and the Tally dark palette, matching the ScrollView tabs.
                .tallyList()
                // D01: content scrolled past the top stayed visible, blurred, under the inline
                // title and the status bar, even at rest.
                .tallyScreenChrome()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { FreshnessBreadcrumb() }
        .navigationTitle(String(localized: L10n.Courses.navigationTitle()))
        .navigationDestination(for: CanvasID<Course>.self) { id in
            CourseDetailView(courseID: id, sparklines: sparklines)
        }
        .task(id: model.insightsScreen.trendInput) { await sparklines.load(model.insightsScreen.trendInput) }
        .toolbar {
            if !model.courseCards.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    Button(editMode.isEditing ? String(localized: L10n.Courses.editDoneButton()) : String(localized: L10n.Courses.editButton())) {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    }
                    .accessibilityIdentifier("courses.edit")
                }
            }
        }
    }

    private func infoBinding(for id: CanvasID<Course>) -> Binding<Bool> {
        Binding(get: { infoCourse == id }, set: { infoCourse = $0 ? id : nil })
    }

    @ViewBuilder
    private var emptyState: some View {
        switch model.phase {
        case .loading, .glance:
            // The launch's glance carries no rows for this tab (M2-C1 D7): loading until the projection.
            ProgressView(String(localized: L10n.Courses.loading()))
        case .loaded, .failed:
            // ux-ui.md §3.2.3 "No courses".
            ContentUnavailableView {
                Label(String(localized: L10n.Courses.emptyTitle()), systemImage: "books.vertical")
            } description: {
                Text(L10n.Courses.emptyDescription())
            } actions: {
                Button(String(localized: L10n.Courses.emptyRefresh())) { model.requestRefresh() }
            }
        }
    }
}

/// One course card (ux-ui.md §3.7.2): colour bar, name, code, grade, next due and the health chip.
/// From the accessibility sizes up, the grade moves under the name instead of beside it. A course
/// whose grades are not in Canvas shows "—" and its caption instead (plan 08 §4.4 row 3).
struct CourseCardView: View {
    let card: CourseCard
    /// UX-SPARK: `nil` when the course has no sparkline (fewer than two graded days, or its grade
    /// is not in Canvas as a percentage) — the card then shows nothing extra, never a placeholder.
    var sparkline: CourseSparklinePoints?
    var isInfoPresented: Binding<Bool> = .constant(false)
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .top, spacing: TallySpacing.md) {
            CourseColorMark(paletteIndex: card.paletteIndex, style: .bar)
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: TallySpacing.sm))
                : AnyLayout(HStackLayout(alignment: .top, spacing: TallySpacing.md))
            layout {
                VStack(alignment: .leading, spacing: TallySpacing.xs) {
                    Text(card.name)
                        .font(TallyTypography.cardTitle)
                        .foregroundStyle(TallyColor.textPrimary)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    Text(card.code)
                        .font(TallyTypography.subheadline)
                        .foregroundStyle(TallyColor.textSecondary)
                    if let next = card.nextDueText {
                        Text(next)
                            .font(TallyTypography.footnote)
                            .foregroundStyle(TallyColor.textSecondary)
                    }
                    // "No grade yet" and "Grade not in Canvas" are already said where the grade goes.
                    if !card.health.isSaidByTheGrade {
                        StatusChip(symbol: card.health.symbol, text: card.health.label, tone: card.health.tone)
                    }
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: TallySpacing.sm) }
                grade
            }
        }
        .padding(.vertical, TallySpacing.xs)
    }

    @ViewBuilder
    private var grade: some View {
        if let notInCanvas = card.notInCanvas {
            GradeNotInCanvasValue(notInCanvas: notInCanvas, infoButtonLabel: card.infoButtonLabel,
                                  isInfoPresented: isInfoPresented,
                                  alignment: typeSize.isAccessibilitySize ? .leading : .trailing)
        } else {
            gradeInCanvas
        }
    }

    @ViewBuilder
    private var gradeInCanvas: some View {
        // UX-SPARK: the sparkline sits beside whichever grade line shows first (the letter, else
        // the percentage); at AX sizes it wraps below instead of squeezing that text (never
        // truncating the grade). Only the branch that actually draws a sparkline uses the extra
        // layout, so a course with none keeps its plain row (no stray spacing for an empty slot).
        let gradeRowLayout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: TallySpacing.xs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: TallySpacing.xs))
        VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: TallySpacing.xs) {
            if let letter = card.letter {
                if let sparkline {
                    gradeRowLayout {
                        Text(letter)
                            .font(.system(.title2).bold())
                            .foregroundStyle(TallyColor.textPrimary)
                        CourseSparklineView(points: sparkline)
                            .accessibilityIdentifier("course.sparkline")
                    }
                } else {
                    Text(letter)
                        .font(.system(.title2).bold())
                        .foregroundStyle(TallyColor.textPrimary)
                }
            }
            if let percent = card.percentText {
                if card.letter == nil, let sparkline {
                    gradeRowLayout {
                        Text(percent)
                            .font(TallyTypography.subheadline)
                            .foregroundStyle(TallyColor.textSecondary)
                            .monospacedDigit()
                        CourseSparklineView(points: sparkline)
                            .accessibilityIdentifier("course.sparkline")
                    }
                } else {
                    Text(percent)
                        .font(TallyTypography.subheadline)
                        .foregroundStyle(TallyColor.textSecondary)
                        .monospacedDigit()
                }
            }
            if card.letter == nil && card.percentText == nil {
                Text(card.gradeText)
                    .font(TallyTypography.subheadline)
                    .foregroundStyle(TallyColor.textSecondary)
            }
        }
    }
}
