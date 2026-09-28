import SwiftUI
import Testing
import TallyDomain
@testable import TallyGlance

/// Plan 06 step 11 and PMO R10 through the widgets' own views, rendered with `ImageRenderer` in
/// the test host: the grade shows only on the opt-in Standing widget, and under the privacy
/// redaction WidgetKit applies while the iPhone is locked, no pixel depends on the grade.
@MainActor
@Suite("Widget glance: views")
struct WidgetGlanceRenderTests {
    /// A small widget's size on a 6.1-inch iPhone, in points.
    private static let widgetSize = CGSize(width: 170, height: 170)
    private static let asOf = Date(timeIntervalSince1970: 1_790_600_400)

    private static func summary(standing: GradeBand?, nextUp: GlanceSummary.Item? = nil) -> GlanceSummary {
        GlanceSummary(nextUp: nextUp, laterCount: 2, overdueCount: 1, standing: standing, asOf: asOf,
                      isStale: false, asOfIsBeforeToday: false)
    }

    private static let item = GlanceSummary.Item(title: "Lab report 4", courseCode: "BIO 101",
                                                 dueAt: asOf.addingTimeInterval(3_600), day: .today)

    private static func png(_ view: some View) -> Data? {
        let renderer = ImageRenderer(content: view.frame(width: widgetSize.width, height: widgetSize.height))
        renderer.scale = 2
        return renderer.uiImage?.pngData()
    }

    private static func entry(_ content: GlanceContent) -> GlanceEntry {
        GlanceEntry(date: asOf, content: content)
    }

    @Test("under the privacy redaction, the Standing widget renders the same pixels whatever the grade")
    func standingIsRedactedWhenLocked() throws {
        let aRange = Self.entry(.summary(Self.summary(standing: .aRange)))
        let passing = Self.entry(.summary(Self.summary(standing: .passing)))

        let lockedA = try #require(Self.png(StandingWidgetView(entry: aRange).redacted(reason: .privacy)))
        let lockedPassing = try #require(Self.png(StandingWidgetView(entry: passing).redacted(reason: .privacy)))
        let unlockedA = try #require(Self.png(StandingWidgetView(entry: aRange)))
        let unlockedPassing = try #require(Self.png(StandingWidgetView(entry: passing)))

        #expect(lockedA == lockedPassing, "a locked Standing widget's pixels depend on the grade")
        #expect(unlockedA != unlockedPassing, "the unlocked Standing widget does not show the grade at all")
    }

    @Test("the grade badge itself: identical when redacted for privacy, different when not")
    func badgeIsRedactedWhenLocked() throws {
        var locked: Set<Data> = []
        var unlocked: Set<Data> = []
        for band in GradeBand.allCases {
            locked.insert(try #require(Self.png(GradeBandBadge(band: band).redacted(reason: .privacy))))
            unlocked.insert(try #require(Self.png(GradeBandBadge(band: band))))
        }

        #expect(locked.count == 1, "\(locked.count) different locked renderings for \(GradeBand.allCases.count) bands")
        #expect(unlocked.count == GradeBand.allCases.count)
    }

    @Test("the Next up widget never shows a grade: its pixels do not depend on the glance's grades")
    func nextUpNeverShowsAGrade() throws {
        let withGrades = Self.entry(.summary(Self.summary(standing: .aRange, nextUp: Self.item)))
        let otherGrades = Self.entry(.summary(Self.summary(standing: .fRange, nextUp: Self.item)))
        let withoutGrades = Self.entry(.summary(Self.summary(standing: nil, nextUp: Self.item)))

        let a = try #require(Self.png(NextUpWidgetView(entry: withGrades)))
        let f = try #require(Self.png(NextUpWidgetView(entry: otherGrades)))
        let none = try #require(Self.png(NextUpWidgetView(entry: withoutGrades)))
        #expect(a == f)
        #expect(a == none)
    }

    @Test("every state renders: placeholder, each message, a summary with and without a next item")
    func everyStateRenders() {
        let contents: [GlanceContent] = [
            .placeholder,
            .message(.signedOut), .message(.waitingForFirstSync), .message(.locked), .message(.unavailable),
            .summary(Self.summary(standing: nil, nextUp: Self.item)),
            .summary(Self.summary(standing: nil)),
            .summary(GlanceSummary(nextUp: Self.item, laterCount: 0, overdueCount: 0, standing: .bRange,
                                   asOf: Self.asOf, isStale: true, asOfIsBeforeToday: true)),
        ]
        for content in contents {
            #expect(Self.png(NextUpWidgetView(entry: Self.entry(content))) != nil, "Next up: \(content)")
            #expect(Self.png(StandingWidgetView(entry: Self.entry(content))) != nil, "Standing: \(content)")
        }
    }

    @Test("copy: one label per grade band, counts, and a message for every read failure")
    func copy() {
        let labels = GradeBand.allCases.map(GlanceText.bandLabel)
        #expect(Set(labels).count == GradeBand.allCases.count)
        #expect(labels.allSatisfy { !$0.isEmpty })
        #expect(GlanceText.counts(later: 0, overdue: 0) == nil)
        #expect(GlanceText.counts(later: 2, overdue: 0) == "+2 more")
        #expect(GlanceText.counts(later: 0, overdue: 1) == "1 overdue")
        #expect(GlanceText.counts(later: 2, overdue: 1) == "+2 more · 1 overdue")
        for message in [GlanceMessage.signedOut, .waitingForFirstSync, .locked, .unavailable] {
            #expect(!GlanceText.message(message).isEmpty)
        }
    }
}
