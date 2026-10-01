import Foundation
import Testing
import TallyTestSupport
@testable import TallyDomain

/// Plan 08 §3.2 (L10N-02): a notification is a `NotificationMessage` value; the app phrases it
/// (`TallyStrings.NotificationText`, whose English is pinned by the hosted renderer goldens). What
/// the Linux build proves is structural: no case can carry a grade (R10), and "Hide course names"
/// leaves no Canvas name in the message at all.
@Suite("NotificationMessage: R10 (no grade payload) and Hide course names, as values")
struct NotificationMessageTests {
    private static let date = Date(timeIntervalSince1970: 1_790_000_000)

    /// Every case's name. No `default`: a new case does not compile until it is named here, and
    /// `samples` must then include it (`samplesCoverEveryCase`).
    static func caseName(_ message: NotificationMessage) -> String {
        switch message {
        case .due: "due"
        case .missingFollowup: "missingFollowup"
        case .examReminder: "examReminder"
        case .gradePosted: "gradePosted"
        case .belowGoal: "belowGoal"
        case .eveningDigest: "eveningDigest"
        case .weekAhead: "weekAhead"
        case .sentinel: "sentinel"
        }
    }

    static let caseCount = 8

    /// Every case, with every optional both present and absent, and every name both shown and hidden.
    static let samples: [NotificationMessage] = {
        var out: [NotificationMessage] = []
        for hide in [false, true] {
            let subject = NotificationMessage.Subject(assignmentTitle: "Lab Report 4", courseCode: "BIO 101", hideCourseNames: hide)
            let course = NotificationMessage.CourseName(courseCode: "BIO 101", hideCourseNames: hide)
            out += [
                .due(subject, dueAt: date, isFinalReminder: false),
                .due(subject, dueAt: date, isFinalReminder: true),
                .missingFollowup(subject, stillAcceptedUntil: date),
                .missingFollowup(subject, stillAcceptedUntil: nil),
                .examReminder(subject, dueAt: date),
                .gradePosted(course),
                .belowGoal(course),
                .eveningDigest(dueCount: 2, firstItem: .init(title: "Lab Report 4", hideCourseNames: hide)),
                .eveningDigest(dueCount: 2, firstItem: nil),
            ]
        }
        out += [.weekAhead(dueCount: 7, busiestDay: date), .weekAhead(dueCount: 1, busiestDay: nil), .sentinel(lastSuccess: date)]
        return out
    }()

    /// One value in a message's payload: where it sits and its type.
    struct Leaf: Equatable {
        let path: String
        let type: String
        let text: String?
    }

    /// The optionals a message may carry (by the wrapped type's name).
    static let allowedOptionals: Set<String> = ["Optional<Date>", "Optional<ItemName>"]

    /// Every leaf of `value`'s payload. Only `NotificationMessage`'s own enums, tuples and the
    /// allowed optionals are opened; a `String`, `Date`, `Int` or `Bool` is a leaf; anything else
    /// (a `Double`, a `GradeBand`, `ComputedScores`, an unexpected optional …) is reported as a
    /// leaf of its own type, which the allowlist then rejects.
    static func leaves(_ value: Any, path: String = "") -> [Leaf] {
        switch value {
        case let text as String: return [Leaf(path: path, type: "String", text: text)]
        case is Date: return [Leaf(path: path, type: "Date", text: nil)]
        case is Int: return [Leaf(path: path, type: "Int", text: nil)]
        case is Bool: return [Leaf(path: path, type: "Bool", text: nil)]
        default: break
        }
        let mirror = Mirror(reflecting: value)
        let typeName = String(describing: type(of: value))
        switch mirror.displayStyle {
        case .optional:
            guard allowedOptionals.contains(typeName) else { return [Leaf(path: path, type: typeName, text: nil)] }
            return mirror.children.flatMap { leaves($0.value, path: path) }
        case .tuple:
            return mirror.children.flatMap { leaves($0.value, path: "\(path).\($0.label ?? "?")") }
        case .enum where String(reflecting: type(of: value)).hasPrefix("TallyDomain.NotificationMessage"):
            return mirror.children.flatMap { leaves($0.value, path: "\(path)/\($0.label ?? "?")") }
        default:
            return [Leaf(path: path, type: typeName, text: nil)]
        }
    }

    @Test func samplesCoverEveryCase() {
        #expect(Set(Self.samples.map(Self.caseName)).count == Self.caseCount)
    }

    /// R10, structurally: a message's payload is Canvas names, dates, flags and counts, and
    /// nothing else; the only integers are item counts.
    @Test func noCaseCarriesAScoreOrGradePayload() {
        for message in Self.samples {
            let leaves = Self.leaves(message)
            let types = Set(leaves.map(\.type))
            #expect(types.isSubset(of: ["String", "Date", "Int", "Bool"]), "\(Self.caseName(message)): \(types)")
            for leaf in leaves where leaf.type == "Int" {
                #expect(leaf.path.hasSuffix(".dueCount"), "\(Self.caseName(message)): an integer at \(leaf.path)")
            }
        }
    }

    /// The walker itself: a grade-shaped payload is reported, not skipped (so a mutation that adds
    /// one fails the test above).
    @Test func theWalkerReportsGradeShapedValues() {
        #expect(Self.leaves((score: 93.4, band: GradeBand.aRange)).map(\.type) == ["Double", "GradeBand"])
        #expect(Self.leaves(Optional<Double>.none as Any).map(\.type) == ["Optional<Double>"])
        #expect(Self.leaves(NotificationMessage.gradePosted(.code("X"))).map(\.path) == ["/gradePosted/code"])
    }

    // MARK: - Hide course names (R10) hides BOTH course names/codes and assignment titles

    @Test func hideCourseNamesLeavesNoNameInTheMessage() {
        #expect(NotificationMessage.Subject(assignmentTitle: "Lab Report 4", courseCode: "BIO 101", hideCourseNames: true) == .hidden)
        #expect(NotificationMessage.CourseName(courseCode: "BIO 101", hideCourseNames: true) == .hidden)
        #expect(NotificationMessage.ItemName(title: "Lab Report 4", hideCourseNames: true) == .hidden)
        #expect(NotificationMessage.Subject(assignmentTitle: "Lab Report 4", courseCode: "BIO 101", hideCourseNames: false)
                    == .assignment(title: "Lab Report 4", courseCode: "BIO 101"))
        #expect(NotificationMessage.CourseName(courseCode: "BIO 101", hideCourseNames: false) == .code("BIO 101"))
        #expect(NotificationMessage.ItemName(title: "Lab Report 4", hideCourseNames: false) == .title("Lab Report 4"))
    }

    /// Property test over every fixture persona (the WP-D02 criterion, now on values): with "Hide
    /// course names" on, no message carries any text; with it off, only that assignment's own
    /// title and course code.
    @Test(arguments: Fixtures.personas)
    func noFixturePersonaLeaksANameWhenHidden(_ persona: String) throws {
        let courses = try GradeFixtures.courses(persona: persona)
        var checked = 0
        for course in courses {
            let code = course.course.courseCode
            for assignment in course.groups.flatMap(\.assignments) {
                for hide in [false, true] {
                    let subject = NotificationMessage.Subject(assignmentTitle: assignment.name, courseCode: code, hideCourseNames: hide)
                    let messages: [NotificationMessage] = [
                        .due(subject, dueAt: Self.date, isFinalReminder: false),
                        .due(subject, dueAt: Self.date, isFinalReminder: true),
                        .missingFollowup(subject, stillAcceptedUntil: assignment.lockAt),
                        .examReminder(subject, dueAt: Self.date),
                        .eveningDigest(dueCount: 3, firstItem: .init(title: assignment.name, hideCourseNames: hide)),
                        .gradePosted(.init(courseCode: code, hideCourseNames: hide)),
                        .belowGoal(.init(courseCode: code, hideCourseNames: hide)),
                    ]
                    for message in messages {
                        let texts = Self.leaves(message).compactMap(\.text)
                        if hide {
                            #expect(texts.isEmpty, "\(persona): \(Self.caseName(message)) carried \(texts) with names hidden")
                        } else {
                            #expect(Set(texts).isSubset(of: [assignment.name, code]), "\(persona): \(texts)")
                        }
                    }
                    checked += 1
                }
            }
        }
        // "empty" (Morgan Sample) has no enrollments at all (fixtures/canvas README): zero
        // assignments is the correct, verified state there, not a test-setup bug.
        if persona != "empty" {
            #expect(checked > 0, "\(persona): expected at least one assignment to check")
        }
    }
}
