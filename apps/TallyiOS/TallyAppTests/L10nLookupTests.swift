import Foundation
import Testing
import TallyStrings

/// `L10n.string` (PR #27's sample-entry budget) returns exactly what `String(localized:)` returns,
/// byte for byte: the first call (a catalog lookup) and every later one (from the cache), with
/// arguments that would trip a find-and-replace.
@Suite("L10n.string: the same text as String(localized:), looked up once")
struct L10nLookupTests {
    /// Canvas text can hold anything: a percent sign, a format specifier, a placeholder's own code
    /// point, combining marks, emoji, right-to-left text, a line break.
    static let arguments = [
        "", "Problem Set 7", "tomorrow", "11:59 PM", "100%", "%@", "%1$@", "\u{E000}", "\u{E001}x\u{E000}",
        "\u{E002}", "e\u{301}", "\u{301}leading mark", "👩‍👩‍👧", "שלום", "a\u{200F}b", "line\nbreak",
    ]

    private static func bytes(_ text: String) -> [UInt8] { Array(text.utf8) }

    @Test("keys with no argument, twice (the second from the cache)")
    func noArgument() {
        let keys: [() -> LocalizedStringResource] = [
            L10n.ToDo.statusMissing, L10n.ToDo.statusNotSubmitted, L10n.ToDo.statusSubmitted, L10n.ToDo.statusGraded,
            L10n.ToDo.statusExcused, L10n.ToDo.statusLate, L10n.ToDo.priorityWord, L10n.Courses.healthOnTrack,
            L10n.Courses.justAbove, L10n.Courses.pointAbove, L10n.CourseDetail.sectionUpcoming,
            L10n.CourseDetail.sectionGraded, L10n.Calendar.allDay,
        ]
        for key in keys {
            let direct = String(localized: key())
            #expect(Self.bytes(L10n.string(key)) == Self.bytes(direct))
            #expect(Self.bytes(L10n.string(key)) == Self.bytes(direct), "cached: \(direct)")
        }
    }

    @Test("keys with one String argument")
    func oneArgument() {
        let keys: [(String) -> LocalizedStringResource] = [
            L10n.Courses.wasDue, L10n.Courses.dueDay, L10n.Courses.letterMinus, L10n.CourseDetail.postedOn,
            L10n.ToDo.stillAcceptedUntil, L10n.Insights.spokenPercent, L10n.Calendar.due,
            L10n.Grades.infoButton(courseCode:),
        ]
        for key in keys {
            for first in Self.arguments {
                let direct = String(localized: key(first))
                #expect(Self.bytes(L10n.string(key, first)) == Self.bytes(direct), "\(direct.debugDescription)")
            }
        }
    }

    @Test("keys with two String arguments, in both orders of every pair")
    func twoArguments() {
        let keys: [(String, String) -> LocalizedStringResource] = [
            L10n.Courses.dueAtTime, L10n.Courses.atTime, L10n.CourseDetail.scoreOutOf, L10n.Calendar.timeRange,
        ]
        for key in keys {
            for first in Self.arguments {
                for second in Self.arguments {
                    let direct = String(localized: key(first, second))
                    #expect(Self.bytes(L10n.string(key, first, second)) == Self.bytes(direct), "\(direct.debugDescription)")
                }
            }
        }
    }

    @Test("keys with three String arguments")
    func threeArguments() {
        let keys: [(String, String, String) -> LocalizedStringResource] = [
            L10n.CourseDetail.gradedItemAccessibility, L10n.Insights.trendSummaryUp,
        ]
        for key in keys {
            for first in Self.arguments {
                for second in Self.arguments.prefix(6) {
                    for third in Self.arguments {
                        let direct = String(localized: key(first, second, third))
                        #expect(Self.bytes(L10n.string(key, first, second, third)) == Self.bytes(direct),
                                "\(direct.debugDescription)")
                    }
                }
            }
        }
    }

    @Test("plural keys: every cached number, and numbers outside the cached range")
    func plurals() {
        let keys: [(Int) -> LocalizedStringResource] = [
            L10n.Calendar.itemCount, L10n.Courses.missingItemsStillAccepted, L10n.Insights.streakDays,
        ]
        let outside = [L10n.cachedCounts.lowerBound - 1, L10n.cachedCounts.upperBound + 1, 1_000_000]
        for key in keys {
            for count in Array(0...30) + [L10n.cachedCounts.upperBound] + outside {
                let direct = String(localized: key(count))
                #expect(L10n.string(key, count) == direct)
                #expect(L10n.string(key, count) == direct, "cached: \(direct)")
            }
        }
    }
}
