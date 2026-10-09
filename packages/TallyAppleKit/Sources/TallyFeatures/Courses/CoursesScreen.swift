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
                // title and the status bar, even at rest. R4 (round 3): the large-title variant,
                // so the opaque fill never paints over "Courses" and its subtitle at rest.
                .tallyLargeTitleScreenChrome()
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
            TallyUnavailableView(Text(L10n.Courses.emptyTitle()), systemImage: "books.vertical",
                                 description: Text(L10n.Courses.emptyDescription())) {
                Button(String(localized: L10n.Courses.emptyRefresh())) { model.requestRefresh() }
            }
            // ux-fp2 D20: centred when it fits, scrolling when it does not (AX5), with the
            // list's own D01 chrome, since it can now scroll under the bar.
            .tallyCenteredScrolling()
            .tallyLargeTitleScreenChrome()
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
                sparklineColumn
                if !typeSize.isAccessibilitySize, sparkline == nil {
                    Spacer(minLength: TallySpacing.sm)
                }
                grade
            }
        }
        .padding(.vertical, TallySpacing.xs)
    }

    /// UX-SPARK-2: a dedicated, centred trend column between the title and grade blocks, about
    /// 96×32 pt; at accessibility sizes it moves below the title block, full width, so the grade
    /// (laid out after it) is never squeezed (D14). `nil` when the course has no sparkline (fewer
    /// than two graded days, or its grade not in Canvas as a percentage): no placeholder, and the
    /// layout adds no extra spacing for it.
    @ViewBuilder
    private var sparklineColumn: some View {
        if let sparkline {
            if typeSize.isAccessibilitySize {
                CourseSparklineView(points: sparkline, width: nil, height: CourseSparklineView.courseCardSize.height,
                                    tint: TallyColor.accent, background: .card)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("course.sparkline")
            } else {
                Spacer(minLength: TallySpacing.sm)
                CourseSparklineView(points: sparkline, width: CourseSparklineView.courseCardSize.width,
                                    height: CourseSparklineView.courseCardSize.height, tint: TallyColor.accent,
                                    background: .card)
                    .accessibilityIdentifier("course.sparkline")
                Spacer(minLength: TallySpacing.sm)
            }
        }
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

    /// UX-SPARK-2: the sparkline is its own dedicated column (`sparklineColumn`), never tucked
    /// beside the letter or percentage, so this is the plain grade row every course had before
    /// UX-SPARK.
    @ViewBuilder
    private var gradeInCanvas: some View {
        VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: TallySpacing.xs) {
            if let letter = card.letter {
                Text(letter)
                    .font(.system(.title2).bold())
                    .foregroundStyle(TallyColor.textPrimary)
            }
            if let percent = card.percentText {
                Text(percent)
                    .font(TallyTypography.subheadline)
                    .foregroundStyle(TallyColor.textSecondary)
                    .monospacedDigit()
            }
            if card.letter == nil && card.percentText == nil {
                Text(card.gradeText)
                    .font(TallyTypography.subheadline)
                    .foregroundStyle(TallyColor.textSecondary)
            }
        }
    }
}
