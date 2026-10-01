import AppIntents
import Foundation
import Testing
import TallyDomain
import TallyIntents
import TallyStore
import UserNotifications
@testable import Tally
@testable import TallyGlance

/// M3-D: the intents' logic, hosted in the app. The spoken answers in English; "Refresh Tally"'s
/// answers; the Focus filter's notification predicate, applied to a test notification's criteria;
/// and the App Intents metadata the build ships in the app and in the widget extension (titles and
/// phrases are build-time constants, so this is where a missing intent or string would show).
///
/// No test runs an intent's `perform()` against the process-wide `RefreshIntentBridge`: other suites
/// attach coordinators to it, and a refresh here would run theirs.
@Suite("Intents M3-D: spoken answers, refresh, the Focus filter, the metadata the build ships")
struct WidgetIntentsTests {
    private static let enUS = Locale(identifier: "en_US")
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        return calendar
    }()

    private static func date(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute)) ?? .distantPast
    }

    /// Tuesday 2026-10-06, 10:00 in New York.
    private static let now = date(6, 10)

    private static func item(_ id: String, _ title: String, _ code: String?, _ due: Date) -> GlanceDueItem {
        GlanceDueItem(id: id, courseShortCode: code, title: title, dueAt: due, missing: false, late: false, excused: false,
                      submitted: false)
    }

    private static func glance(asOf: Date = WidgetIntentsTests.date(6, 8, 30), _ items: [GlanceDueItem]) -> GlanceReadResult {
        .loaded(GlanceProjection(generation: 1, asOf: asOf, gradeSummary: .band(.aRange), courses: [], dueSoon: items))
    }

    /// The resource's text in en_US, with the narrow and no-break spaces ICU puts in times made plain.
    private static func text(_ resource: LocalizedStringResource) -> String {
        var resource = resource
        resource.locale = enUS
        return String(localized: resource).replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    // MARK: Spoken answers

    @Test("What's due next, spoken: three items with course and time, then 'Plus 1 more' and the overdue count; never a grade")
    func dueNextDialog() {
        let result = Self.glance([
            Self.item("late", "Reading 1", "HIST 210", Self.date(5, 9)),
            Self.item("lab", "Lab Report 4", "BIO 101", Self.date(6, 12)),
            Self.item("quiz", "Quiz 3", "CHEM 110", Self.date(7, 9)),
            Self.item("essay", "Essay", nil, Self.date(9, 17)),
            Self.item("final", "Final", "BIO 101", Self.date(3, 9, month: 11)),
        ])
        let answer = GlanceIntentAnswers.dueNext(result, now: Self.now, calendar: Self.calendar)
        let spoken = Self.text(GlanceIntentAnswers.dialog(answer, calendar: Self.calendar, locale: Self.enUS))
        #expect(spoken == "Next up: Lab Report 4 (BIO 101), due today at 12:00 PM, Quiz 3 (CHEM 110), due tomorrow at 9:00 AM, "
            + "and Essay, due Friday at 5:00 PM. Plus 1 more. You also have 1 overdue.")
        #expect(!spoken.contains("A range") && !spoken.contains("%"), "a spoken answer carries no grade: \(spoken)")
    }

    @Test("What's due today, spoken: nothing left today, and how old the data is once it is stale")
    func dueTodayDialog() {
        let result = Self.glance(asOf: Self.date(6, 6), [Self.item("quiz", "Quiz 3", "CHEM 110", Self.date(7, 9))])
        let answer = GlanceIntentAnswers.dueToday(result, now: Self.now, calendar: Self.calendar)
        #expect(Self.text(GlanceIntentAnswers.dialog(answer, calendar: Self.calendar, locale: Self.enUS))
            == "Nothing else is due today. As of 6:00 AM.")
    }

    @Test("Spoken answers: the widgets' message when there is no glance, and a generic word with names hidden")
    func messagesAndHiddenNames() {
        let signedOut = GlanceIntentAnswers.dueNext(.noAccount, now: Self.now, calendar: Self.calendar)
        #expect(Self.text(GlanceIntentAnswers.dialog(signedOut, calendar: Self.calendar, locale: Self.enUS))
            == "Open Tally to see what's due.")

        let item = GlanceSummary.Item(id: "lab", title: "Lab Report 4", courseCode: "BIO 101", dueAt: Self.date(6, 12), day: .today)
        let hidden = GlanceAnswerList(kind: .dueToday, items: [item], moreCount: 0, moreIsLowerBound: false, overdueCount: 0,
                                      hidesCourseNames: true, asOf: Self.date(6, 9), isStale: false, asOfIsBeforeToday: false)
        let spoken = Self.text(GlanceIntentAnswers.dialog(.list(hidden), calendar: Self.calendar, locale: Self.enUS))
        #expect(spoken == "Due today: An assignment, due today at 12:00 PM.")
    }

    @Test("Refresh Tally, spoken: one honest sentence for each outcome")
    func refreshDialogs() {
        let cases: [(RefreshAnswer, String)] = [
            (.updated, "Tally is up to date."),
            (.stillRefreshing, "Tally is still refreshing. Check back in a moment."),
            (.offline(showing: Self.date(6, 9)), "You're offline. Tally is showing data from 9:00 AM."),
            (.offline(showing: nil), "You're offline, so Tally couldn't refresh."),
            (.signInExpired, "Your Canvas sign-in expired. Open Tally to sign in again."),
            (.failed(showing: Self.date(5, 9)), "Tally couldn't refresh. It's showing data from Mon 9:00 AM."),
            (.failed(showing: nil), "Tally couldn't refresh yet."),
            (.openTally, "Open Tally to refresh."),
        ]
        for (answer, expected) in cases {
            #expect(Self.text(answer.dialog(now: Self.now, calendar: Self.calendar, locale: Self.enUS)) == expected)
        }
    }

    // MARK: The Focus filter

    @Test("Focus criteria: one course and one level per notification, each between separators")
    func focusCriteria() {
        #expect(FocusFilterCriteria.criteria(courseID: "123", level: .high) == ";course=123;level=high;")
        #expect(FocusFilterCriteria.criteria(courseID: nil, level: .info) == ";level=info;")
        #expect(FocusFilterCriteria.predicate(courseIDs: [], onlyUrgent: false) == nil, "nothing to filter")
    }

    @Test("Focus predicate: a notification without criteria always comes through; others match the courses and urgency")
    func focusPredicate() throws {
        let courses = try #require(FocusFilterCriteria.predicate(courseIDs: ["123"], onlyUrgent: false))
        #expect(courses.evaluate(with: nil), "a Focus filter must never silence a notification that carries no criteria")
        #expect(courses.evaluate(with: ";course=123;level=info;"))
        #expect(!courses.evaluate(with: ";course=12;level=info;"))
        #expect(!courses.evaluate(with: ";course=1234;level=info;"))

        let urgent = try #require(FocusFilterCriteria.predicate(courseIDs: [], onlyUrgent: true))
        #expect(urgent.evaluate(with: ";course=9;level=critical;"))
        #expect(urgent.evaluate(with: ";level=high;"))
        #expect(!urgent.evaluate(with: ";course=9;level=medium;"))
        #expect(!urgent.evaluate(with: ";level=info;"))

        // A test notification, as the scheduler would tag it.
        let both = try #require(FocusFilterCriteria.predicate(courseIDs: ["123", "456"], onlyUrgent: true))
        let tagged = UNMutableNotificationContent()
        tagged.filterCriteria = FocusFilterCriteria.criteria(courseID: "456", level: .critical)
        #expect(both.evaluate(with: tagged.filterCriteria))
        tagged.filterCriteria = FocusFilterCriteria.criteria(courseID: "456", level: .info)
        #expect(!both.evaluate(with: tagged.filterCriteria))
        tagged.filterCriteria = FocusFilterCriteria.criteria(courseID: "789", level: .high)
        #expect(!both.evaluate(with: tagged.filterCriteria))
        #expect(both.evaluate(with: UNMutableNotificationContent().filterCriteria), "today's untagged notifications")
    }

    @Test("Tally's Focus filter: its parameters become the predicate and the summary iOS shows in Focus settings")
    func tallyFocusFilter() throws {
        var filter = TallyFocusFilter()
        #expect(filter.appContext.notificationFilterPredicate == nil, "a new filter lets everything through")

        filter.courses = [CourseEntity(id: "123", code: "BIO 101")]
        filter.onlyUrgent = true
        let predicate = try #require(filter.appContext.notificationFilterPredicate)
        #expect(predicate.evaluate(with: FocusFilterCriteria.criteria(courseID: "123", level: .critical)))
        #expect(!predicate.evaluate(with: FocusFilterCriteria.criteria(courseID: "999", level: .critical)))
        #expect(!predicate.evaluate(with: FocusFilterCriteria.criteria(courseID: "123", level: .info)))
        #expect(Self.text(filter.displayRepresentation.title) == "BIO 101")
        #expect(filter.displayRepresentation.subtitle.map(Self.text) == "Only urgent alerts")
    }

    // MARK: What the build ships

    /// The App Intents metadata Xcode extracted into a bundle at build time.
    private static func metadata(in bundle: Bundle) throws -> String {
        let directory = bundle.bundleURL.appending(path: "Metadata.appintents")
        let file = directory.appending(path: "extract.actionsdata")
        guard let data = try? Data(contentsOf: file) else {
            let listing = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            throw MetadataError.missing("\(file.path) is missing; Metadata.appintents holds \(listing)")
        }
        return String(decoding: data, as: UTF8.self)
    }

    private enum MetadataError: Error { case missing(String) }

    /// Every string value in the metadata that is one of this project's `AppIntents` keys.
    private static func intentKeys(in metadata: String) throws -> Set<String> {
        let regex = try NSRegularExpression(pattern: "\"(intent\\.[A-Za-z.]*[A-Za-z])\"")
        let matches = regex.matches(in: metadata, range: NSRange(metadata.startIndex..., in: metadata))
        return Set(matches.compactMap { Range($0.range(at: 1), in: metadata).map { String(metadata[$0]) } })
    }

    @Test("The build ships every intent: the app's and the widget's metadata name them, and every title resolves")
    func appIntentsMetadata() throws {
        let app = Bundle.main
        let plugins = try #require(app.builtInPlugInsURL)
        let widget = try #require(Bundle(url: plugins.appending(path: "TallyWidgets.appex")))

        let appMetadata = try Self.metadata(in: app)
        let appIntents = ["RefreshTallyIntent", "OpenTallyIntent", "WhatsDueNextIntent", "WhatsDueTodayIntent",
                          "TallyFocusFilter", "CourseEntity", "TallyDestination"]
        for name in appIntents {
            #expect(appMetadata.contains(name), "the app's metadata does not name \(name)")
        }
        let widgetMetadata = try Self.metadata(in: widget)
        let widgetIntents = ["GlanceWidgetIntent", "RefreshTallyIntent", "OpenTallyIntent"]
        for name in widgetIntents {
            #expect(widgetMetadata.contains(name), "the widget's metadata does not name \(name)")
        }
        #expect(!widgetMetadata.contains("TallyFocusFilter"), "the Focus filter belongs to the app alone")

        var counts: [String] = []
        for (name, bundle, metadata) in [("app", app, appMetadata), ("widget", widget, widgetMetadata)] {
            let keys = try Self.intentKeys(in: metadata)
            #expect(!keys.isEmpty, "\(name): no intent.* key in the metadata")
            for key in keys.sorted() {
                #expect(bundle.localizedString(forKey: key, value: "<missing>", table: "AppIntents") != "<missing>",
                        "\(name): \(key) is not in its AppIntents table")
            }
            counts.append("\(name) \(keys.count) keys")
        }

        // The App Shortcuts phrases: in the metadata, and in the app's own AppShortcuts table.
        let phrases = ["What's due next in ${applicationName}", "What's next in ${applicationName}",
                       "What's due today in ${applicationName}", "What's due in ${applicationName}",
                       "Refresh ${applicationName}", "Update ${applicationName}"]
        for phrase in phrases {
            #expect(app.localizedString(forKey: phrase, value: "<missing>", table: "AppShortcuts") == phrase, "\(phrase)")
        }
        #expect(appMetadata.contains("applicationName"), "the app's metadata holds no App Shortcuts phrase")
        // Evidence for the CI log (the console keeps lines that say "passed").
        print("M3D-APPINTENTS | app names \(appIntents.count), widget names \(widgetIntents.count) | \(counts.joined(separator: ", ")) | check passed")
    }
}
