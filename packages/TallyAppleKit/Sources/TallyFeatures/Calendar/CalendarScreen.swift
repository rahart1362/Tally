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
    /// MVP-2b gate-2 round 3 (verdict item 1, PMO note). The strip's own measured height (never a
    /// fixed number: it scales with Dynamic Type and changes shape from AX1 up, D18), fed to
    /// `.contentMargins(.top:)` below so `scrollTo` reserves exactly as much room as the strip
    /// actually draws.
    @State private var pinnedStripHeight: CGFloat = 0

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
                        Section {
                            // MVP-2b gate-2 round 3 (verdict item 1, the PMO's documented
                            // fallback). The first attempt put `.id(day.id)` on the `header:`
                            // closure's own `Text` instead of the `Section`, reasoning that
                            // `scrollTo` landing on "the Section's first row" meant the anchor
                            // needed to sit on the header view itself. CI proved that wrong
                            // (run 38608671835: `heading.minY` of 87 against a target of 233, on
                            // open — the scroll barely moved at all): a `List` `Section`'s
                            // `header:`/`footer:` content does not publish the anchor preference
                            // `ScrollViewProxy.scrollTo` reads; only its own rows do. The heading
                            // is now the Section's own first row instead, carrying the id
                            // `scrollTo` needs, and styled to read as the header did: this app's
                            // own "meta text" role (`.footnote`, the same size role the freshness
                            // breadcrumb and agenda times use) and `tallySectionText()`'s colour,
                            // no cell background (`.tallyRow()` below sets the card colour for
                            // every *other* row in this Section; a row's own `.listRowBackground`
                            // overrides that), and the `.isHeader` trait a true header gets
                            // automatically.
                            Text(day.heading)
                                .font(TallyTypography.footnote)
                                .tallySectionText()
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityIdentifier("calendar.dayHeading")
                                .listRowBackground(Color.clear)
                                .id(day.id)
                            if day.items.isEmpty {
                                Text(L10n.Calendar.nothingScheduled())
                                    .font(TallyTypography.subheadline)
                                    .foregroundStyle(TallyColor.textSecondary)
                                    // MVP-2b gate-2 round 3: lets a UI test find the row under a
                                    // heading even on a day with nothing scheduled (item 1's own
                                    // assertion needs the heading's first row, whichever it is).
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
            .refreshable { await model.refreshUntilSettledOrDelayed() }
            // D27/D31: 16 pt edges and the Tally dark palette, matching the ScrollView tabs.
            .tallyList()
            // D01: content scrolled past the top stayed visible, blurred, under the inline title
            // and the status bar, even at rest. R4 (round 3): Calendar is a large-title tab root
            // too (no inline display mode); it usually opens scrolled to today, its title already
            // collapsed into the bar, but on a day whose row is first it opens at the scroll edge,
            // where a `.visible` fill would paint over the large title as on the other four roots.
            .tallyLargeTitleScreenChrome()
            // MVP-2b gate-2 round 3 (verdict item 1, PMO note). `.safeAreaInset(edge: .top)`
            // (round 1 onward) places the strip correctly, but `List`'s `ScrollViewProxy.scrollTo`
            // does not read that inset when computing an anchor's target offset — a documented
            // `List`/`ScrollViewReader` gap, confirmed empirically (CI runs 38608671835,
            // 38623450627: the heading landed near the navigation bar's own height, short of the
            // strip's extra reservation, however the anchor or the timing was adjusted).
            // `.contentMargins(.top:, for: .scrollContent)` IS read by `scrollTo` (it is the same
            // mechanism `tallyList()` already uses for the horizontal margins), so the strip's own
            // measured height now drives that margin instead. The strip itself moves to an
            // `.overlay` so the two mechanisms never double-reserve the same space — only
            // `contentMargins` reserves scroll room; the overlay only draws, inside the safe area
            // (unchanged: no `.ignoresSafeArea()`), so it still starts right below the navigation
            // bar exactly where the inset view used to.
            .contentMargins(.top, pinnedStripHeight, for: .scrollContent)
            .overlay(alignment: .top) {
                // The week strip stays in place above the agenda (it is how the student moves
                // through the week), under the breadcrumb when one shows.
                VStack(spacing: 0) {
                    FreshnessBreadcrumb()
                    if !calendar.week.isEmpty {
                        WeekStrip(days: calendar.week, selected: selectedDay ?? calendar.todayID) { day in
                            selectedDay = day
                            scrollBelowPinnedStrip(day, with: proxy, animated: true)
                        }
                        .padding(.horizontal, TallySpacing.sm)
                        .padding(.vertical, TallySpacing.xs)
                        .background(TallyColor.bgCanvas)
                    }
                }
                // MVP-2b: a container (its children stay their own elements) with an identifier, so
                // the accessibility audit knows where this opaque pinned bar is: agenda rows above
                // today pass under it by design (`A11yScene.pinnedBars`, AccessibilityAuditUITests).
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("calendar.pinnedHeader")
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                    pinnedStripHeight = height
                }
            }
            .task(id: calendar.todayID) {
                // Open on today (the agenda starts at the beginning of the week).
                if let today = calendar.todayID, selectedDay == nil {
                    scrollBelowPinnedStrip(today, with: proxy, animated: false)
                }
            }
            // MVP-2b gate-2 round 3 (verdict item 1, PMO note). CI showed a real, but
            // incomplete, improvement from `contentMargins(.top:)` alone (heading.minY 98 pt ->
            // 170 pt against a target of 233 pt, run 38644410449) — consistent with
            // `scrollBelowPinnedStrip`'s fixed-delay re-corrections (50 ms, 200 ms) firing before
            // `pinnedStripHeight` finished settling to its true value, so `scrollTo` kept using a
            // too-small margin. Re-scrolling exactly when the measured height actually changes,
            // rather than guessing how long that takes, keeps the correction in sync with
            // whatever `contentMargins` currently reserves, however many renders that took.
            .onChange(of: pinnedStripHeight) { _, _ in
                if let target = selectedDay ?? calendar.todayID {
                    scrollBelowPinnedStrip(target, with: proxy, animated: false)
                }
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

    /// MVP-2b gate-2 round 3 (verdict item 1; round 2's own fix did not hold — section 3; round
    /// 3's first attempt did not either — CI run 38608671835/38623450627). Two separate bugs, now
    /// both fixed:
    /// 1. **The wrong scroll anchor.** Round 2's `.id(day.id)` sat on the `Section`, which made
    ///    `scrollTo` land on the Section's first *row*, not its heading. Round 3's own first
    ///    attempt moved the id onto the `header:` closure's `Text`, which CI proved does not
    ///    register as a `scrollTo` anchor at all (the scroll barely moved). The id now sits on
    ///    the heading's own ROW (`CalendarScreen.body`: the heading is the Section's first row,
    ///    no `header:` closure), which `scrollTo` does resolve correctly.
    /// 2. **Layout not yet settled.** Even with the right anchor, a single `scrollTo` right when
    ///    this `.task`/`onSelect` fires measures against the `List`'s own row heights before they
    ///    have all been laid out for a freshly rendered agenda, landing short (CI run
    ///    38623450627: heading.minY 98 against a target of 233 pt, on open). A second,
    ///    re-corrective call, one or more run-loop turns later, measures the now-settled layout
    ///    and corrects it — this is the same shape round 2's single delayed call took, but that
    ///    one could never have helped: it targeted the SAME wrong anchor as the first call. With
    ///    the anchor now correct, the delayed calls can actually re-measure and land.
    ///
    /// `CalendarUITests.testSelectedDayHeadingClearsThePinnedStripOnOpenAndAfterTapping` asserts
    /// `heading.frame.minY >= pinnedHeader.frame.maxY` on open, after the first day and after a
    /// mid-week day, at std and AX5.
    private func scrollBelowPinnedStrip(_ day: Date, with proxy: ScrollViewProxy, animated: Bool) {
        func scroll() {
            if animated {
                withAnimation { proxy.scrollTo(day, anchor: .top) }
            } else {
                proxy.scrollTo(day, anchor: .top)
            }
        }
        scroll()
        for delay in [0.05, 0.2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { scroll() }
        }
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
