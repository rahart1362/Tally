import CoreGraphics
import Foundation
import PDFKit
import SwiftUI
import Testing
import TallyDomain
import TallyStore
import UIKit
import WidgetKit
@testable import Tally
@testable import TallyGlance

/// M3-D (UX-WP-29, UX-WP-38): every widget surface in every rendering mode, rendered in the test
/// host with `ImageRenderer`. The PNGs are attached to the test run (CI's screenshot export uploads
/// them), so a person can look at each one; the assertions do not compare against stored reference
/// images, which would differ between the iOS 26 runtimes CI runs on.
///
/// What the tests prove: each surface draws in each mode; the Standing widget's locked rendering
/// (`.privacy` redaction, as WidgetKit applies it while the iPhone is locked) does not depend on any
/// grade; the Lock Screen accessories never show a grade, by their pixels and by their rendered
/// text (drawn into a PDF and read back); in the accented mode, where the system keeps only each
/// pixel's opacity, a change of meaning still changes the picture; and "Hide course names" leaves
/// no title or course code on the Lock Screen.
@MainActor
@Suite("Widgets M3-D: every family and rendering mode, the locked preview, no grades on the Lock Screen")
struct WidgetFamilyRenderTests {
    /// The widget surfaces (kind and family) at their sizes on a 6.7-inch iPhone, in points
    /// (Apple's Human Interface Guidelines, "Widgets": small 170 × 170, medium 364 × 170, large
    /// 364 × 382; circular 76 × 76, rectangular 172 × 76, inline 257 × 26).
    enum Surface: String, CaseIterable, Sendable {
        case nextUpSmall = "next-up-small"
        case standingSmall = "standing-small"
        case standingMedium = "standing-medium"
        case dueSoonMedium = "due-soon-medium"
        case weekAheadLarge = "week-ahead-large"
        case dueTodayCircular = "due-today-circular"
        case nextItemRectangular = "next-item-rectangular"
        case nextDueInline = "next-due-inline"

        var size: CGSize {
            switch self {
            case .nextUpSmall, .standingSmall: CGSize(width: 170, height: 170)
            case .standingMedium, .dueSoonMedium: CGSize(width: 364, height: 170)
            case .weekAheadLarge: CGSize(width: 364, height: 382)
            case .dueTodayCircular: CGSize(width: 76, height: 76)
            case .nextItemRectangular: CGSize(width: 172, height: 76)
            case .nextDueInline: CGSize(width: 257, height: 26)
            }
        }

        var isLockScreen: Bool {
            switch self {
            case .dueTodayCircular, .nextItemRectangular, .nextDueInline: true
            default: false
            }
        }

        @MainActor
        func view(_ entry: GlanceEntry) -> AnyView {
            switch self {
            case .nextUpSmall: AnyView(NextUpWidgetView(entry: entry))
            case .standingSmall: AnyView(StandingWidgetView(entry: entry, family: .systemSmall))
            case .standingMedium: AnyView(StandingWidgetView(entry: entry, family: .systemMedium))
            case .dueSoonMedium: AnyView(DueSoonWidgetView(entry: entry))
            case .weekAheadLarge: AnyView(WeekAheadWidgetView(entry: entry))
            case .dueTodayCircular: AnyView(DueTodayAccessoryView(entry: entry))
            case .nextItemRectangular: AnyView(NextItemAccessoryView(entry: entry))
            case .nextDueInline: AnyView(NextDueInlineView(entry: entry))
            }
        }
    }

    /// WidgetKit's rendering modes: full colour (the Home Screen), accented (a tinted or clear Home
    /// Screen, and StandBy), vibrant (the Lock Screen).
    enum Mode: String, CaseIterable, Sendable {
        case fullColor = "full-color"
        case accented
        case vibrant

        var renderingMode: WidgetRenderingMode {
            switch self {
            case .fullColor: .fullColor
            case .accented: .accented
            case .vibrant: .vibrant
            }
        }
    }

    private static let calendar = Calendar.autoupdatingCurrent
    /// A fixed moment: noon, 2026-10-06, in this simulator's time zone.
    private static let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 12)) ?? .distantPast

    private static func at(days: Int, hour: Int) -> Date {
        let day = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(byAdding: .hour, value: hour, to: day) ?? now
    }

    /// A realistic glance: a lab report later today, more through the week (a busy Thursday-like
    /// day), one overdue item, and five courses whose grades are A, C, not in Canvas, not graded in
    /// Canvas and not posted yet (`band` sets the first course's band and the overall band).
    private static func glance(band: GradeBand? = .aRange, overdue: Int = 1, busyDay: Bool = true,
                               title: String = "Lab Report 4") -> GlanceProjection {
        var items = [GlanceDueItem(id: "assignment:9101", courseShortCode: "BIO 101", title: title, dueAt: at(days: 0, hour: 18),
                                   missing: false, late: false, excused: false, submitted: false)]
        let busy = busyDay ? 3 : 1
        for index in 0..<busy {
            items.append(GlanceDueItem(id: "quiz:920\(index)", courseShortCode: "MATH 122", title: "Problem Set \(index + 6)",
                                       dueAt: at(days: 2, hour: 9 + index), missing: false, late: false, excused: false,
                                       submitted: false))
        }
        for index in 0..<overdue {
            items.append(GlanceDueItem(id: "planner_note:930\(index)", courseShortCode: "HIST 210", title: "Reading \(index + 1)",
                                       dueAt: at(days: -1, hour: 9 + index), missing: true, late: false, excused: false,
                                       submitted: false))
        }
        let courses = [
            GlanceCourse(id: CanvasID("1"), shortCode: "BIO 101", currentGrade: band, gradeStatus: band == nil ? .notYetPosted : .averaged),
            GlanceCourse(id: CanvasID("2"), shortCode: "MATH 122", currentGrade: band == nil ? nil : .cRange, gradeStatus: .averaged),
            GlanceCourse(id: CanvasID("3"), shortCode: "ART 1", currentGrade: nil, gradeStatus: .keptOutsideCanvas),
            GlanceCourse(id: CanvasID("4"), shortCode: "ADVISORY", currentGrade: nil, gradeStatus: .notGradedInCanvas),
            GlanceCourse(id: CanvasID("5"), shortCode: "HIST 210", currentGrade: nil, gradeStatus: .notYetPosted),
        ]
        return GlanceProjection(generation: 1, asOf: now.addingTimeInterval(-600),
                                gradeSummary: band.map(GlanceGradeSummary.band) ?? .notOptedIn, courses: courses, dueSoon: items,
                                entitledUntil: GlanceStoreFixture.entitledUntil) // M3-B2: enforcement is on
    }

    private static func entry(_ glance: GlanceProjection) -> GlanceEntry {
        GlanceEntry(GlanceTimelinePlanner.plan(for: .loaded(glance), now: now, calendar: calendar).current)
    }

    private static func renderer(_ surface: Surface, _ entry: GlanceEntry, mode: Mode = .fullColor,
                                 redacted: Bool = false) -> ImageRenderer<some View> {
        let view = surface.view(entry)
            .environment(\.widgetRenderingMode, mode.renderingMode)
            .frame(width: surface.size.width, height: surface.size.height)
        let renderer = ImageRenderer(content: Group { if redacted { view.redacted(reason: .privacy) } else { view } })
        renderer.scale = 2
        return renderer
    }

    private static func png(_ surface: Surface, _ entry: GlanceEntry, mode: Mode = .fullColor, redacted: Bool = false) -> Data? {
        renderer(surface, entry, mode: mode, redacted: redacted).uiImage?.pngData()
    }

    /// Each pixel's opacity: all the system keeps of a widget in the accented mode.
    private static func alpha(_ surface: Surface, _ entry: GlanceEntry, mode: Mode) -> [UInt8] {
        guard let image = renderer(surface, entry, mode: mode).cgImage,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return [] }
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        return pixels.withUnsafeMutableBytes { buffer -> [UInt8] in
            guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return stride(from: 3, to: buffer.count, by: 4).map { buffer[$0] }
        }
    }

    /// The text the surface draws: rendered into a one-page PDF and read back with PDFKit, spaces
    /// and line breaks removed (PDF text extraction places them by position).
    private static func renderedText(_ surface: Surface, _ entry: GlanceEntry, mode: Mode = .fullColor,
                                     redacted: Bool = false) -> String {
        let data = NSMutableData()
        renderer(surface, entry, mode: mode, redacted: redacted).render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let consumer = CGDataConsumer(data: data as CFMutableData),
                  let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
            context.closePDF()
        }
        return (PDFDocument(data: data as Data)?.string ?? "").filter { !$0.isWhitespace }
    }

    /// Every grade word a widget could draw (en_US, the simulator's locale), spaces removed.
    private static let gradeTokens = GradeBand.allCases.map { GlanceText.bandLabel($0, locale: Locale(identifier: "en_US")) }
        .map { $0.filter { !$0.isWhitespace } } + ["%"]

    // MARK: Snapshots

    @Test("Snapshot: every surface draws in every rendering mode (attached as a PNG)",
          arguments: Surface.allCases, Mode.allCases)
    func snapshot(surface: Surface, mode: Mode) throws {
        let entry = Self.entry(Self.glance())
        let png = try #require(Self.png(surface, entry, mode: mode), "\(surface.rawValue) did not render in \(mode.rawValue)")
        Attachment.record(png, named: "m3d-\(surface.rawValue)-\(mode.rawValue).png")
        let opaque = Self.alpha(surface, entry, mode: mode).filter { $0 > 0 }.count
        #expect(opaque > 0, "\(surface.rawValue) in \(mode.rawValue) drew nothing")
    }

    // MARK: The "Mark Done" button (M3-D2)

    @Test("Snapshot: a Due soon row with the Mark Done button draws something extra at its trailing edge")
    func dueSoonRowWithMarkDoneButton() throws {
        let entry = Self.entry(Self.glance())
        let plain = try #require(Self.png(.dueSoonMedium, entry))
        let view = DueSoonWidgetView(entry: entry) { itemID, accessibilityLabel in
            AnyView(MarkDoneButton(itemID: itemID, accessibilityLabel: accessibilityLabel))
        }
        .environment(\.widgetRenderingMode, Mode.fullColor.renderingMode)
        .frame(width: Surface.dueSoonMedium.size.width, height: Surface.dueSoonMedium.size.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let withButton = try #require(renderer.uiImage?.pngData())
        Attachment.record(withButton, named: "m3d2-due-soon-mark-done.png")
        #expect(withButton != plain, "the Mark Done button drew nothing extra on the Due soon row")
    }

    @Test("The Mark Done button is offered only on assignment rows, never on a quiz or a planner note")
    func markDoneButtonOnlyOnAssignments() throws {
        final class Offered { var itemIDs: [String] = [] }
        let offered = Offered()
        let view = DueSoonWidgetView(entry: Self.entry(Self.glance())) { itemID, accessibilityLabel in
            offered.itemIDs.append(itemID)
            return AnyView(MarkDoneButton(itemID: itemID, accessibilityLabel: accessibilityLabel))
        }
        .environment(\.widgetRenderingMode, Mode.fullColor.renderingMode)
        .frame(width: Surface.dueSoonMedium.size.width, height: Surface.dueSoonMedium.size.height)
        _ = try #require(ImageRenderer(content: view).uiImage)
        #expect(offered.itemIDs.contains("assignment:9101"), "the assignment row got no Mark Done button")
        #expect(offered.itemIDs.allSatisfy { GlancePlannerID.assignmentID($0) != nil },
                "a non-assignment row got a Mark Done button: \(offered.itemIDs)")
    }

    @Test("Every state renders on every surface: placeholder, each message (the subscription lock too), a summary",
          arguments: Surface.allCases)
    func everyState(surface: Surface) {
        var contents: [GlanceContent] = [.placeholder]
        contents += GlanceMessage.allCases.map(GlanceContent.message)
        contents.append(Self.entry(Self.glance()).content)
        contents.append(Self.entry(Self.glance(band: nil, overdue: 0, busyDay: false)).content)
        for content in contents {
            #expect(Self.png(surface, GlanceEntry(date: Self.now, content: content)) != nil, "\(surface.rawValue): \(content)")
        }
        let locked = Self.renderedText(surface, GlanceEntry(date: Self.now, content: .message(.subscriptionRequired)))
        #expect(!locked.contains("LabReport4"), "\(surface.rawValue) showed glance data while access is locked")
    }

    // MARK: The locked preview (PMO R10)

    @Test("Locked preview: the Standing widget's pixels do not depend on any grade, small or medium",
          arguments: [Surface.standingSmall, .standingMedium])
    func standingRedactedWhenLocked(surface: Surface) throws {
        let gradeA = Self.entry(Self.glance(band: .aRange))
        let gradeF = Self.entry(Self.glance(band: .fRange))
        let lockedA = try #require(Self.png(surface, gradeA, redacted: true))
        let lockedF = try #require(Self.png(surface, gradeF, redacted: true))
        #expect(lockedA == lockedF, "\(surface.rawValue): the locked rendering depends on the grade")
        #expect(Self.png(surface, gradeA) != Self.png(surface, gradeF), "\(surface.rawValue): no grade shown even when unlocked")
        Attachment.record(lockedA, named: "m3d-\(surface.rawValue)-locked.png")

        let text = Self.renderedText(surface, gradeA, redacted: true)
        #expect(text.contains("Hiddenwhilelocked"), "\(surface.rawValue) locked text: \(text)")
        for token in Self.gradeTokens where token != "%" {
            #expect(!text.contains(token), "\(surface.rawValue) shows '\(token)' while locked")
        }
    }

    // MARK: The Lock Screen never shows a grade (PMO R10, UX-WP-29)

    @Test("Lock Screen accessories: the same pixels with or without grades, in every mode",
          arguments: [Surface.dueTodayCircular, .nextItemRectangular, .nextDueInline], Mode.allCases)
    func accessoriesIgnoreGrades(surface: Surface, mode: Mode) {
        let withGrades = Self.entry(Self.glance(band: .aRange))
        let otherGrades = Self.entry(Self.glance(band: .fRange))
        let noGrades = Self.entry(Self.glance(band: nil))
        let rendered = [withGrades, otherGrades, noGrades].map { Self.png(surface, $0, mode: mode) }
        #expect(rendered[0] != nil)
        #expect(Set(rendered).count == 1, "\(surface.rawValue) in \(mode.rawValue): the pixels depend on the grades")
    }

    @Test("Lock Screen accessories: no grade word or percentage in the rendered text, which does show the item",
          arguments: [Surface.nextItemRectangular, .nextDueInline])
    func accessoryTextHasNoGrades(surface: Surface) {
        let text = Self.renderedText(surface, Self.entry(Self.glance(band: .aRange)), mode: .vibrant)
        #expect(text.contains("LabReport4"), "\(surface.rawValue): the rendered text was not read back: '\(text)'")
        for token in Self.gradeTokens {
            #expect(!text.contains(token), "\(surface.rawValue) shows '\(token)': \(text)")
        }
    }

    @Test("Due today gauge: the rendered text is the open count and 'today', never a grade")
    func gaugeTextHasNoGrades() {
        let text = Self.renderedText(.dueTodayCircular, Self.entry(Self.glance(band: .aRange)), mode: .vibrant)
        #expect(text.contains("today"), "the gauge's text was not read back: '\(text)'")
        for token in Self.gradeTokens {
            #expect(!text.contains(token), "the gauge shows '\(token)': \(text)")
        }
    }

    // MARK: Accented and clear (UX-WP-38): meaning survives when only opacity is kept

    @Test("Accented: a change of meaning still changes the opacity mask (words carry it, never colour alone)",
          arguments: [Surface.nextUpSmall, .dueSoonMedium, .weekAheadLarge, .standingSmall, .standingMedium])
    func accentedKeepsMeaning(surface: Surface) {
        let calm = Self.entry(Self.glance(band: .aRange, overdue: 0, busyDay: false))
        let urgent = Self.entry(Self.glance(band: .cRange, overdue: 2, busyDay: true))
        let calmMask = Self.alpha(surface, calm, mode: .accented)
        #expect(!calmMask.isEmpty)
        #expect(calmMask != Self.alpha(surface, urgent, mode: .accented),
                "\(surface.rawValue): overdue work, a busy day or another grade looks the same in the accented mode")
    }

    // MARK: Hide course names (PMO R10)

    @Test("Hide course names: no title or course code on the Lock Screen, a generic word instead",
          arguments: [Surface.nextItemRectangular, .nextDueInline])
    func hideCourseNames(surface: Surface) throws {
        guard case .summary(let summary) = Self.entry(Self.glance()).content else {
            Issue.record("no summary")
            return
        }
        let hidden = GlanceSummary(
            nextUp: summary.nextUp, laterCount: summary.laterCount, overdueCount: summary.overdueCount, grades: summary.grades,
            asOf: summary.asOf, isStale: summary.isStale, asOfIsBeforeToday: summary.asOfIsBeforeToday,
            upcoming: summary.upcoming, today: summary.today, week: summary.week, hidesCourseNames: true)
        let text = Self.renderedText(surface, GlanceEntry(date: Self.now, content: .summary(hidden)), mode: .vibrant)
        #expect(text.contains("Assignment"), "\(surface.rawValue): '\(text)'")
        #expect(!text.contains("LabReport4"), "\(surface.rawValue) shows the title: '\(text)'")
        #expect(!text.contains("BIO101"), "\(surface.rawValue) shows the course code: '\(text)'")
    }
}
