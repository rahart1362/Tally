import SwiftUI
import TallyDesignSystem
import TallyDomain
import TallyStrings

/// UX-WP-17 / ARC E05d: Calendar (ux-ui.md §3.7.4). A week strip with dots for how busy each day
/// is (today ringed), then the agenda: classes with their time range and place, items due, and a
/// conflict line (icon plus words) where two things overlap. The day timeline is offered only below
/// the accessibility text sizes, where its hour grid would clip text.
///
/// PMO R6: "Subscribe to Canvas Calendar…" hands the student's own feed to Calendar (`webcal://`),
/// and "Add to Calendar" on a row opens the system editor. Neither asks for calendar access.
struct CalendarScreen: View {
    nonisolated enum Mode: String, CaseIterable, Identifiable {
        case agenda, timeline
        var id: Self { self }
        var title: LocalizedStringResource { self == .agenda ? L10n.Calendar.modeAgenda() : L10n.Calendar.modeDay() }
    }

    @Environment(HomeModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.openURL) private var openURL
    @State private var mode: Mode = .agenda
    @State private var selectedDay: Date?
    @State private var draft: CalendarEventDraft?
    @State private var showsSampleFeedNote = false

    var body: some View {
        let calendar = model.calendarScreen
        ScrollViewReader { proxy in
            List {
                if showsTimeline, let day = timelineDay(calendar) {
                    Section {
                        DayTimeline(day: day)
                    } header: {
                        Text(day.heading)
                    }
                    // D31 round 2: applied to the Section, which reaches every row inside it.
                    .tallyRow()
                } else {
                    ForEach(calendar.days) { day in
                        Section {
                            if day.items.isEmpty {
                                Text(L10n.Calendar.nothingScheduled())
                                    .font(TallyTypography.subheadline)
                                    .foregroundStyle(TallyColor.textSecondary)
                            }
                            ForEach(day.items) { item in
                                AgendaRow(item: item) { draft = item.draft }
                            }
                        } header: {
                            Text(day.heading)
                        }
                        .tallyRow()
                        .id(day.id)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { await model.refreshUntilSettledOrDelayed() }
            // D27/D31: 16 pt edges and the Tally dark palette, matching the ScrollView tabs.
            .tallyList()
            // D01: content scrolled past the top stayed visible, blurred, under the inline title
            // and the status bar, even at rest.
            .tallyScreenChrome()
            // The week strip stays in place above the agenda (it is how the student moves through
            // the week), under the breadcrumb when one shows.
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    FreshnessBreadcrumb()
                    if !calendar.week.isEmpty {
                        WeekStrip(days: calendar.week, selected: selectedDay ?? calendar.todayID) { day in
                            selectedDay = day
                            withAnimation { proxy.scrollTo(day, anchor: .top) }
                        }
                        .padding(.horizontal, TallySpacing.sm)
                        .padding(.vertical, TallySpacing.xs)
                        .background(TallyColor.bgCanvas)
                    }
                }
            }
            .task(id: calendar.todayID) {
                // Open on today (the agenda starts at the beginning of the week).
                if let today = calendar.todayID, selectedDay == nil { proxy.scrollTo(today, anchor: .top) }
            }
        }
        .navigationTitle(calendar.monthTitle.isEmpty ? Text(L10n.Calendar.tabTitle()) : Text(calendar.monthTitle))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    if calendar.subscribeURL != nil {
                        Button {
                            subscribe(calendar.subscribeURL)
                        } label: {
                            Label(String(localized: L10n.Calendar.subscribeMenuItem()), systemImage: "calendar.badge.plus")
                        }
                    }
                    // ux-ui.md §3.7.4: the timeline only below the accessibility sizes.
                    if Self.offersTimeline(at: typeSize) {
                        Picker(String(localized: L10n.Calendar.viewPickerLabel()), selection: $mode) {
                            ForEach(Mode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                    }
                } label: {
                    Label(String(localized: L10n.Calendar.optionsMenuLabel()), systemImage: "ellipsis.circle")
                }
                .accessibilityIdentifier("calendar.options")
            }
        }
        .sheet(item: $draft) { draft in
            AddToCalendarView(draft: draft) { self.draft = nil }
                .ignoresSafeArea()
        }
        .alert(String(localized: L10n.Calendar.subscribeAlertTitle()), isPresented: $showsSampleFeedNote) {
            Button(String(localized: L10n.Calendar.subscribeAlertOK()), role: .cancel) {}
        } message: {
            Text(L10n.Calendar.subscribeSampleNote())
        }
    }

    private var showsTimeline: Bool {
        mode == .timeline && Self.offersTimeline(at: typeSize)
    }

    /// UX-WP-17: the day timeline's hour grid clips text at the accessibility sizes, so it is
    /// offered only below them (ux-ui.md §3.7.4). A hosted test pins it for every size.
    static func offersTimeline(at size: DynamicTypeSize) -> Bool {
        !size.isAccessibilitySize
    }

    private func timelineDay(_ calendar: CalendarProjection) -> AgendaDay? {
        let id = selectedDay ?? calendar.todayID
        return calendar.days.first { $0.id == id } ?? calendar.days.first
    }

    /// Sample data's feed points at a fictional host, so it is never handed to Calendar (ASC-14).
    private func subscribe(_ url: URL?) {
        guard !model.isSampleData, let url else {
            showsSampleFeedNote = true
            return
        }
        openURL(url)
    }
}

/// The week strip: a day letter, the date and up to three dots; today is ringed in the accent. From
/// the accessibility sizes up, seven columns no longer fit, so the strip scrolls sideways.
private struct WeekStrip: View {
    let days: [AgendaDay]
    let selected: Date?
    let onSelect: (Date) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .headline) private var columnWidth: CGFloat = 44

    var body: some View {
        if typeSize.isAccessibilitySize {
            ScrollView(.horizontal) {
                strip.frame(width: columnWidth * CGFloat(days.count))
            }
        } else {
            strip
        }
    }

    private var strip: some View {
        HStack(spacing: 0) {
            ForEach(days) { day in
                Button {
                    onSelect(day.id)
                } label: {
                    VStack(spacing: TallySpacing.xs) {
                        Text(day.weekdayLetter)
                            .font(TallyTypography.caption)
                            .foregroundStyle(TallyColor.textSecondary)
                        Text(day.dayNumber)
                            .font(TallyTypography.cardTitle)
                            .foregroundStyle(TallyColor.textPrimary)
                            .frame(minWidth: 32, minHeight: 32)
                            .overlay {
                                if day.isToday {
                                    Circle().strokeBorder(TallyColor.accent, lineWidth: 2)
                                }
                            }
                            .background {
                                if day.id == selected {
                                    Circle().fill(TallyColor.accent.opacity(0.15))
                                }
                            }
                        HStack(spacing: 2) {
                            ForEach(0..<3, id: \.self) { index in
                                Circle()
                                    .fill(index < day.dotCount ? TallyColor.textSecondary : Color.clear)
                                    .frame(width: 5, height: 5)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(day.stripLabel)
                .accessibilityAddTraits(day.id == selected ? .isSelected : [])
                .accessibilityIdentifier("calendar.day")
            }
        }
    }
}

/// One agenda row: time, title, course, place, a conflict line, and "Add to Calendar".
private struct AgendaRow: View {
    let item: AgendaItem
    let onAdd: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: TallySpacing.sm) {
            VStack(alignment: .leading, spacing: TallySpacing.xs) {
                HStack(spacing: TallySpacing.xs) {
                    if item.kind == .due {
                        Image(systemName: "checklist")
                            .accessibilityHidden(true)
                    }
                    Text(item.timeText)
                }
                .font(TallyTypography.subheadline)
                .foregroundStyle(TallyColor.textSecondary)
                Text(item.title)
                    .font(TallyTypography.cardTitle)
                    .foregroundStyle(TallyColor.textPrimary)
                if let code = item.courseCode {
                    HStack(spacing: TallySpacing.xs) {
                        if let palette = item.paletteIndex {
                            CourseColorMark(paletteIndex: palette)
                        }
                        Text(code)
                        if let location = item.location {
                            Text("· \(location)")
                        }
                    }
                    .font(TallyTypography.footnote)
                    .foregroundStyle(TallyColor.textSecondary)
                } else if let location = item.location {
                    Text(location)
                        .font(TallyTypography.footnote)
                        .foregroundStyle(TallyColor.textSecondary)
                }
                if item.isExam {
                    StatusChip(symbol: "graduationcap", text: L10n.Calendar.examChip(), tone: .warning)
                }
                if let conflict = item.conflictText {
                    Label(conflict, systemImage: "exclamationmark.triangle")
                        .font(TallyTypography.footnote)
                        .foregroundStyle(TallyColor.textPrimary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(item.accessibilityLabel)
            .accessibilityIdentifier("calendar.item")
            Spacer(minLength: TallySpacing.sm)
            Button(action: onAdd) {
                Image(systemName: "calendar.badge.plus")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(String(localized: L10n.Calendar.addToCalendar(item.title)))
            .accessibilityIdentifier("calendar.add")
        }
    }
}

/// The day timeline (the mockup's hour grid): blocks placed by start time, from the day's first
/// hour (8 AM, or earlier) to midnight. Offered only below the accessibility sizes.
private struct DayTimeline: View {
    let day: AgendaDay
    @ScaledMetric(relativeTo: .caption) private var hourHeight: CGFloat = 48

    var body: some View {
        let firstHour = day.timelineStartHour
        let hours = Array(firstHour..<24)
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(hours, id: \.self) { hour in
                    HStack(alignment: .top, spacing: TallySpacing.sm) {
                        Text(Self.hourLabel(hour))
                            .font(TallyTypography.caption)
                            .foregroundStyle(TallyColor.textSecondary)
                            .frame(width: 44, alignment: .trailing)
                        Rectangle().fill(TallyColor.separator).frame(height: 0.5)
                    }
                    .frame(height: hourHeight, alignment: .top)
                }
            }
            ForEach(day.timedItems) { item in
                let top = CGFloat(item.startMinute - firstHour * 60) / 60 * hourHeight
                let height = max(CGFloat(item.durationMinutes) / 60 * hourHeight, 24)
                Text(item.title)
                    .font(TallyTypography.caption)
                    .foregroundStyle(TallyColor.textPrimary)
                    .lineLimit(1)
                    .padding(.horizontal, TallySpacing.xs)
                    .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
                    .background(TallyColor.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
                    .padding(.leading, 52)
                    .offset(y: max(0, top))
                    .accessibilityLabel(item.accessibilityLabel)
            }
        }
        .frame(height: CGFloat(hours.count) * hourHeight)
    }

    /// "8 AM"-style hour labels. Formatting a whole hour needs no clock: `hour` is data, placed on a
    /// fixed day in a fixed zone and formatted in that zone.
    private static func hourLabel(_ hour: Int) -> String {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = .gmt
        guard let date = gregorian.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: hour)) else {
            return "\(hour):00"
        }
        return date.formatted(Date.FormatStyle(timeZone: .gmt).hour())
    }
}
