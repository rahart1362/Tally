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
    /// Idea 4 (FEAT-3): "Remind me" asks for one reminders pass right after scheduling, the same
    /// way Settings' "Hide Course Names" does.
    @Environment(AppModel.self) private var app: AppModel?
    @State private var sortOrder: ToDoSortOrder = .dueDate
    @State private var editMode: EditMode = .inactive
    @State private var selection = Set<CanvasID<Assignment>>()
    /// UX1-11: the tab root's own content margin, read from the container width so Pro Max's
    /// large title and this list's rows share one left edge (20 pt on a wide phone, else the
    /// static 16 pt) instead of the title alone picking up the system's wider margin.
    @State private var screenMargin: CGFloat = TallySpacing.screenMargin

    var body: some View {
        Group {
            if model.toDoScreen.sections.isEmpty {
                emptyState
            } else {
                // MVP-2h: the selection binding is `nil` outside edit mode, not merely emptied.
                // MVP-2g's `List(selection: $selection)` left its leading multi-select accessory
                // permanently reserved on every row once `editMode` had been `.active` at least
                // once — a disabled `circle` image stayed in the element tree even once `editMode`
                // read `.inactive` again. MVP-2g's own Pro Max AX5 legs did release the accessory
                // on a normal exit, so the accessory is tied to the List holding a live selection
                // binding, not to the List's identity; binding only while editing removes it the
                // same way, without rebuilding the List (and so without resetting its scroll
                // position — the narrow re-check's finding against `.id(listGeneration)`).
                List(selection: editMode.isEditing ? $selection : nil) {
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
                // UX1-11: the edge itself now follows the container width (see `screenMargin`).
                .tallyList(margin: screenMargin)
                .tallyReadsScreenMargin(into: $screenMargin)
                // D01: content scrolled past the top stayed visible, blurred, under the inline
                // title and the status bar, even at rest — select mode included. R4 (round 3): the
                // large-title variant, so the opaque fill never paints over "To-Do" at rest.
                .tallyLargeTitleScreenChrome()
            }
        }
        // UX1-11: the breadcrumb is the one other screen-margin-sensitive element outside the
        // list itself; it needs the same dynamic edge the list's rows now get.
        .safeAreaInset(edge: .top, spacing: 0) { FreshnessBreadcrumb(margin: screenMargin) }
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
                        model.setDone(selection, done: true)
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
            model.setDone([item.id], done: !isDone)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                model.setDone([item.id], done: !isDone)
            } label: {
                Label(isDone ? String(localized: L10n.ToDo.swipeNotDone()) : String(localized: L10n.ToDo.swipeDone()),
                      systemImage: isDone ? "arrow.uturn.backward" : "checkmark")
            }
            // ux-fp6 D28: a swipe action always draws a white glyph/label, which a label colour
            // change can't reach; `accent` flips to a light blue in dark (2.08–2.15:1). `accentFill`
            // stays dark enough in both appearances.
            .tint(TallyColor.accentFill)
            // L10N-04: a stable id (the Audit tour looked this up by its English label — "Done" —
            // which Spanish changes to "Hecho"/"No hecho").
            .accessibilityIdentifier(isDone ? "todo.swipe.notDone" : "todo.swipe.done")
            // Sample data has no real Canvas to open (ASC-14).
            if !model.isSampleData, let url = item.canvasURL {
                Button {
                    // A one-shot open: the Canvas Student app, else the browser (R20).
                    Task { await CanvasLinkOpener.open(url, accountHost: model.account.host) }
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
            // Idea 4 (FEAT-3): one ad-hoc reminder through the existing pipeline — never a grade
            // value, respects "Hide Course Names" (same content rules as every other reminder).
            // Sample data schedules nothing (ASC-14), and an undated item has no due date for the
            // pipeline to say anything honest about (`ReminderSubjects` only carries dated items).
            if !model.isSampleData, item.dueText != nil {
                Button {
                    remindMe(for: item)
                } label: {
                    Label(String(localized: L10n.ToDo.swipeRemindMe()), systemImage: "bell")
                }
                .tint(TallyColor.accentFill)
                .accessibilityIdentifier("todo.swipe.remindMe")
            }
        }
    }

    /// Idea 4 (FEAT-3): schedules one ad-hoc reminder one hour from now (`SnoozeOption.oneHour`,
    /// already built and tested for this exact purpose, `ReminderPlanner.snoozeDate`), persisted
    /// so every later reminders pass keeps planning it until the item is done, submitted or
    /// graded. `Date()`/`.current` stay out of `body` itself (`check_view_bodies.py`); this is a
    /// plain method, called only from a tap.
    private func remindMe(for item: ToDoItem) {
        guard let fireDate = ReminderPlanner.snoozeDate(.oneHour, now: Date(), dueAt: nil, timeZone: .current) else { return }
        model.scheduleReminder(for: item.id, fireDate: fireDate)
        app?.reminders.reconcileNow()
        AccessibilityAnnouncer.announce(String(localized: L10n.ToDo.remindMeConfirmation()))
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
                        // UX1-27: at AX5 `title2` grows to about 55 pt, but the frame was fixed at
                        // 44 x 44 pt, so the glyph overflowed it by about 5 pt a side and ate the
                        // gap before the title. `minWidth`/`minHeight` keep the 44 pt tap target
                        // as a floor while letting the frame grow with the glyph above it.
                        .frame(minWidth: 44, minHeight: 44)
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
                // due date goes under it, where it needs no "·" separator. UX1-28: `xxxLarge`
                // (`stacksAtXXXLarge`) joins that stacked layout too, so the due date wraps as its
                // own full-width line instead of a hanging column beside the code (the
                // `CourseCardView.usesFullWidthColumn` precedent).
                TallyReflowStack(spacing: TallySpacing.xs, stacksAtXXXLarge: true) {
                    HStack(spacing: TallySpacing.xs) {
                        CourseColorMark(paletteIndex: item.paletteIndex)
                        Text(item.courseCode)
                    }
                    .tallyReflowValue()
                    if let due = item.dueText {
                        if TallyReflow.isStacked(at: typeSize, stacksAtXXXLarge: true) {
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
            // L10N-04 round 2 (gate-2 verdict item 16 / round-1 report §8 item 3): was a flat
            // "todo.row" for every row, so the Audit tour's batch-select filter matched on this
            // row's spoken label containing the English "Marked done in Tally" instead — which
            // Spanish translates, so under es the filter silently stopped filtering rather than
            // failing loudly. `.accessibilityValue` was considered and rejected: VoiceOver speaks
            // a value alongside the label, so a literal English word there would read aloud in
            // every language, a real regression for a screen-reader user. The identifier itself
            // (never spoken; test-only) carries the state instead. Every row still matches a
            // `identifier BEGINSWITH "todo.row"` query exactly as "todo.row" alone did
            // (`ScreenUITestSupport.elementsWithPrefix`), so `ToDoUITests.swift`'s existing exact
            // match is updated to that prefix form, not removed.
            .accessibilityIdentifier(isDone ? "todo.row.done" : "todo.row.notDone")
        }
    }
}
