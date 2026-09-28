import SwiftUI
import TallyDesignSystem
import TallyDomain

/// UX-WP-18 / ARC E05c: To-Do (ux-ui.md §3.7.5). Missing and overdue work first, then this week,
/// then later; each section's rows arrive sorted three ways from the projector, so the Sort menu
/// only picks one. "Done" is Tally's own mark (PMO R16: Tally never writes to Canvas), and the row
/// says so honestly: "Marked done in Tally", plus "Not submitted in Canvas" while Canvas still
/// expects a submission.
struct ToDoScreen: View {
    @Environment(HomeModel.self) private var model
    @State private var sortOrder: ToDoSortOrder = .dueDate
    @State private var editMode: EditMode = .inactive
    @State private var selection = Set<CanvasID<Assignment>>()

    var body: some View {
        Group {
            if model.toDoScreen.sections.isEmpty {
                emptyState
            } else {
                List(selection: $selection) {
                    ForEach(model.toDoScreen.sections) { section in
                        Section {
                            ForEach(section.items(sortedBy: sortOrder)) { item in
                                row(item)
                            }
                        } header: {
                            Text(section.title)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .environment(\.editMode, $editMode)
                .refreshable { await model.refreshUntilSettledOrDelayed() }
                // Select mode's bottom bar (Mark Done) takes the tab bar's place, as in Photos; with
                // both shown, the tab bar covered Mark Done (run 36454544581).
                .toolbarVisibility(editMode.isEditing ? .hidden : .automatic, for: .tabBar)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { FreshnessBreadcrumb() }
        .navigationTitle("To-Do")
        .toolbar {
            if !model.toDoScreen.sections.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Sort by", selection: $sortOrder) {
                            ForEach(ToDoSortOrder.allCases) { order in
                                Text(order.label).tag(order)
                            }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                    .accessibilityIdentifier("todo.sort")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(editMode.isEditing ? "Cancel" : "Select") {
                        selection.removeAll()
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    }
                    .accessibilityIdentifier("todo.select")
                }
            }
            if editMode.isEditing {
                ToolbarItem(placement: .bottomBar) {
                    Button("Mark Done") {
                        model.local.setDone(selection, done: true)
                        selection.removeAll()
                        withAnimation { editMode = .inactive }
                    }
                    .disabled(selection.isEmpty)
                    .accessibilityIdentifier("todo.markDone")
                }
            }
        }
    }

    private func row(_ item: ToDoItem) -> some View {
        let isDone = model.local.isDone(item.id)
        return ToDoRowView(item: item, isDone: isDone) {
            model.local.setDone([item.id], done: !isDone)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                model.local.setDone([item.id], done: !isDone)
            } label: {
                Label(isDone ? "Not Done" : "Done", systemImage: isDone ? "arrow.uturn.backward" : "checkmark")
            }
            .tint(TallyColor.accent)
            // Sample data has no real Canvas to open (ASC-14).
            if !model.isSampleData, let url = item.canvasURL {
                Button {
                    // A one-shot open: the Canvas Student app, else the browser (R20).
                    Task { await CanvasLinkOpener.open(url) }
                } label: {
                    Label("Open in Canvas", systemImage: "safari")
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        switch model.phase {
        case .loading:
            ProgressView("Loading your work…")
        case .loaded, .failed:
            // ux-ui.md §3.2.3 "Nothing due".
            ContentUnavailableView("You're all caught up", systemImage: "checkmark.circle",
                                   description: Text("Nothing is missing, and nothing is due."))
        }
    }
}

/// One To-Do row (ux-ui.md §3.6 AssignmentRow): the completion control (44 × 44 pt, A11Y-04), then
/// the title, the course dot and code, the due date, the Canvas status chip and a "High priority"
/// flag in words.
struct ToDoRowView: View {
    let item: ToDoItem
    let isDone: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: TallySpacing.sm) {
            Button(action: onToggle) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(.title2))
                    .foregroundStyle(isDone ? TallyColor.accent : TallyColor.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isDone ? "Marked done. Mark \(item.title) not done" : "Mark \(item.title) done")
            .accessibilityIdentifier("todo.complete")

            VStack(alignment: .leading, spacing: TallySpacing.xs) {
                Text(item.title)
                    .font(TallyTypography.cardTitle)
                    .foregroundStyle(TallyColor.textPrimary)
                HStack(spacing: TallySpacing.xs) {
                    CourseColorMark(paletteIndex: item.paletteIndex)
                    Text(item.courseCode)
                    if let due = item.dueText {
                        Text("· \(due)")
                    }
                }
                .font(TallyTypography.subheadline)
                .foregroundStyle(TallyColor.textSecondary)
                if item.status != nil || item.priorityWord != nil {
                    HStack(spacing: TallySpacing.xs) {
                        if let status = item.status {
                            StatusChip(symbol: status.symbol, text: status.label, tone: status.tone)
                        }
                        if let priority = item.priorityWord {
                            StatusChip(symbol: "flag", text: priority, tone: .warning)
                        }
                    }
                }
                if let late = item.lateNote {
                    Text(late)
                        .font(TallyTypography.footnote)
                        .foregroundStyle(TallyColor.textSecondary)
                }
                if isDone {
                    Label(ToDoItem.markedDoneText, systemImage: "checkmark")
                        .font(TallyTypography.footnote)
                        .foregroundStyle(TallyColor.textPrimary)
                    if item.needsCanvasSubmission {
                        Label(ToDoItem.notSubmittedText, systemImage: "exclamationmark.circle")
                            .font(TallyTypography.footnote)
                            .foregroundStyle(TallyColor.textPrimary)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(item.spokenLabel(isDone: isDone))
            .accessibilityIdentifier("todo.row")
        }
    }
}
