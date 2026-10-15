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
                            .tallySectionText()
                    }
                    // D31 round 2: applied to the Section, which reaches every row inside it.
                    .tallyRow()
                } else {
                    ForEach(calendar.days) { day in
                        // MVP-2c: the day's heading is a section of its own, one clear row that is the
                        // day's scroll target, and its items are the next section, a native card.
                        // A `List` header is never a `scrollTo` anchor (run 38608671835: with the id
                        // on the header, the list scrolled to the first row and left the header
                        // under the strip). Round 3 made the heading the card's own first row, which
                        // scrolled correctly but squared the card's top corners and shrank the
                        // heading to footnote size (run 38660677136's screenshot). As its own section
                        // the card keeps the system's corners and separators, and `DayHeading` keeps
                        // the system header's measured style.
                        Section {
                            DayHeading(text: day.heading)
                                .id(day.id)
                        }
                        Section {
                            if day.items.isEmpty {
                                Text(L10n.Calendar.nothingScheduled())
                                    .font(TallyTypography.subheadline)
                                    .foregroundStyle(TallyColor.textSecondary)
                                    // MVP-2b round 3: the UI test finds the first row under a heading
                                    // even on a day with nothing scheduled.
                                    .accessibilityIdentifier("calendar.nothingScheduled")
                            }
                            ForEach(day.items) { item in
                                AgendaRow(item: item) { draft = item.draft }
                            }
                        }
                        .tallyRow()
                    }
                }
            }
            .listStyle(.insetGrouped)
            // MVP-2c: the gap above each heading is `DayHeading`'s own top inset (the system's
            // section spacing plus its header padding), so a heading sits on its card as a header
            // did, and rests that same gap below the strip once scrolled to.
            .listSectionSpacing(.custom(0))
            .refreshable { await model.refreshUntilSettledOrDelayed() }
            // D27/D31: 16 pt edges and the Tally dark palette, matching the ScrollView tabs.
            .tallyList()
            // D01: content scrolled past the top stayed visible, blurred, under the inline title
            // and the status bar, even at rest.
            //
            // MVP-2e (gate-2 final review S2, fix list item 2): R4 (round 3) made Calendar a
            // large-title tab root (`tallyLargeTitleScreenChrome`, fill `.automatic`) on the theory
            // that it usually opens scrolled to today, title already collapsed, and only a day
            // whose row is first opens at the true scroll edge, where a `.visible` fill would paint
            // over the large title as it did on the other four roots. That theory was wrong for
            // this screen specifically: every large-title capture since MVP-2c (scope=a11y and
            // scope=only, Light/Dark/Increase Contrast, 22 of them) shows "October" and "Updated
            // just now" in the hierarchy but drawn nowhere (max pixel difference from the canvas 15
            // in Light, 0 in Dark) — the pre-existing l10n-04 defect (main-era, today a Sunday) is
            // the same blank band, now reached on every first-day tap instead of only by chance.
            // The week strip's `.safeAreaBar(edge: .top)`, below, is the one thing that
            // distinguishes Calendar from the other four large-title roots: pinning content
            // directly under the bar is apparently enough for `.automatic` to resolve as though the
            // list had scrolled, even at the List's own true top, so the fill goes opaque and
            // collapses the title together, leaving nothing drawn in the expanded title's place.
            // Diagnosing the exact SwiftUI interaction further needs a simulator this host does not
            // have, so this takes the PMO's own sanctioned fallback instead: an inline title, like
            // Course Detail's (`CourseDetailView.swift`) and What-If's (`WhatIfSheet.swift`), both
            // of which already render correctly on `tallyScreenChrome()`'s always-opaque fill — the
            // same state this screen's own OWN inline (collapsed) title already rendered correctly
            // in, every time it was reached by scrolling rather than by opening at the top. D01 is
            // unaffected (content is still never visible under the bar at rest; the fill is simply
            // always on instead of conditional). Recorded for the owner: a native large title for
            // Calendar remains open, should the safe-area-bar interaction ever get a real fix.
            .tallyScreenChrome()
            // MVP-2c: the week strip is a safe-area bar (iOS 26), so the list's safe area, its scroll
            // edge effect and `scrollTo(_:anchor: .top)` all start below it. Round 3's diagnosis
            // ("scrollTo ignores the inset") was the test's: run 38623450627's hierarchy has today's
            // heading at y = 237.3 under a strip ending at 233.3, with `.safeAreaInset`; the test
            // measured the previous day's heading, still in the hierarchy under the bars. Round 3's
            // `.contentMargins` replacement is padding inside the content, which `scrollTo` does
            // not count (run 38652917902: the heading at the navigation bar's bottom, y = 170).
            .safeAreaBar(edge: .top, spacing: 0) {
                // The week strip stays in place above the agenda (it is how the student moves
                // through the week), under the breadcrumb when one shows.
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
                // MVP-2b: a container (its children stay their own elements) with an identifier, so
                // the accessibility audit knows where this opaque pinned bar is: agenda rows above
                // the selected day pass under it by design (`A11yScene.pinnedBars`).
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("calendar.pinnedHeader")
            }
            .task(id: calendar.todayID) {
                // Open on today (the agenda starts at the beginning of the week).
                if let today = calendar.todayID, selectedDay == nil { proxy.scrollTo(today, anchor: .top) }
            }
        }
        .navigationTitle(calendar.monthTitle.isEmpty ? Text(L10n.Calendar.tabTitle()) : Text(calendar.monthTitle))
        // MVP-2e (S2, fix list item 2): paired with `tallyScreenChrome()` above, like Course
        // Detail's and What-If's own inline titles.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    if calendar.subscribeURL != nil {
                        Button {
                            subscribe(calendar.subscribeURL)
                        } label: {
                            Label(String(localized: L10n.Calendar.subscribeMenuItem()), systemImage: "calendar.badge.plus")
                        }
                        // L10N-04: a stable id (the Audit tour looked this menu row up by its
                        // English label, which Spanish changes).
                        .accessibilityIdentifier("calendar.subscribeMenuItem")
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

/// MVP-2c: a day's heading in the agenda, drawn as a row (the day's scroll target) that looks like
/// the inset-grouped section header it replaces: the system header's measured font
/// (`TallyTypography.listHeader`), colour (`tallySectionText()`, `#475467` measured) and position
/// (`Metrics`), on no card, with no separator. It keeps the header's `.isHeader` trait.
private struct DayHeading: View {
    /// The system header "Mon, Oct 12" in scope=a11y run 38550012702 (light-std, before round 3's
    /// change): the previous card ends at y = 476.3, the capitals' tops are at 508.0 and the
    /// header's own card starts at 534.3, so 31.7 pt from the card above to the capitals and 26.3
    /// pt from the capitals to the card below. With the section spacing at zero these insets put the
    /// heading's capitals at those distances (scope=only run 38672964445 measured 31.0 and 27.0 with
    /// 27.5 and 10, hence 28.2 and 9.3; the 58 pt between the cards is unchanged).
    enum Metrics {
        static let top: CGFloat = 28.2
        static let bottom: CGFloat = 9.3
        static let horizontal: CGFloat = 16
    }

    let text: String

    var body: some View {
        Text(text)
            .font(TallyTypography.listHeader)
            .tallySectionText()
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("calendar.dayHeading")
            .listRowInsets(EdgeInsets(top: Metrics.top, leading: Metrics.horizontal,
                                      bottom: Metrics.bottom, trailing: Metrics.horizontal))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

/// The week strip: a day letter, the date and up to three dots; today is ringed in the accent. From
/// the accessibility sizes up, seven columns no longer fit, so the strip scrolls sideways.
///
/// ux-fp2 D18 (S2): at AX5 the scrolling strip opened at Sunday, with today (the selected day) cut
/// at the right edge of the largest iPhone and off the smallest one, and nothing to say it scrolls.
/// It now opens with the selected day centred, keeps a newly selected day centred, and flashes its
/// scroll indicator on appear; the days cut at both edges show there is more either way.
private struct WeekStrip: View {
    let days: [AgendaDay]
    let selected: Date?
    let onSelect: (Date) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .headline) private var columnWidth: CGFloat = 44
    /// The day number's ring and selection disc: 32 pt at the default size, scaled with the number
    /// itself. ux-fp2 D18 follow-up: a fixed 32 pt minimum left a digit-wide ring cutting through
    /// the AX5 number (64 pt tall), seen once today was centred and on screen (Audit tour run
    /// 37842950859, every AX5 leg).
    @ScaledMetric(relativeTo: .headline) private var dayMarkDiameter: CGFloat = 32

    /// MVP-2b: one view tree at every text size. The strip used to be a plain row below the
    /// accessibility sizes and a different, scrolling tree from AX1 up, so its texts were new views
    /// once the size crossed AX1. Xcode's audit predicts clipping by growing the text and finding
    /// each text again; one it cannot find seems to come back as "may be clipped" with no element
    /// (the sign-in hand-off had one such finding while its address tag switched layouts at AX1,
    /// run 38357314250, and none once the tag kept one layout, run 38363059477). Now the strip is always
    /// in the scroll view: the screen's own width, not scrolling, below the accessibility sizes (as
    /// before); a fixed column width, scrolling and centred on the selected day, from AX1 up (D18).
    var body: some View {
        let scrolls = typeSize.isAccessibilitySize
        let scrollingWidth = columnWidth * CGFloat(days.count)
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                strip
                    .containerRelativeFrame(.horizontal) { length, _ in scrolls ? scrollingWidth : length }
            }
            .scrollDisabled(!scrolls)
            .scrollIndicators(scrolls ? .automatic : .hidden)
            .scrollIndicatorsFlash(onAppear: scrolls)
            .onAppear { if scrolls { centre(selected, with: proxy, animated: false) } }
            .onChange(of: selected) { _, day in if scrolls { centre(day, with: proxy, animated: true) } }
        }
    }

    /// Scrolls the strip so `day`'s column sits in the middle of it.
    private func centre(_ day: Date?, with proxy: ScrollViewProxy, animated: Bool) {
        guard let day else { return }
        if animated, !reduceMotion {
            withAnimation(.snappy) { proxy.scrollTo(WeekStripColumn(day: day), anchor: .center) }
        } else {
            proxy.scrollTo(WeekStripColumn(day: day), anchor: .center)
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
                            // MVP-2b: names the letter for its measured contrast waiver
                            // (`docs/pmo/a11y-waivers.md`).
                            .accessibilityIdentifier("calendar.weekStrip.weekday")
                        Text(day.dayNumber)
                            .font(TallyTypography.cardTitle)
                            .foregroundStyle(TallyColor.textPrimary)
                            .frame(minWidth: dayMarkDiameter, minHeight: dayMarkDiameter)
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
                // D18: the strip's own scroll target, a type of its own so it can never be
                // mistaken for the agenda's day sections (which use the bare date).
                .id(WeekStripColumn(day: day.id))
            }
        }
    }
}

/// D18: a week strip column's scroll identity.
private struct WeekStripColumn: Hashable {
    let day: Date
}

/// One agenda row: time, title, course, place, a conflict line, and "Add to Calendar".
private struct AgendaRow: View {
    let item: AgendaItem
    let onAdd: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

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
                    // ux-fp2 D02: the course code never breaks; from AX1 up the place goes under
                    // it, where it needs no "·" separator (the To-Do row's rule).
                    TallyReflowStack(spacing: TallySpacing.xs) {
                        HStack(spacing: TallySpacing.xs) {
                            if let palette = item.paletteIndex {
                                CourseColorMark(paletteIndex: palette)
                            }
                            Text(code)
                        }
                        .tallyReflowValue()
                        if let location = item.location {
                            // MVP-2b: one text whose words change at AX1, not two texts (the week
                            // strip's note: the audit loses a text that is replaced as it grows).
                            Text(verbatim: typeSize.isAccessibilitySize ? location : "· " + location)
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
                        // ux-fp2 D11: icon and words together, not across the list's icon column.
                        .labelStyle(.tallyCompact)
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
