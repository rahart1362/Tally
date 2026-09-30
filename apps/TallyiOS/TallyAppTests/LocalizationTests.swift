import Foundation
import Testing
import TallyStrings
@testable import TallyFeatures

/// Plan 08 L10N-01 (§3.1, §3.3, §3.9): the shared String Catalog resolves through `#bundle`, the
/// app and the widget ship English only, the formatting locale keeps the UI language, and
/// `TallyFormat` is locale-aware while matching today's English output byte for byte.
@Suite("L10N-01: TallyStrings catalog, shipped localizations, TallyLocale and TallyFormat")
struct LocalizationTests {
    private static let enUS = Locale(identifier: "en_US")

    // MARK: - The catalog through #bundle

    /// Spike question 1: `L10n` (a nonisolated target with resources) called from the main actor.
    /// "Average of 1 course" can only come from the catalog's `one` form: the English
    /// `defaultValue` alone would read "Average of 1 courses".
    @MainActor
    @Test("The hero caption's plural forms come from the TallyStrings catalog (main-actor caller)",
          arguments: [(0, "Average of 0 courses"), (1, "Average of 1 course"), (5, "Average of 5 courses")])
    func heroCaptionPlural(count: Int, expected: String) {
        var resource = L10n.Dashboard.averageOfCourses(count)
        resource.locale = Self.enUS
        #expect(String(localized: resource) == expected)
    }

    @Test("#bundle names the TallyStrings resource bundle, not the app")
    func resourceBundle() {
        let resource = L10n.Dashboard.averageOfCourses(2)
        #expect(resource.key == "dashboard.hero.averageOfCourses")
        let bundle = String(describing: resource.bundle)
        #expect(bundle.contains("TallyStrings"), "\(bundle)")
    }

    // MARK: - What the app and the widget ship

    /// `en.lproj` in the app, the widget and the TallyStrings bundle inside each; each declares
    /// English as its development region and only localization (main ships en only; L10N-04 adds
    /// es). The display names and the widget gallery keys resolve from the compiled catalogs.
    @Test("The app and the widget ship en.lproj, declare [en] and resolve their catalogs")
    func shippedLocalizations() throws {
        let app = Bundle.main
        #expect(app.bundleURL.pathExtension == "app", "the tests run hosted in Tally.app: \(app.bundleURL.path)")
        Self.expectEnglishOnly(app, displayName: "Tally")

        let plugins = try #require(app.builtInPlugInsURL)
        let widget = try #require(Bundle(url: plugins.appending(path: "TallyWidgets.appex")))
        Self.expectEnglishOnly(widget, displayName: "Tally Widgets")
        let gallery = [
            "widget.nextUp.displayName": "Next Up",
            "widget.nextUp.description": "The next thing due in your courses.",
            "widget.standing.displayName": "Standing",
            "widget.standing.description":
                "Your average grade band, if you choose to show grades in widgets. Hidden while your iPhone is locked.",
        ]
        for (key, english) in gallery {
            #expect(widget.localizedString(forKey: key, value: "<missing>", table: nil) == english, "\(key)")
        }

        for container in [app, widget] {
            let strings = try #require(Self.stringsBundle(in: container), "no TallyStrings bundle in \(container.bundleURL.lastPathComponent)")
            #expect(Self.languages(of: strings) == ["en"], "\(strings.bundleURL.path): \(strings.localizations)")
            #expect(FileManager.default.fileExists(atPath: strings.bundleURL.appending(path: "en.lproj").path))
        }
    }

    private static func expectEnglishOnly(_ bundle: Bundle, displayName: String) {
        let name = bundle.bundleURL.lastPathComponent
        #expect(bundle.object(forInfoDictionaryKey: "CFBundleDevelopmentRegion") as? String == "en", "\(name)")
        #expect(bundle.object(forInfoDictionaryKey: "CFBundleLocalizations") as? [String] == ["en"], "\(name)")
        #expect(languages(of: bundle) == ["en"], "\(name): \(bundle.localizations)")
        #expect(FileManager.default.fileExists(atPath: bundle.bundleURL.appending(path: "en.lproj").path), "\(name)")
        #expect(bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String == displayName,
                "\(name): InfoPlist.xcstrings was not compiled into en.lproj")
    }

    private static func languages(of bundle: Bundle) -> Set<String> {
        Set(bundle.localizations).subtracting(["Base"])
    }

    /// SwiftPM's resource bundle for TallyStrings (Xcode names it `<package>_<target>.bundle`),
    /// at the top level of the app or the extension.
    private static func stringsBundle(in container: Bundle) -> Bundle? {
        let items = (try? FileManager.default.contentsOfDirectory(at: container.bundleURL, includingPropertiesForKeys: nil)) ?? []
        return items.first { $0.lastPathComponent.hasSuffix("TallyStrings.bundle") }.flatMap(Bundle.init(url:))
    }

    // MARK: - The formatting locale

    @Test("TallyLocale.effective keeps the region and preferences and takes the UI language",
          arguments: [
              ("en", "en_US", "en_US"),
              ("en", "en_GB", "en_GB"),
              ("es", "es_US", "es_US"),
              ("es", "es_ES", "es_ES"),
              ("en", "fr_FR", "en_FR"),
              ("en", "de_DE", "en_DE"),          // German iPhone, Tally in English (the mixed case)
              ("es", "en_US", "es_US"),          // per-app Spanish on an English iPhone
              ("en", "en_US@hours=h23", "en_US@hours=h23"), // a 24-hour override survives
              ("Base", "de_DE", "de_DE"),
          ])
    func effectiveLocale(uiLanguage: String, current: String, expected: String) {
        #expect(TallyLocale.effective(uiLanguage: uiLanguage, current: Locale(identifier: current)).identifier == expected)
    }

    @Test("TallyLocale.effective without a UI language is the current locale")
    func effectiveWithoutUILanguage() {
        #expect(TallyLocale.effective(uiLanguage: nil, current: Locale(identifier: "de_DE")).identifier == "de_DE")
    }

    // MARK: - TallyFormat across the locale matrix

    /// 2026-09-21 14:13:20 UTC.
    private static let instant = Date(timeIntervalSince1970: 1_790_000_000)
    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        return calendar
    }

    /// Percent, share, time, the named days (-1, 0, 1 mid-sentence; 0 at the start) and a list.
    /// Spaces are compared as plain spaces: ICU puts U+00A0 or U+202F before "%" and "PM", and
    /// which one changes between ICU releases.
    private static func row(_ locale: Locale) -> [String] {
        let days = [-1, 0, 1].map { TallyFormat.namedDay(offset: $0, locale: locale) ?? "<nil>" }
        return [
            TallyFormat.percent(90.1, locale: locale),
            TallyFormat.share(0.5, locale: locale),
            TallyFormat.time(instant, calendar: utc, locale: locale),
        ] + days + [
            TallyFormat.namedDay(offset: 0, context: .beginningOfSentence, locale: locale) ?? "<nil>",
            TallyFormat.list(["A", "B", "C"], locale: locale),
        ]
    }

    private static func plainSpaces(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { $0 == "\u{00A0}" || $0 == "\u{202F}" ? " " : $0 }))
    }

    @Test("TallyFormat: en_US, en_GB, es_US, es_ES, fr_FR and German regional settings with the English UI")
    func formatMatrix() {
        let germanWithEnglishUI = TallyLocale.effective(uiLanguage: "en", current: Locale(identifier: "de_DE"))
        let actual: [String: [String]] = [
            "en_US": Self.row(Locale(identifier: "en_US")).map(Self.plainSpaces),
            "en_GB": Self.row(Locale(identifier: "en_GB")).map(Self.plainSpaces),
            "es_US": Self.row(Locale(identifier: "es_US")).map(Self.plainSpaces),
            "es_ES": Self.row(Locale(identifier: "es_ES")).map(Self.plainSpaces),
            "fr_FR": Self.row(Locale(identifier: "fr_FR")).map(Self.plainSpaces),
            "de_DE+en": Array(Self.row(germanWithEnglishUI).map(Self.plainSpaces).dropLast()),
        ]
        let expected: [String: [String]] = [
            "en_US": ["90.1%", "50%", "2:13 PM", "yesterday", "today", "tomorrow", "Today", "A, B, and C"],
            "en_GB": ["90.1%", "50%", "14:13", "yesterday", "today", "tomorrow", "Today", "A, B and C"],
            "es_US": ["90.1%", "50%", "2:13 p.m.", "ayer", "hoy", "mañana", "Hoy", "A, B y C"],
            "es_ES": ["90,1 %", "50 %", "14:13", "ayer", "hoy", "mañana", "Hoy", "A, B y C"],
            "fr_FR": ["90,1 %", "50 %", "14:13", "hier", "aujourd’hui", "demain", "Aujourd’hui", "A, B et C"],
            // German number and time conventions, English words: never "morgen" in an English UI.
            "de_DE+en": ["90,1 %", "50 %", "14:13", "yesterday", "today", "tomorrow", "Today"],
        ]
        for key in expected.keys.sorted() {
            #expect(actual[key] == expected[key], "\(key)")
        }
    }

    @Test("The mixed-language case: formatting with Locale.current on a German iPhone gives German words")
    func mixedLanguageRisk() {
        let german = Locale(identifier: "de_DE")
        #expect(TallyFormat.namedDay(offset: 1, locale: german) == "morgen")
        #expect(TallyFormat.namedDay(offset: 1, locale: TallyLocale.effective(uiLanguage: "en", current: german)) == "tomorrow")
    }

    @Test("Named days only for yesterday, today and tomorrow")
    func namedDayRange() {
        #expect(TallyFormat.namedDay(offset: 2, locale: Self.enUS) == nil)
        #expect(TallyFormat.namedDay(offset: -2, locale: Self.enUS) == nil)
    }

    /// L10N-03b swaps `ScreenFormatter`'s "+ \"%\"" for these; the English must not change. Every
    /// 0.05 step from 0 to 100 (the ties included) and every 0.0005 share.
    @Test("en_US: TallyFormat.percent and share equal ScreenFormatter's text today")
    func englishParityWithScreenFormatter() {
        let screen = ScreenFormatter(now: Self.instant, calendar: Self.utc, locale: Self.enUS)
        var mismatches: [String] = []
        for step in 0...2_000 {
            let percent = Double(step) / 20
            let old = screen.percentText(percent), new = TallyFormat.percent(percent, locale: Self.enUS)
            if old != new { mismatches.append("percent \(percent): \(old) vs \(new)") }
            let share = Double(step) / 2_000
            let oldShare = screen.shareText(share), newShare = TallyFormat.share(share, locale: Self.enUS)
            if oldShare != newShare { mismatches.append("share \(share): \(oldShare) vs \(newShare)") }
        }
        #expect(mismatches.isEmpty, "\(mismatches.prefix(10))")
    }
}
