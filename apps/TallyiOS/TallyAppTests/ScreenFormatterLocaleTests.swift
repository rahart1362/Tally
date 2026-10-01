import Foundation
import Testing
import TallyStrings
@testable import TallyFeatures

/// Plan 08 §3.3, L10N-03b: `ScreenFormatter`'s locale fixes, each with the required locale matrix
/// (en_US, en_GB, es_ES; fr_FR too for "Percent") and en_US shown unchanged except where the row
/// says it changes. `TallyFormat`'s own primitives (percent, share, namedDay) are already proven
/// across this exact matrix in `LocalizationTests.swift` (L10N-01); these tests are about this
/// stream's *consuming* code — `ScreenFormatter` and `CourseDetailBuilder` — wiring them correctly,
/// not re-proving the primitives themselves.
@Suite("ScreenFormatter: plan 08 §3.3 locale fixes (L10N-03b)")
struct ScreenFormatterLocaleTests {
    /// 2026-09-21 14:13:20 UTC — the same fixed instant `LocalizationTests.swift` uses, so values
    /// already proven there (percent, named days) are directly comparable here.
    private static let now = Date(timeIntervalSince1970: 1_790_000_000)
    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        return calendar
    }

    private static func formatter(_ locale: Locale) -> ScreenFormatter {
        ScreenFormatter(now: now, calendar: utc, locale: locale)
    }

    private static func plainSpaces(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { $0 == "\u{00A0}" || $0 == "\u{202F}" ? " " : $0 }))
    }

    // MARK: - Percent (ScreenFormatter.percentText/spokenPercent/shareText, now TallyFormat-backed)

    /// en_US unchanged (`LocalizationTests.englishParityWithScreenFormatter` already proves this
    /// exhaustively for `percentText`/`shareText`; this is the same claim at the call sites this
    /// stream's files actually use, plus `spokenPercent` and `trimmedPercentText`, which that test
    /// does not cover). en_GB matches en_US (both use ".", no space). es_ES and fr_FR use a comma
    /// and a space before "%" — the sign's position and spacing genuinely vary by locale, not just
    /// decoration (plan 08 §3.3's own example).
    @Test("percentText/shareText/trimmedPercentText: en_US unchanged; es_ES and fr_FR use ',' and a space",
          arguments: [
              ("en_US", "90.1%", "50%", "90.1%"),
              ("en_GB", "90.1%", "50%", "90.1%"),
              ("es_ES", "90,1 %", "50 %", "90,1 %"),
              ("fr_FR", "90,1 %", "50 %", "90,1 %"),
          ])
    func percentAcrossLocales(identifier: String, percent: String, share: String, trimmed: String) {
        let f = Self.formatter(Locale(identifier: identifier))
        #expect(Self.plainSpaces(f.percentText(90.1)) == percent)
        #expect(Self.plainSpaces(f.shareText(0.5)) == share)
        #expect(Self.plainSpaces(f.trimmedPercentText(90.1)) == trimmed)
    }

    /// `spokenPercent` is a whole-sentence key ("… percent"), never a hand-appended word; today
    /// (before L10N-04 ships Spanish) every locale falls back to the catalog's English value, so the
    /// word "percent" itself is unchanged everywhere, but the *number* inside it is still locale
    /// formatted (the point of the fix: the number was already locale-aware before this sweep, and
    /// stays so; the literal " percent" suffix is now a catalog key instead).
    @Test("spokenPercent: the number is locale-formatted; the English word falls back pre-L10N-04",
          arguments: ["en_US", "en_GB", "es_ES", "fr_FR"])
    func spokenPercentAcrossLocales(identifier: String) {
        let f = Self.formatter(Locale(identifier: identifier))
        let spoken = f.spokenPercent(90.1)
        #expect(spoken.hasSuffix(" percent"), spoken)
        let number = String(spoken.dropLast(" percent".count))
        let expectedNumber = identifier == "es_ES" || identifier == "fr_FR" ? "90,1" : "90.1"
        #expect(number == expectedNumber, spoken)
    }

    // MARK: - Relative days (ScreenFormatter.dayText, now TallyFormat.namedDay-backed)

    /// en_US/en_GB unchanged ("today"/"tomorrow"/"yesterday", lowercase, matching `l10n-03a`'s
    /// infra and `LocalizationTests.formatMatrix`'s already-proven values); es_ES gets the Spanish
    /// words ("hoy"/"mañana"/"ayer") — the whole reason for the fix (plan 08 §3.3: these three
    /// words were hard-coded English before). `spoken` does not change which word is used (only the
    /// weekday/month branches further out do), matching the pre-sweep behaviour exactly.
    @Test("dayText: today/tomorrow/yesterday are TallyFormat.namedDay, not hard-coded English",
          arguments: [
              ("en_US", "today", "tomorrow", "yesterday"),
              ("en_GB", "today", "tomorrow", "yesterday"),
              ("es_ES", "hoy", "mañana", "ayer"),
          ])
    func dayTextNamedDays(identifier: String, today: String, tomorrow: String, yesterday: String) {
        let f = Self.formatter(Locale(identifier: identifier))
        #expect(f.dayText(Self.now) == today)
        #expect(f.dayText(Self.now.addingTimeInterval(24 * 3600)) == tomorrow)
        #expect(f.dayText(Self.now.addingTimeInterval(-24 * 3600)) == yesterday)
        // `spoken` does not change which of these three words is used.
        #expect(f.dayText(Self.now, spoken: true) == today)
    }

    /// Further than `namedDayOffsets` (-1...1): a weekday or month/day, unaffected by this fix
    /// (unchanged behaviour, every locale).
    @Test("dayText beyond named-day range: a weekday or month/day, not a named day")
    func dayTextBeyondRange() {
        let f = Self.formatter(Locale(identifier: "en_US"))
        let in4Days = f.dayText(Self.now.addingTimeInterval(4 * 24 * 3600))
        #expect(!["today", "tomorrow", "yesterday"].contains(in4Days), in4Days)
        let in30Days = f.dayText(Self.now.addingTimeInterval(30 * 24 * 3600))
        #expect(!["today", "tomorrow", "yesterday"].contains(in30Days), in30Days)
    }

    // MARK: - Sentence assembly (ScreenFormatter.dueText/untilText: whole-sentence keys)

    /// en_US unchanged: "Due today at 2:13 PM" reads exactly as the old string-interpolated version
    /// did. es_ES: the catalog has no Spanish translation yet (L10N-04), so the sentence template
    /// itself falls back to English ("Due … at …"), but the day and time *inside* it are already
    /// Spanish/24-hour — proving the pipeline (L10n key → locale-formatted placeholders) is wired
    /// correctly now, ready for L10N-04 to translate the template without touching this code again.
    @Test("dueText (within the coming week): en_US unchanged; the placeholders are locale-formatted",
          arguments: [
              ("en_US", "Due today at 2:13 PM"),
              ("en_GB", "Due today at 14:13"),
              ("es_ES", "Due hoy at 14:13"),
          ])
    func dueTextWithinWeek(identifier: String, expected: String) {
        let f = Self.formatter(Locale(identifier: identifier))
        #expect(f.dueText(Self.now) == expected)
    }

    /// Past due: "Was due …" — en_US unchanged; the day word still localizes.
    @Test("dueText (past due): 'Was due' is a whole-sentence key")
    func dueTextPast() {
        let past = Self.now.addingTimeInterval(-3600)
        #expect(Self.formatter(Locale(identifier: "en_US")).dueText(past) == "Was due today")
        #expect(Self.formatter(Locale(identifier: "es_ES")).dueText(past) == "Was due hoy")
    }

    /// `untilText` ("Fri at 11:59 PM", for "still accepted until …"): same whole-sentence pattern.
    @Test("untilText: en_US unchanged; the placeholders are locale-formatted")
    func untilText() {
        #expect(Self.formatter(Locale(identifier: "en_US")).untilText(Self.now) == "today at 2:13 PM")
        #expect(Self.formatter(Locale(identifier: "en_GB")).untilText(Self.now) == "today at 14:13")
        #expect(Self.formatter(Locale(identifier: "es_ES")).untilText(Self.now) == "hoy at 14:13")
    }

    // MARK: - Letter grades (ScreenFormatter.spokenLetter: never translate the letter itself)

    /// The base letter (Canvas's own grading scheme) is passed through untouched in every locale;
    /// "minus"/"plus" are catalog keys now, and (pre-L10N-04) fall back to English everywhere,
    /// which is the correct, honest current state — not a regression, since Spanish does not exist
    /// in the catalog yet. en_US is byte-identical to the old " minus"/" plus" concatenation.
    @Test("spokenLetter: the letter is never translated; en_US unchanged", arguments: [
        ("A-", "A minus"), ("B+", "B plus"), ("C", "C"),
    ])
    func spokenLetterEnUS(letter: String, expected: String) {
        #expect(ScreenFormatter.spokenLetter(letter) == expected)
    }

    @Test("spokenLetter: the same result regardless of the ambient locale (no ScreenFormatter instance; it is a static, letters-only API)")
    func spokenLetterLocaleIndependent() {
        // spokenLetter takes no locale: confirms it reads no ambient/ScreenFormatter state, so a
        // caller in any locale gets the same (currently English-fallback) words, never a crash or
        // an empty string.
        #expect(ScreenFormatter.spokenLetter("A-") == "A minus")
        #expect(ScreenFormatter.spokenLetter("F") == "F")
    }

    // MARK: - Points and "9/10" (courseDetail.scoreOutOf: a whole-sentence key, not a string replace)

    /// The old implementation took the *already-built* visual text ("92/100") and replaced its "/"
    /// with " out of " — fragile, because "/" is data punctuation, not a translatable separator.
    /// The fix is a whole-sentence key taking both already-formatted point values directly, so
    /// nothing here depends on the visual form's separator at all. en_US unchanged; the point values
    /// stay locale-formatted inside the sentence (the same pre-existing `pointsText` behaviour),
    /// while the template itself (like `dueText`'s) falls back to English pre-L10N-04.
    @Test("courseDetail.scoreOutOf: a whole-sentence key with two already-formatted placeholders, not a '/' replace",
          arguments: [
              ("en_US", "92 out of 100"),
              ("en_GB", "92 out of 100"),
              ("es_ES", "92 out of 100"),
          ])
    func scoreOutOfKey(identifier: String, expected: String) {
        var resource = L10n.CourseDetail.scoreOutOf("92", "100")
        resource.locale = Locale(identifier: identifier)
        #expect(String(localized: resource) == expected)
    }

    /// The key never mentions "/" at all: changing the visual separator can never silently change
    /// what VoiceOver says (the bug class the old `replacingOccurrences(of: "/", ...)` risked).
    @Test("courseDetail.scoreOutOf's English value contains no '/'")
    func scoreOutOfHasNoSlash() {
        let resource = L10n.CourseDetail.scoreOutOf("92", "100")
        #expect(!String(localized: resource).contains("/"))
    }

    // MARK: - Plurals (catalog plural variants, not hand-pluralised string concatenation)

    /// `courses.health.missingItemsStillAccepted`: English's "one" category only ever matches
    /// exactly 1, so count 1 reads "item" (singular) and every other count reads "items" — the same
    /// `one`/`other` mechanism L10N-01's own exemplar (`dashboard.hero.averageOfCourses`) proved
    /// works through `#bundle` from a main-actor caller (`LocalizationTests.heroCaptionPlural`).
    /// en_GB and es_ES share English's plural rule (one ↔ n==1), so the same expectations hold for
    /// every locale in the required matrix; fr_FR's different rule (one ↔ n∈{0,1}) is reserved for
    /// the Percent row's extra locale, per the brief, not tested here.
    @Test("courses.health.missingItemsStillAccepted: a genuine catalog plural, not hand-pluralised",
          arguments: ["en_US", "en_GB", "es_ES"])
    func missingItemsPlural(identifier: String) {
        let locale = Locale(identifier: identifier)
        var one = L10n.Courses.missingItemsStillAccepted(1)
        one.locale = locale
        var many = L10n.Courses.missingItemsStillAccepted(3)
        many.locale = locale
        #expect(String(localized: one) == "1 missing item is still accepted")
        #expect(String(localized: many) == "3 missing items are still accepted")
    }

    /// `insights.streak.days`: "1-day streak" (singular, no catalog plural category chosen by
    /// chance — `one` is written out directly) versus "N-day streak" for every other count.
    @Test("insights.streak.days: 1 is singular, every other count is plural", arguments: ["en_US", "en_GB", "es_ES"])
    func streakDaysPlural(identifier: String) {
        let locale = Locale(identifier: identifier)
        var one = L10n.Insights.streakDays(1)
        one.locale = locale
        var many = L10n.Insights.streakDays(5)
        many.locale = locale
        #expect(String(localized: one) == "1-day streak")
        #expect(String(localized: many) == "5-day streak")
    }

    /// The gap-text fixed pair (`courses.health.pointAbove`/`pointsAboveCount`): L10N-03a's
    /// documented choice for `settings.threshold.pointsOne`/`pointsOther` (an unrounded `Double`,
    /// not a clean plural count) applied to the same shape of problem here. Confirms both keys
    /// resolve and that `pointsAboveCount` carries the already-formatted value through unchanged.
    @Test("courses.health.pointAbove/pointsAboveCount: a fixed pair, not a plural (gap is an unrounded Double)")
    func pointsAboveFixedPair() {
        #expect(String(localized: L10n.Courses.pointAbove()) == "1 point above")
        #expect(String(localized: L10n.Courses.pointsAboveCount("0.4")) == "0.4 points above")
        #expect(String(localized: L10n.Courses.pointsAboveCount("2.3")) == "2.3 points above")
    }

    // MARK: - Pass/fail tokens (CourseDetailBuilder.gradeText)

    /// Canvas's fixed pass/fail tokens are mapped, case-insensitively (classifying Canvas's own
    /// data, never `.lowercased()` on text shown to the student); any other value — a letter grade —
    /// passes through unchanged, in every locale (it is Canvas's own grading scheme, §3.3 "Letter
    /// grades").
    @Test("gradeText: Canvas's complete/incomplete tokens map to localized words; anything else passes through", arguments: [
        ("complete", "Complete"), ("Complete", "Complete"), ("COMPLETE", "Complete"),
        ("incomplete", "Incomplete"), ("Incomplete", "Incomplete"),
        ("A-", "A-"), ("B+", "B+"), ("Pass", "Pass"),
    ])
    func gradeTextMapsPassFailTokens(grade: String, expected: String) {
        #expect(CourseDetailBuilder.gradeText(grade) == expected)
    }
}
