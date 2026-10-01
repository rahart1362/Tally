import Foundation
import SwiftUI
import Testing
import TallyDomain
import TallyStrings
import TallyTestSupport
import UIKit
@testable import TallyFeatures

/// Plan 08 XG-03, §4.5 and §4.4 rows 1 (G-5's hero rows) and 17, in the app: the hero's caption
/// rows, the "not included" list built from the Home course rows, the info bubble's words and
/// Tell My School's message, how the bubble is presented, and what VoiceOver gets from the views
/// themselves. Synthetic `external-grades` persona only. No UI test: the owner's lean-testing
/// guidance keeps one smoke test per screen, and those run on the flagship, which these screens
/// leave unchanged.
@Suite("XG-03 G-5 and row 17: the Dashboard hero's rows")
struct GradeNotInCanvasHeroTests {
    static func hero(_ snapshot: CanvasSnapshot) -> DashboardProjection.Hero {
        DashboardBuilder.hero(courses: snapshot.courses,
                              gradeAvailability: GradeAvailabilityIndex(snapshot: snapshot, overrides: [:], now: ExternalGrades.anchor))
    }

    @Test("Which caption row: 'N courses not included', 'Grades aren't in Canvas', or none (the flagship)")
    func captionRow() async throws {
        let snapshot = try await ExternalGrades.snapshot()
        #expect(HeroCaption(Self.hero(snapshot)) == .notIncluded(5))
        #expect(HeroCaption(Self.hero(ExternalGrades.trimmed(snapshot, keeping: ExternalGrades.noneInCanvas))) == .notInCanvas)
        // Nothing averaged, but nothing kept outside Canvas either: "No grades to show yet", no row.
        #expect(HeroCaption(Self.hero(ExternalGrades.trimmed(snapshot, keeping: ["ART-1", "ADVISORY"]))) == .noRow)
        #expect(HeroCaption(Self.hero(ExternalGrades.trimmed(snapshot, keeping: ["SPAN-2", "ENG-10"]))) == .notIncluded(1))
        #expect(HeroCaption(Self.hero(try await ExternalGrades.snapshot("flagship"))) == .noRow)
        #expect(String(localized: L10n.Dashboard.coursesNotIncluded(1)) == "1 course not included")
        #expect(String(localized: L10n.Dashboard.coursesNotIncluded(5)) == "5 courses not included")
    }

    @Test("The bubble lists exactly the courses the hero leaves out, each with its reason (the Home course rows)",
          arguments: ["external-grades", "grading-periods", "flagship"])
    func exclusionList(persona: String) async throws {
        let snapshot = try await ExternalGrades.snapshot(persona)
        let projector = HomeProjector(calendar: Calendar(identifier: .gregorian), locale: Locale(identifier: "en_US"))
        await projector.install(HomeUpdate(generation: 1, snapshot: snapshot, digest: nil, digestAsOf: nil, freshness: .noCache))
        let projection = try #require(await projector.project(now: ExternalGrades.anchor))
        let hero = projection.dashboard.hero
        var listed: [CourseGradeStatus: Int] = [:]
        var reasons: [String: String] = [:]
        for row in projection.courses {
            let status = HeroExclusion.status(of: row)
            guard let reason = HeroExclusion.reason(status) else {
                #expect(status == .averaged)
                continue
            }
            listed[status, default: 0] += 1
            reasons[row.code] = String(localized: reason)
        }
        #expect(listed == hero.exclusions, "\(persona)")
        #expect(listed.values.reduce(0, +) == hero.courseCount - hero.averagedCount)
        switch persona {
        case "external-grades":
            #expect(reasons == ["ENG-10": "Not in Canvas", "ALG2": "Not in Canvas", "BIO-H": "Not in Canvas",
                                "ART-1": "No grade yet", "ADVISORY": "Not graded in Canvas"])
        case "grading-periods":
            #expect(reasons == ["CHEM-H": "Hidden by your instructor"])
        default:
            #expect(reasons.isEmpty)
        }
    }

    @Test("Every reason the hero can give has its words", arguments: CourseGradeStatus.allCases)
    func everyReason(status: CourseGradeStatus) {
        let row = HomeProjection.CourseRow(
            id: "1", code: "SYN-1", name: "Synthetic", percent: status == .averaged ? 90 : nil, letterGrade: nil,
            gradeAvailability: {
                switch status {
                case .averaged, .noPercentage: .available
                case .lettersOnly: .lettersOnly
                case .hiddenByInstructor: .hiddenByInstructor
                case .notYetPosted: .notYetPosted
                case .notGradedInCanvas: .notGradedInCanvas
                case .keptOutsideCanvas: .keptOutsideCanvas(.init(pastDueItems: 5, submittedOrOfflineItems: 3))
                }
            }())
        #expect(HeroExclusion.status(of: row) == status)
        let expected: [CourseGradeStatus: String] = [
            .noPercentage: "No percentage in Canvas", .lettersOnly: "Letter grades only",
            .hiddenByInstructor: "Hidden by your instructor", .notYetPosted: "No grade yet",
            .notGradedInCanvas: "Not graded in Canvas", .keptOutsideCanvas: "Not in Canvas",
        ]
        #expect(HeroExclusion.reason(status).map { String(localized: $0) } == expected[status])
    }
}

@Suite("XG-03 §4.5: the bubble's words and Tell My School")
struct GradeNotInCanvasBubbleTests {
    @Test("G-4's title, bodies, action and the advisory line, from the String Catalog")
    func copy() {
        #expect(String(localized: L10n.Grades.infoTitle()) == "Grades aren't in Canvas")
        #expect(String(localized: GradeInfoText.body(.course)) == "Your school doesn't appear to enter grades for this "
                + "course into Canvas, so Tally can't show them. Your assignments, due dates and reminders still work. "
                + "Check your school's grade portal for this grade.")
        #expect(String(localized: GradeInfoText.body(.school)) == "Your school doesn't appear to enter your grades "
                + "directly into Canvas. Tally can show only grades that are posted in Canvas. Your assignments, due "
                + "dates and reminders still work. If you'd like to see your grades in Tally, you can let your school know.")
        #expect(String(localized: L10n.Grades.tellMySchool()) == "Tell My School")
        #expect(String(localized: L10n.Dashboard.heroNotInCanvas()) == "Grades aren't in Canvas")
        #expect(String(localized: L10n.Insights.trendNotInCanvas()) == "Trends appear when grades are posted in Canvas.")
    }

    @Test("Tell My School's message: the student's voice and the school's name, no link and no 'free'",
          arguments: ["Northfield High School", "  Lakeside Academy  "])
    func shareTextWithSchool(school: String) {
        let text = GradeInfoText.shareText(school: school)
        let name = school.trimmingCharacters(in: .whitespaces)
        #expect(text == "Hello, I'm a student at \(name). I use Canvas to keep track of my assignments, but my grades "
                + "don't appear there. Would the school consider entering grades in Canvas too? I could then see my grades "
                + "next to my work, in Canvas and in apps I use with it, like Tally. Thank you.")
        Self.expectNoLinkAndNoPrice(text)
    }

    @Test("Without a school name (sample data): 'your school', still no link and no 'free'", arguments: [nil, "", "   "])
    func shareTextWithoutSchool(school: String?) {
        let text = GradeInfoText.shareText(school: school)
        #expect(text.hasPrefix("Hello, I'm a student at your school. I use Canvas"))
        #expect(!text.contains("%@") && !text.contains("  "))
        Self.expectNoLinkAndNoPrice(text)
    }

    static func expectNoLinkAndNoPrice(_ text: String) {
        let lower = text.lowercased()
        for link in ["http", "://", "www.", ".com", ".dev", ".org", ".edu", "tally-app"] {
            #expect(!lower.contains(link), "a link in: \(text)")
        }
        let words = lower.split { !$0.isLetter }
        #expect(!words.contains("free"), "a price claim in: \(text)")
        #expect(!text.contains("$"))
    }
}

@Suite("XG-03 §4.5 accessibility: presentation, tap target, and what VoiceOver gets", .serialized)
@MainActor
struct GradeNotInCanvasViewTests {
    @Test("A11Y-02: a popover below the accessibility sizes, a sheet at every one of them")
    func presentation() {
        for size in DynamicTypeSize.allCases {
            #expect(GradeInfoPresentation.usesSheet(at: size) == size.isAccessibilitySize, "\(size)")
        }
        #expect(!GradeInfoPresentation.usesSheet(at: .xxxLarge))
        #expect(GradeInfoPresentation.usesSheet(at: .accessibility1))
        #expect(CourseHealth.gradeNotInCanvas.tone == .neutral)
    }

    @Test("A11Y-04: the ⓘ button is at least 44 × 44 pt at the smallest and the default text size",
          arguments: [DynamicTypeSize.xSmall, .large])
    func tapTarget(size: DynamicTypeSize) {
        let host = UIHostingController(rootView:
            GradeInfoButton(label: Text(verbatim: "About grades for ENG-10"), isPresented: .constant(false)) { EmptyView() }
                .environment(\.dynamicTypeSize, size))
        let fitted = host.sizeThatFits(in: CGSize(width: 1_000, height: 1_000))
        #expect(fitted.width >= 44 && fitted.height >= 44, "\(fitted)")
        #expect(GradeInfoPresentation.minimumTapTarget >= 44)
    }

    // MARK: - The accessibility tree of the real views (`AccessibilityTree`)

    @Test("The card: 'Grade not in Canvas' (never a dash), and a labelled ⓘ of at least 44 pt",
          .enabled(if: !TestRuntime.sanitized))
    func cardTree() async throws {
        let cards = CourseCardBuilder.cards(from: try await ExternalGrades.snapshot(), formatter: ExternalGrades.formatter())
        let english = try #require(cards.first { $0.code == "ENG-10" })
        let elements = try await AccessibilityTree.elements(of: CourseCardView(card: english).frame(width: 360))
        #expect(elements.contains { $0.label == "Grade not in Canvas" }, "\(elements)")
        #expect(!elements.contains { $0.label.contains("\u{2014}") || $0.label.lowercased().contains("dash") }, "\(elements)")
        let info = try #require(elements.first { $0.label == "About grades for ENG-10" }, "\(elements)")
        #expect(info.traits.contains(.button))
        #expect(info.frame.width >= 44 && info.frame.height >= 44, "\(info.frame)")

        let advisory = try #require(cards.first { $0.code == "ADVISORY" })
        let advisoryElements = try await AccessibilityTree.elements(of: CourseCardView(card: advisory).frame(width: 360))
        #expect(advisoryElements.contains { $0.label == "Not graded in Canvas" }, "\(advisoryElements)")
        #expect(!advisoryElements.contains { $0.traits.contains(.button) }, "advisory has no ⓘ: \(advisoryElements)")
    }

    @Test("The bubble: its title is a header (A11Y-09), Tell My School is a button", .enabled(if: !TestRuntime.sanitized))
    func bubbleTree() async throws {
        for scope in [GradeInfoScope.course, .school] {
            let elements = try await AccessibilityTree.elements(of: GradeInfoBubble(scope: scope).frame(width: 320))
            let title = try #require(elements.first { $0.label == "Grades aren't in Canvas" }, "\(elements)")
            #expect(title.traits.contains(.header))
            let share = try #require(elements.first { $0.label.contains("Tell My School") }, "\(elements)")
            #expect(share.traits.contains(.button))
        }
    }

    @Test("The hero: the dash is silent, the caption and its labelled ⓘ are read; the flagship hero has neither",
          .enabled(if: !TestRuntime.sanitized))
    func heroTree() async throws {
        let snapshot = try await ExternalGrades.snapshot()
        let model = HomeModel(source: FakeHomeSource(HomeTestSupport.update(nil, generation: 0, freshness: .noCache)))

        let notInCanvas = GradeNotInCanvasHeroTests.hero(ExternalGrades.trimmed(snapshot, keeping: ExternalGrades.noneInCanvas))
        let noneElements = try await AccessibilityTree.elements(
            of: HeroSection(hero: notInCanvas).environment(model).frame(width: 360))
        #expect(!noneElements.contains { $0.label.contains("\u{2014}") || $0.label.lowercased().contains("dash") }, "\(noneElements)")
        #expect(noneElements.contains { $0.label == "Grades aren't in Canvas" }, "\(noneElements)")
        let noneInfo = try #require(noneElements.first { $0.label == "About grades not in Canvas" }, "\(noneElements)")
        #expect(noneInfo.traits.contains(.button) && noneInfo.frame.width >= 44 && noneInfo.frame.height >= 44)

        let mixed = GradeNotInCanvasHeroTests.hero(snapshot)
        let mixedElements = try await AccessibilityTree.elements(of: HeroSection(hero: mixed).environment(model).frame(width: 360))
        #expect(mixedElements.contains { $0.label.hasPrefix("Average of 1 course") }, "\(mixedElements)")
        #expect(mixedElements.contains { $0.label == "5 courses not included" }, "\(mixedElements)")
        #expect(mixedElements.contains { $0.label == "About the courses not included" && $0.traits.contains(.button) })

        let flagship = GradeNotInCanvasHeroTests.hero(try await ExternalGrades.snapshot("flagship"))
        let flagshipElements = try await AccessibilityTree.elements(of: HeroSection(hero: flagship).environment(model).frame(width: 360))
        #expect(flagshipElements.contains { $0.label.hasPrefix("Average of 5 courses") }, "\(flagshipElements)")
        #expect(!flagshipElements.contains { $0.label.contains("not included") || $0.label.contains("in Canvas") },
                "\(flagshipElements)")
    }
}

nonisolated enum TestRuntime {
    /// Under ThreadSanitizer or AddressSanitizer. The accessibility-tree tests are skipped there:
    /// those runs gain nothing from turning the accessibility runtime on, and only risk reports
    /// from its threads.
    static var sanitized: Bool {
        let handle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        return dlsym(handle, "__tsan_init") != nil || dlsym(handle, "__asan_init") != nil
    }
}

/// Reads a SwiftUI view's accessibility elements in-process: hosts it in a window of the test
/// host's scene with the accessibility runtime switched on, then walks the hosting view's
/// accessibility tree (`accessibilityElements`, else the element count, else the subviews).
@MainActor
enum AccessibilityTree {
    struct Element: CustomStringConvertible {
        let label: String
        let traits: UIAccessibilityTraits
        let frame: CGRect
        var description: String { "\(label) [\(traits.rawValue)] \(frame.size)" }
    }

    struct Unavailable: Error, CustomStringConvertible {
        let description: String
    }

    private typealias AutomationEnabled = @convention(c) () -> Int32
    private typealias SetAutomationEnabled = @convention(c) (Int32) -> Void

    static func elements(of view: some View) async throws -> [Element] {
        guard let library = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW),
              let getter = dlsym(library, "_AXSAutomationEnabled"),
              let setter = dlsym(library, "_AXSSetAutomationEnabled") else {
            throw Unavailable(description: "libAccessibility's automation switch is not available")
        }
        let isEnabled = unsafeBitCast(getter, to: AutomationEnabled.self)
        let setEnabled = unsafeBitCast(setter, to: SetAutomationEnabled.self)
        let before = isEnabled()
        setEnabled(1)
        defer { setEnabled(before) }

        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: view)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()

        // The tree is built after the first render; poll briefly until it has elements.
        var found: [Element] = []
        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(50))
            found = walk(host.view)
            if !found.isEmpty { break }
        }
        guard !found.isEmpty else { throw Unavailable(description: "the hosted view exposed no accessibility elements") }
        return found
    }

    private static func walk(_ root: NSObject) -> [Element] {
        var out: [Element] = []
        func visit(_ object: NSObject, depth: Int) {
            guard depth < 64 else { return }
            if object.isAccessibilityElement {
                out.append(Element(label: object.accessibilityLabel ?? "", traits: object.accessibilityTraits,
                                   frame: object.accessibilityFrame))
                return
            }
            if let children = object.accessibilityElements as? [NSObject], !children.isEmpty {
                for child in children { visit(child, depth: depth + 1) }
                return
            }
            let count = object.accessibilityElementCount()
            if count != NSNotFound, count > 0 {
                for index in 0..<count {
                    if let child = object.accessibilityElement(at: index) as? NSObject { visit(child, depth: depth + 1) }
                }
                return
            }
            if let view = object as? UIView {
                for subview in view.subviews { visit(subview, depth: depth + 1) }
            }
        }
        visit(root, depth: 0)
        return out
    }
}
