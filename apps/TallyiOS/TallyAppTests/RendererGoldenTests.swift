import Foundation
import Testing
import TallyDomain
import TallyStrings
import TallyTestSupport
@testable import TallyFeatures

/// Plan 08 L10N-02 (§3.2, §5): TallyCore returns values and `TallyStrings` phrases them. These
/// pin the renderers' English to the text Tally showed before (628ee09), byte for byte, and
/// sample a few other locales:
/// - literal goldens for every sentence (en_US, America/Chicago), from the 628ee09 capture in the
///   L10N-02 report;
/// - differential sweeps against `LegacyEnglish` (628ee09's code, frozen) over real persona
///   data: every planned reminder with names shown and hidden, every dashboard row, a reason grid
///   with non-finite inputs, and the change chip for 0 to 30 changes;
/// - every new catalog key compiled into the TallyStrings bundle with its English value;
/// - en_GB and German regional settings with the English UI (`TallyLocale.effective`).
///
/// The two named fixes are against TallyCore's own former text, not the app's: the time was a
/// fixed 24-hour `HH:mm` and the date an ISO `yyyy-MM-dd` there, which `HomeProjector` re-rendered
/// in the user's locale before the student saw them. So the app's English is unchanged.
@Suite("L10N-02: renderer goldens (en_US equal to 628ee09) and a locale sample")
struct RendererGoldenTests {
    private static let enUS = Locale(identifier: "en_US")
    private static let chicago = TimeZone(identifier: "America/Chicago") ?? .gmt
    /// Monday 2026-09-21 09:13:20 in Chicago (14:13:20Z), the flagship anchor.
    private static let seen = Date(timeIntervalSince1970: 1_790_000_000)
    private static func at(_ epoch: TimeInterval) -> Date { Date(timeIntervalSince1970: epoch) }
    private static func calendar(_ zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    /// ICU puts U+202F before "AM"/"PM" and U+00A0 before "%" in some locales, and which one
    /// changes between ICU releases: literal goldens compare them as plain spaces. The
    /// differential sweeps compare exact bytes.
    private static func plain(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { $0 == "\u{00A0}" || $0 == "\u{202F}" ? " " : $0 }))
    }

    private static func render(_ message: NotificationMessage, locale: Locale = enUS) -> [String] {
        let rendered = NotificationText.render(message, seenAt: seen, timeZone: chicago,
                                               weekdayNamingDays: RemindersConfig.weekdayNamingDays, locale: locale)
        return [plain(rendered.title), plain(rendered.body)]
    }

    // MARK: - Literal goldens: notifications

    private static let lab = NotificationMessage.Subject.assignment(title: "Lab Report 4", courseCode: "BIO 101")

    /// Each row: a message, then 628ee09's title and body for it (the "NC" lines of the capture,
    /// with the day and time text `ReminderTimeFormat` gave for these instants).
    @Test("Notifications: every sentence, en_US, equals 628ee09's text")
    func notificationGoldens() {
        let rows: [(NotificationMessage, String, String)] = [
            (.due(Self.lab, dueAt: Self.at(1_790_031_600), isFinalReminder: false),
             "Lab Report 4 · BIO 101", "Due today at 6:00 PM."),
            (.due(Self.lab, dueAt: Self.at(1_790_031_600), isFinalReminder: true),
             "Lab Report 4 · BIO 101", "Due today at 6:00 PM, if you haven't submitted yet."),
            (.due(.hidden, dueAt: Self.at(1_790_031_600), isFinalReminder: false), "An assignment", "Due today at 6:00 PM."),
            (.due(.hidden, dueAt: Self.at(1_790_031_600), isFinalReminder: true),
             "An assignment", "Due today at 6:00 PM, if you haven't submitted yet."),
            (.due(Self.lab, dueAt: Self.at(1_789_488_000), isFinalReminder: false), "Lab Report 4 · BIO 101", "Due Tue at 11:00 AM."),
            (.missingFollowup(.assignment(title: "Problem Set 6", courseCode: "MATH 122"), stillAcceptedUntil: Self.at(1_790_398_740)),
             "Problem Set 6 · MATH 122", "Still accepted until Fri at 11:59 PM."),
            (.missingFollowup(.hidden, stillAcceptedUntil: Self.at(1_790_398_740)), "An assignment", "Still accepted until Fri at 11:59 PM."),
            (.missingFollowup(.assignment(title: "Problem Set 6", courseCode: "MATH 122"), stillAcceptedUntil: nil),
             "Problem Set 6 · MATH 122", "Past due. Canvas lists no closing date."),
            (.examReminder(.assignment(title: "Midterm 1", courseCode: "CHEM 110"), dueAt: Self.at(1_790_085_600)),
             "Midterm 1 · CHEM 110", "Due tomorrow at 9:00 AM."),
            (.examReminder(.hidden, dueAt: Self.at(1_790_085_600)), "An assignment", "Due tomorrow at 9:00 AM."),
            (.examReminder(.assignment(title: "Final Exam", courseCode: "CHEM 110"), dueAt: Self.at(1_790_861_400)),
             "Final Exam · CHEM 110", "Due Oct 1 at 8:30 AM."),
            (.gradePosted(.code("BIO 101")), "New grade posted", "BIO 101"),
            (.gradePosted(.hidden), "New grade posted", "a course"),
            (.belowGoal(.code("BIO 101")), "BIO 101 needs attention", "Open Tally to see your standing."),
            (.belowGoal(.hidden), "a course needs attention", "Open Tally to see your standing."),
            (.eveningDigest(dueCount: 1, firstItem: .title("Lab Report 4")), "Tomorrow", "1 due · Lab Report 4 first"),
            (.eveningDigest(dueCount: 2, firstItem: .title("Lab Report 4")), "Tomorrow", "2 due · Lab Report 4 first"),
            (.eveningDigest(dueCount: 2, firstItem: .hidden), "Tomorrow", "2 due · An assignment first"),
            (.eveningDigest(dueCount: 3, firstItem: nil), "Tomorrow", "3 due"),
            (.weekAhead(dueCount: 7, busiestDay: Self.at(1_790_226_000)), "This week", "7 due · busiest Thursday"),
            (.weekAhead(dueCount: 1, busiestDay: nil), "This week", "1 due"),
            (.sentinel(lastSuccess: Self.at(1_789_931_640)),
             "Tally hasn't refreshed since yesterday at 2:14 PM", "Open Tally to update your reminders."),
            // Canvas text is an argument, never a format: "%@" and "%" in a title pass through.
            (.due(.assignment(title: "Essay %@ 100%", courseCode: "ENG %d"), dueAt: Self.at(1_790_031_600), isFinalReminder: false),
             "Essay %@ 100% · ENG %d", "Due today at 6:00 PM."),
        ]
        for (message, title, body) in rows {
            #expect(Self.render(message) == [title, body], "\(message)")
        }
    }

    // MARK: - Literal goldens: the Dashboard

    @Test("Dashboard: reasons, Needs attention rows and the change chip, en_US, equal 628ee09's text")
    func dashboardGoldens() {
        let reasons: [([PriorityScore.Factor], String, String)] = [
            ([.dueIn(hours: 581.4), .nearBoundary, .courseWeight(0.11)], "BIO 101", "Due in 581h · near a grade boundary · ~11% of BIO 101"),
            ([.overdue, .nearBoundary, .stillAccepted], "MATH 122", "Overdue · near a grade boundary · Still accepted"),
            ([.overdue, .stillAccepted, .courseWeight(0.07)], "CHEM 231", "Overdue · Still accepted · ~7% of CHEM 231"),
            ([.dueIn(hours: 0.5)], "BIO 101", "Due in 30m"),
            ([.dueIn(hours: 0.001), .courseBelowGoal], "BIO 101", "Due in 1m · course below your goal"),
            ([.noDueDate, .courseBelowGoal, .courseWeight(0.05)], "HIST 210", "No due date · course below your goal · ~5% of HIST 210"),
            ([.dueIn(hours: 24)], "BIO 101", "Due in 24h"),
            ([], "BIO 101", ""),
        ]
        for (factors, code, expected) in reasons {
            #expect(Self.plain(DashboardText.reason(factors, courseCode: code, locale: Self.enUS)) == expected, "\(factors)")
        }

        let chicago = Self.calendar(Self.chicago)
        let rows: [(DashboardProjection.AttentionItem.Content, String, String)] = [
            (.missingOpen(title: "Worksheet 3: Integration by Parts", courseCode: "MATH 122"),
             "Worksheet 3: Integration by Parts is missing", "MATH 122 · still accepted"),
            (.missingClosed(courseCode: "BIO 101"), "BIO 101: missing work is closed", "Talk to your instructor"),
            (.dueSoon(title: "Exam 1", dueAt: Self.at(1_790_016_600), courseCode: "PSY 101"), "Exam 1 due 1:50 PM", "PSY 101"),
            (.overload(start: Self.at(1_790_917_200)), "Busy stretch starting Oct 2, 2026", "Several items are due close together"),
            (.other(title: "Lab 2", courseCode: "BIO 101"), "Lab 2", "BIO 101"),
        ]
        for (content, title, subtitle) in rows {
            #expect(Self.plain(DashboardText.attentionTitle(content, calendar: chicago, locale: Self.enUS)) == title, "\(content)")
            #expect(DashboardText.attentionSubtitle(content, locale: Self.enUS) == subtitle, "\(content)")
        }

        // "1 change" can only come from the catalog's `one` form: the English fallback reads "1 changes".
        for (count, expected) in [(0, "0 changes since 2:13 PM"), (1, "1 change since 2:13 PM"), (6, "6 changes since 2:13 PM")] {
            let summary = DashboardProjection.ChangeSummary(count: count, asOf: Self.at(1_790_017_980))
            #expect(Self.plain(DashboardText.changeSummary(summary, calendar: chicago, locale: Self.enUS)) == expected)
        }
    }

    // MARK: - Differential sweeps against 628ee09 (exact bytes)
    // The expectations compare a count, not the array: Swift Testing prints an operand's whole
    // value, and the full mismatch lists made 10-16 kB log lines that cost the rest of the
    // console in mutation run 36798377151. The comment carries the first three.

    @Test("Every planned reminder, names shown and hidden, equals 628ee09's words",
          arguments: ["flagship", "finals", "grading-periods", "large"])
    func reminderSweep(persona: String) async throws {
        #expect(RemindersConfig.weekdayNamingDays == LegacyEnglish.weekdayNamingDays)
        var checked = 0
        for now in [Self.seen, Self.seen.addingTimeInterval(7 * 86_400)] {
            let snapshot = try await PersonaSnapshotHarness.fetchSnapshot(persona: persona, now: now)
            for zone in ["America/New_York", "Asia/Kolkata"] {
                let outcome = RendererSweep.notifications(snapshot: snapshot, now: now,
                                                          timeZone: TimeZone(identifier: zone) ?? .gmt, locale: Self.enUS)
                let mismatches = outcome.mismatches.count
                #expect(mismatches == 0, "\(persona) \(zone): \(outcome.mismatches.prefix(3))")
                checked += outcome.checked
            }
        }
        #expect(checked > 100, "\(persona): only \(checked) strings compared")
    }

    @Test("Every dashboard row over the personas equals what the app showed at 628ee09",
          arguments: ["flagship", "flagship-previous", "finals", "grading-periods", "large"])
    func dashboardSweep(persona: String) async throws {
        var checked = 0
        for now in [Self.seen, Self.at(1_790_600_400), Self.seen.addingTimeInterval(14 * 86_400)] {
            let snapshot = try await PersonaSnapshotHarness.fetchSnapshot(persona: persona, now: now)
            var digest: ChangeDigest?
            if persona == "flagship" {
                let previous = try await PersonaSnapshotHarness.fetchSnapshot(persona: "flagship-previous", now: now)
                digest = ChangeDigest.diff(old: previous, new: snapshot)
            }
            for zone in [Self.chicago, TimeZone(identifier: "UTC") ?? .gmt] {
                let outcome = RendererSweep.dashboard(snapshot: snapshot, digest: digest, now: now,
                                                      calendar: Self.calendar(zone), locale: Self.enUS)
                let mismatches = outcome.mismatches.count
                #expect(mismatches == 0, "\(persona): \(outcome.mismatches.prefix(3))")
                checked += outcome.checked
            }
        }
        #expect(checked > 10, "\(persona): only \(checked) strings compared")
    }

    @Test("The reason over a grid of times, weights and modifiers (non-finite included), and the chip for 0-30 changes")
    func reasonAndChipGrids() {
        let grid = RendererSweep.reasonGrid(locale: Self.enUS)
        let gridMismatches = grid.mismatches.count
        #expect(gridMismatches == 0, "\(grid.mismatches.prefix(3))")
        #expect(grid.checked == 16 * 9 * 7)
        let chips = RendererSweep.changeSummaries(calendar: Self.calendar(Self.chicago), locale: Self.enUS)
        let chipMismatches = chips.mismatches.count
        #expect(chipMismatches == 0, "\(chips.mismatches.prefix(3))")
        #expect(chips.checked == 3 * 31)
    }

    // MARK: - The catalog

    /// Every key the renderers use is compiled into the TallyStrings bundle with this English
    /// value (the plural `dashboard.changes.count` is pinned by "1 change since" above).
    @Test("Every renderer key resolves from the compiled TallyStrings catalog")
    func everyKeyResolves() throws {
        let english: [String: String] = [
            "notification.subject.assignment": "%1$@ · %2$@", "notification.subject.hidden": "An assignment",
            "notification.course.hidden": "a course", "notification.digest.hiddenItem": "An assignment",
            "notification.due.body": "Due %@.", "notification.due.finalBody": "Due %@, if you haven't submitted yet.",
            "notification.missing.stillAcceptedUntil": "Still accepted until %@.",
            "notification.missing.noClosingDate": "Past due. Canvas lists no closing date.",
            "notification.exam.body": "Due %@.", "notification.gradePosted.title": "New grade posted",
            "notification.belowGoal.title": "%@ needs attention", "notification.belowGoal.body": "Open Tally to see your standing.",
            "notification.digest.title": "Tomorrow", "notification.digest.count": "%lld due",
            "notification.digest.countWithFirst": "%1$lld due · %2$@ first", "notification.weekAhead.title": "This week",
            "notification.weekAhead.count": "%lld due", "notification.weekAhead.countWithBusiest": "%1$lld due · busiest %2$@",
            "notification.sentinel.title": "Tally hasn't refreshed since %@",
            "notification.sentinel.body": "Open Tally to update your reminders.", "notification.dayAtTime": "%1$@ at %2$@",
            "dashboard.reason.join": "%1$@ · %2$@", "dashboard.reason.dueInMinutes": "Due in %lldm",
            "dashboard.reason.dueInHours": "Due in %lldh", "dashboard.reason.overdue": "Overdue",
            "dashboard.reason.stillAccepted": "Still accepted", "dashboard.reason.courseWeight": "~%1$@ of %2$@",
            "dashboard.reason.courseBelowGoal": "course below your goal", "dashboard.reason.nearBoundary": "near a grade boundary",
            "dashboard.reason.noDueDate": "No due date", "dashboard.attention.missingOpen.title": "%@ is missing",
            "dashboard.attention.missingOpen.subtitle": "%@ · still accepted",
            "dashboard.attention.missingClosed.title": "%@: missing work is closed",
            "dashboard.attention.missingClosed.subtitle": "Talk to your instructor",
            "dashboard.attention.dueSoon.title": "%1$@ due %2$@", "dashboard.attention.overload.title": "Busy stretch starting %@",
            "dashboard.attention.overload.subtitle": "Several items are due close together", "dashboard.changes.since": "%1$@ since %2$@",
        ]
        let items = (try? FileManager.default.contentsOfDirectory(at: Bundle.main.bundleURL, includingPropertiesForKeys: nil)) ?? []
        let strings = try #require(items.first { $0.lastPathComponent.hasSuffix("TallyStrings.bundle") }.flatMap(Bundle.init(url:)))
        for (key, value) in english {
            #expect(strings.localizedString(forKey: key, value: "<missing>", table: "Localizable") == value, "\(key)")
        }
    }

    // MARK: - A locale sample

    /// en_GB: 24-hour times and day-first dates, English words. (ICU's short time for en_GB and
    /// en_DE has no leading zero: "8:30", "9:00", as run 36795199706 showed.)
    @Test("en_GB: 24-hour times, day-first dates, the same words")
    func britishEnglish() {
        let gb = Locale(identifier: "en_GB")
        #expect(Self.render(.due(Self.lab, dueAt: Self.at(1_790_031_600), isFinalReminder: false), locale: gb)
                    == ["Lab Report 4 · BIO 101", "Due today at 18:00."])
        #expect(Self.render(.examReminder(Self.lab, dueAt: Self.at(1_790_861_400)), locale: gb)[1] == "Due 1 Oct at 8:30.")
        #expect(Self.render(.sentinel(lastSuccess: Self.at(1_789_931_640)), locale: gb)[0] == "Tally hasn't refreshed since yesterday at 14:14")
        let chicago = Self.calendar(Self.chicago)
        #expect(Self.plain(DashboardText.attentionTitle(.dueSoon(title: "Exam 1", dueAt: Self.at(1_790_016_600), courseCode: "PSY 101"),
                                                        calendar: chicago, locale: gb)) == "Exam 1 due 13:50")
        #expect(Self.plain(DashboardText.attentionTitle(.overload(start: Self.at(1_790_917_200)), calendar: chicago, locale: gb))
                    == "Busy stretch starting 2 Oct 2026")
        #expect(Self.plain(DashboardText.changeSummary(.init(count: 6, asOf: Self.at(1_790_017_980)), calendar: chicago, locale: gb))
                    == "6 changes since 14:13")
    }

    /// A German iPhone with Tally in English: German conventions, English words, never "heute"
    /// or "morgen" inside an English sentence (plan 08 §3.3's mixed-language risk).
    @Test("German regional settings with the English UI: German numbers and times, English words")
    func germanRegionEnglishUI() {
        let locale = TallyLocale.effective(uiLanguage: "en", current: Locale(identifier: "de_DE"))
        #expect(locale.identifier == "en_DE")
        #expect(Self.render(.due(Self.lab, dueAt: Self.at(1_790_031_600), isFinalReminder: false), locale: locale)[1]
                    == "Due today at 18:00.")
        #expect(Self.render(.examReminder(Self.lab, dueAt: Self.at(1_790_085_600)), locale: locale)[1] == "Due tomorrow at 9:00.")
        #expect(Self.plain(DashboardText.reason([.overdue, .courseWeight(0.11)], courseCode: "BIO 101", locale: locale))
                    == "Overdue · ~11 % of BIO 101")
        #expect(Self.plain(DashboardText.changeSummary(.init(count: 1, asOf: Self.at(1_790_017_980)),
                                                       calendar: Self.calendar(Self.chicago), locale: locale))
                    == "1 change since 14:13")
    }
}
