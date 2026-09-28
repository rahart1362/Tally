import SwiftUI
import TallyDesignSystem
import TallyDomain

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

    var body: some View {
        Group {
            if model.courseCards.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(model.courseCards) { card in
                        // One VoiceOver element per card (ux-ui.md §3.7.2): the link's own label.
                        NavigationLink(value: card.id) {
                            CourseCardView(card: card)
                        }
                        .accessibilityLabel(card.name)
                        .accessibilityIdentifier("course.card")
                    }
                    .onMove { source, destination in
                        model.moveCourses(fromOffsets: source, toOffset: destination)
                    }
                }
                .listStyle(.insetGrouped)
                .environment(\.editMode, $editMode)
                .refreshable { await model.refreshUntilSettledOrDelayed() }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { FreshnessBreadcrumb() }
        .navigationTitle("Courses")
        .navigationDestination(for: CanvasID<Course>.self) { id in
            CourseDetailView(courseID: id)
        }
        .toolbar {
            if !model.courseCards.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    Button(editMode.isEditing ? "Done" : "Edit") {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    }
                    .accessibilityIdentifier("courses.edit")
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        switch model.phase {
        case .loading:
            ProgressView("Loading your courses…")
        case .loaded, .failed:
            // ux-ui.md §3.2.3 "No courses".
            ContentUnavailableView {
                Label("No courses yet", systemImage: "books.vertical")
            } description: {
                Text("When your school adds you to courses in Canvas, they'll appear here.")
            } actions: {
                Button("Refresh") { model.requestRefresh() }
            }
        }
    }
}

/// One course card (ux-ui.md §3.7.2): colour bar, name, code, grade, next due and the health chip.
/// From the accessibility sizes up, the grade moves under the name instead of beside it.
struct CourseCardView: View {
    let card: CourseCard
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
                    // "No grade yet" is already said where the grade goes.
                    if card.health != .noGradeYet {
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
