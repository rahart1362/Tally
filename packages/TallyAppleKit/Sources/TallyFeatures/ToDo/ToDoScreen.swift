import SwiftUI
import TallyDesignSystem
import TallyDomain
import TallyStrings

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
                                .tallySectionText()
                        }
                        // D31 round 2: applied to the Section, which reaches every row inside it.
                        .tallyRow()
                    }
                }
                .listStyle(.insetGrouped)
                .environment(\.editMode, $editMode)
                .refreshable { await model.refreshUntilSettledOrDelayed() }
                // Select mode's bottom bar (Mark Done) takes the tab bar's place, as in Photos; with
                // both shown, the tab bar covered Mark Done (run 36454544581).
                .toolbarVisibility(editMode.isEditing ? .hidden : .automatic, for: .tabBar)
                // D27/D31: 16 pt edges and the Tally dark palette, matching the ScrollView tabs.
                .tallyList()
                // D01: content scrolled past the top stayed visible, blurred, under the inline
                // title and the status bar, even at rest — select mode included. R4 (round 3): the
                // large-title variant, so the opaque fill never paints over "To-Do" at rest.
                .tallyLargeTitleScreenChrome()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { FreshnessBreadcrumb() }
        .navigationTitle(String(localized: L10n.ToDo.navigationTitle()))
        .toolbar {
            if !model.toDoScreen.sections.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker(String(localized: L10n.ToDo.sortByLabel()), selection: $sortOrder) {
                            ForEach(ToDoSortOrder.allCases) { order in
                                Text(order.label).tag(order)
                            }
                        }
                    } label: {
                        Label(String(localized: L10n.ToDo.sortMenuLabel()), systemImage: "arrow.up.arrow.down")
                    }
                    .accessibilityIdentifier("todo.sort")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(editMode.isEditing ? String(localized: L10n.ToDo.selectModeCancel()) : String(localized: L10n.ToDo.selectModeSelect())) {
                        selection.removeAll()
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    }
                    .accessibilityIdentifier("todo.select")
                }
            }
            if editMode.isEditing {
                ToolbarItem(placement: .bottomBar) {
                    Button(String(localized: L10n.ToDo.markDoneButton())) {
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
                Label(isDone ? String(localized: L10n.ToDo.swipeNotDone()) : String(localized: L10n.ToDo.swipeDone()),
                      systemImage: isDone ? "arrow.uturn.backward" : "checkmark")
            }
            // ux-fp6 D28: a swipe action always draws a white glyph/label, which a label colour
            // change can't reach; `accent` flips to a light blue in dark (2.08–2.15:1). `accentFill`
            // stays dark enough in both appearances.
            .tint(TallyColor.accentFill)
            // Sample data has no real Canvas to open (ASC-14).
            if !model.isSampleData, let url = item.canvasURL {
                Button {
                    // A one-shot open: the Canvas Student app, else the browser (R20).
                    Task { await CanvasLinkOpener.open(url) }
                } label: {
                    // L10N-03a's finding (its report §1.2): a bare LocalizedStringResource is never
                    // passed to another SwiftUI initializer directly, to avoid an unverified-overload
                    // compile risk with no local Xcode to check it.
                    Label { Text(L10n.CourseDetail.openInCanvas()) } icon: { Image(systemName: "safari") }
                }
                // ux-fp6 D28: this swipe button had no explicit tint, so it inherited the shell's
                // `accent` tint (`HomeShellView`'s TabView) — the same 2.08–2.15:1 white-on-light-
                // blue failure in dark.
                .tint(TallyColor.accentFill)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        switch model.phase {
        case .loading, .glance:
            // The launch's glance carries no rows for this tab (M2-C1 D7): loading until the projection.
            ProgressView(String(localized: L10n.ToDo.loading()))
        case .loaded, .failed:
            // ux-ui.md §3.2.3 "Nothing due".
            TallyUnavailableView(Text(L10n.ToDo.emptyTitle()), systemImage: "checkmark.circle",
                                 description: Text(L10n.ToDo.emptyDescription()))
                // ux-fp2 D20: centred when it fits, scrolling when it does not (AX5), with the
                // list's own D01 chrome, since it can now scroll under the bar.
                .tallyCenteredScrolling()
                .tallyLargeTitleScreenChrome()
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
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.editMode) private var editMode

    var body: some View {
        HStack(alignment: .top, spacing: TallySpacing.sm) {
            // Audit D16: in select mode the system selection circle and this done circle looked
            // alike, and together they squeezed the text column until "Missing" broke mid-word at
            // AX5 (ux-fp2 gate 2). Select mode shows only the selection circle.
            if editMode?.wrappedValue.isEditing != true {
                Button(action: onToggle) {
                    Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(.title2))
                        .foregroundStyle(isDone ? TallyColor.accent : TallyColor.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isDone ? String(localized: L10n.ToDo.markedDoneAccessibility(item.title))
                                    : String(localized: L10n.ToDo.markDoneAccessibility(item.title)))
                .accessibilityIdentifier("todo.complete")
            }

            VStack(alignment: .leading, spacing: TallySpacing.xs) {
                Text(item.title)
                    .font(TallyTypography.cardTitle)
                    .foregroundStyle(TallyColor.textPrimary)
                // ux-fp2 D02: the course code never breaks ("MAT / H 122" at AX5); from AX1 up the
                // due date goes under it, where it needs no "·" separator.
                TallyReflowStack(spacing: TallySpacing.xs) {
                    HStack(spacing: TallySpacing.xs) {
                        CourseColorMark(paletteIndex: item.paletteIndex)
                        Text(item.courseCode)
                    }
                    .tallyReflowValue()
                    if let due = item.dueText {
                        if typeSize.isAccessibilitySize {
                            Text(verbatim: due)
                        } else {
                            Text("· \(due)")
                        }
                    }
                }
                .font(TallyTypography.subheadline)
                .foregroundStyle(TallyColor.textSecondary)
                if item.status != nil || item.priorityWord != nil {
                    // ux-fp2 D11: side by side while both fit, otherwise one under the other.
                    StatusChipRow {
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
                    // ux-fp2 D11: icon and words together, not across the list's icon column.
                    Label(ToDoItem.markedDoneText, systemImage: "checkmark")
                        .labelStyle(.tallyCompact)
                        .font(TallyTypography.footnote)
                        .foregroundStyle(TallyColor.textPrimary)
                    if item.needsCanvasSubmission {
                        Label(ToDoItem.notSubmittedText, systemImage: "exclamationmark.circle")
                            .labelStyle(.tallyCompact)
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
