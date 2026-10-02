import Foundation
import Testing
import TallyTestSupport
@testable import TallyDomain

/// FAM-08's R10a privacy invariant, as values — exactly the `NotificationMessageTests` pattern
/// (that file's own doc comment: "What the Linux build proves is structural"), applied to
/// `FamilyNotificationMessage`. `TallyStrings.FamilyNotificationText` phrases these (an Apple-
/// only, Xcode-built target this host cannot compile); what Linux proves, and what matters for
/// R10a, is that no case *can* carry a score, a percentage or a letter grade for a renderer to
/// leak, structurally, and that every fixture/persona's own data confirms it in practice.
@Suite("FamilyNotificationMessage: R10a (no score/percentage/grade payload), structurally and over every fixture")
struct FamilyNotificationMessageTests {
    private static let date = Date(timeIntervalSince1970: 1_790_000_000)

    static func caseName(_ message: FamilyNotificationMessage) -> String {
        switch message {
        case .weekAhead: "weekAhead"
        case .missingStillOpen: "missingStillOpen"
        case .dueReminder: "dueReminder"
        case .gradePosted: "gradePosted"
        case .belowGoal: "belowGoal"
        }
    }

    static let caseCount = 5

    /// Every case, with every optional both present and absent, and every name both shown and hidden.
    static let samples: [FamilyNotificationMessage] = {
        var out: [FamilyNotificationMessage] = []
        for hide in [false, true] {
            out += [
                FamilyNotificationContentBuilder.weekAhead(studentName: "Maya", hideStudentNames: hide, dueCount: 5, busiestDay: date),
                FamilyNotificationContentBuilder.weekAhead(studentName: "Maya", hideStudentNames: hide, dueCount: 0, busiestDay: nil),
                FamilyNotificationContentBuilder.missingStillOpen(studentName: "Maya", hideStudentNames: hide,
                                                                  assignmentTitle: "Problem Set 6", stillAcceptedUntil: date),
                FamilyNotificationContentBuilder.missingStillOpen(studentName: "Maya", hideStudentNames: hide,
                                                                  assignmentTitle: "Problem Set 6", stillAcceptedUntil: nil),
                FamilyNotificationContentBuilder.dueReminder(studentName: "Maya", hideStudentNames: hide,
                                                             assignmentTitle: "Lab Report 4", dueAt: date, isFinalReminder: false),
                FamilyNotificationContentBuilder.dueReminder(studentName: "Maya", hideStudentNames: hide,
                                                             assignmentTitle: "Lab Report 4", dueAt: date, isFinalReminder: true),
                FamilyNotificationContentBuilder.gradePosted(studentName: "Maya", hideStudentNames: hide, courseCode: "BIO 101"),
                FamilyNotificationContentBuilder.belowGoal(studentName: "Maya", hideStudentNames: hide, courseCode: "BIO 101"),
            ]
        }
        return out
    }()

    struct Leaf: Equatable {
        let path: String
        let type: String
        let text: String?
    }

    /// The optionals a message may carry (by the wrapped type's name) — mirrors
    /// `NotificationMessageTests.allowedOptionals`.
    static let allowedOptionals: Set<String> = ["Optional<Date>"]

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
        case .enum where String(reflecting: type(of: value)).hasPrefix("TallyDomain.FamilyNotificationMessage"):
            return mirror.children.flatMap { leaves($0.value, path: "\(path)/\($0.label ?? "?")") }
        default:
            return [Leaf(path: path, type: typeName, text: nil)]
        }
    }

    @Test func samplesCoverEveryCase() {
        #expect(Set(Self.samples.map(Self.caseName)).count == Self.caseCount)
    }

    /// R10a, structurally: a message's payload is a student-name reference, Canvas names,
    /// dates, and flags — never a `Double`, never anything else.
    @Test func noCaseCarriesAScoreOrGradePayload() {
        for message in Self.samples {
            let leaves = Self.leaves(message)
            let types = Set(leaves.map(\.type))
            #expect(types.isSubset(of: ["String", "Date", "Int", "Bool"]), "\(Self.caseName(message)): \(types)")
            #expect(!types.contains("Double"), "\(Self.caseName(message)) carried a Double")
        }
    }

    /// The walker itself: a grade-shaped payload is reported, not skipped (so a mutation that
    /// adds one fails the test above) — this is the mutation-check counterpart described in the
    /// M3-E1 report (break the privacy filter, see it fail, restore byte-identical).
    @Test func theWalkerReportsGradeShapedValues() {
        #expect(Self.leaves((score: 93.4, grade: "A")).map(\.type) == ["Double", "String"])
        #expect(Self.leaves(Optional<Double>.none as Any).map(\.type) == ["Optional<Double>"])
        // A message's real text leaves still surface (so a case that smuggled a grade-shaped
        // String in among its real text would still be caught by the sweep below).
        let withName = FamilyNotificationMessage.gradePosted(student: .named("Maya"), courseCode: "BIO 101")
        #expect(Set(Self.leaves(withName).compactMap(\.text)) == ["Maya", "BIO 101"])
    }

    // MARK: - Hide student names

    @Test func hideStudentNamesLeavesNoNameInTheMessage() {
        #expect(FamilyNotificationMessage.StudentNameRef(name: "Maya", hideStudentNames: true) == .hidden)
        #expect(FamilyNotificationMessage.StudentNameRef(name: "Maya", hideStudentNames: false) == .named("Maya"))
    }

    @Test func hiddenStudentNameNeverAppearsAsALeaf() {
        for message in Self.samples {
            let isHidden: Bool
            switch message {
            case .weekAhead(let s, _, _), .missingStillOpen(let s, _, _), .dueReminder(let s, _, _, _),
                 .gradePosted(let s, _), .belowGoal(let s, _):
                isHidden = s == .hidden
            }
            guard isHidden else { continue }
            let texts = Self.leaves(message).compactMap(\.text)
            #expect(!texts.contains("Maya"), "\(Self.caseName(message)) leaked the student's name while hidden")
        }
    }

    // MARK: - Property test over every fixture/persona (FAM-08's acceptance criterion)

    /// Every string a `FamilyNotificationMessage` can ever carry is a leaf of the message value
    /// itself (never a rendered sentence — `TallyStrings` is Apple-only and out of this Linux
    /// build's reach, exactly like the student-side `NotificationMessageTests`). So the
    /// strongest, Linux-checkable form of "parent notification text never contains a score, a
    /// percentage or a letter grade taken from the snapshot" is: every String leaf this builder
    /// ever produces, across every fixture/persona, is *only ever* the student's own name, an
    /// assignment's own title or a course's own code — never any of that fixture's own score,
    /// percentage or letter-grade text.
    @Test(arguments: Fixtures.personas)
    func noFixturePersonaLeaksAScoreOrGradeIntoFamilyNotificationText(_ persona: String) throws {
        let courses = try GradeFixtures.courses(persona: persona)
        var checked = 0
        for course in courses {
            let forbidden = Self.forbiddenScoreText(course.course)
            for assignment in course.groups.flatMap(\.assignments) {
                for hide in [false, true] {
                    let messages: [FamilyNotificationMessage] = [
                        FamilyNotificationContentBuilder.weekAhead(studentName: "Sample Student", hideStudentNames: hide,
                                                                   dueCount: 3, busiestDay: Self.date),
                        FamilyNotificationContentBuilder.missingStillOpen(studentName: "Sample Student", hideStudentNames: hide,
                                                                          assignmentTitle: assignment.name, stillAcceptedUntil: assignment.lockAt),
                        FamilyNotificationContentBuilder.dueReminder(studentName: "Sample Student", hideStudentNames: hide,
                                                                     assignmentTitle: assignment.name, dueAt: Self.date, isFinalReminder: false),
                        FamilyNotificationContentBuilder.gradePosted(studentName: "Sample Student", hideStudentNames: hide,
                                                                     courseCode: course.course.courseCode),
                        FamilyNotificationContentBuilder.belowGoal(studentName: "Sample Student", hideStudentNames: hide,
                                                                   courseCode: course.course.courseCode),
                    ]
                    for message in messages {
                        let texts = Self.leaves(message).compactMap(\.text)
                        for text in texts {
                            #expect(!forbidden.contains(text), "\(persona)/\(course.course.courseCode): \(Self.caseName(message)) carried \(text), one of this course's own score/grade values")
                        }
                    }
                    checked += 1
                }
            }
        }
        if persona != "empty" {
            #expect(checked > 0, "\(persona): expected at least one assignment to check")
        }
    }

    /// FAM-14: the same sweep over the sample-data family persona itself (two real subjects,
    /// decoded through `SampleFamilyHarness`, the production decoders end to end).
    @Test func sampleFamilySnapshotsNeverLeakAScoreOrGrade() async throws {
        let subjects = try await SampleFamilyHarness.fetchSubjectSnapshots(now: Self.date)
        #expect(subjects.count == 2)
        var checked = 0
        for subject in subjects {
            for course in subject.snapshot.courses {
                let forbidden = Self.forbiddenScoreText(course)
                for assignment in (subject.snapshot.groups[course.id] ?? []).flatMap(\.assignments) {
                    for hide in [false, true] {
                        let messages: [FamilyNotificationMessage] = [
                            FamilyNotificationContentBuilder.missingStillOpen(studentName: subject.displayName, hideStudentNames: hide,
                                                                              assignmentTitle: assignment.name, stillAcceptedUntil: assignment.lockAt),
                            FamilyNotificationContentBuilder.gradePosted(studentName: subject.displayName, hideStudentNames: hide,
                                                                         courseCode: course.courseCode),
                            FamilyNotificationContentBuilder.belowGoal(studentName: subject.displayName, hideStudentNames: hide,
                                                                       courseCode: course.courseCode),
                        ]
                        for message in messages {
                            let texts = Self.leaves(message).compactMap(\.text)
                            for text in texts {
                                #expect(!forbidden.contains(text), "sample-family/\(subject.displayName)/\(course.courseCode): \(Self.caseName(message)) carried \(text)")
                            }
                        }
                        checked += 1
                    }
                }
            }
        }
        #expect(checked > 0)
    }

    /// Every plausible rendering of this course's own score/grade data (current and final,
    /// whole-course and current-period), as exact text — the set `noFixturePersonaLeaks…` and
    /// `sampleFamilySnapshotsNeverLeak…` assert no message leaf ever equals.
    private static func forbiddenScoreText(_ course: Course) -> Set<String> {
        var out: Set<String> = []
        for scores in [course.scores, course.currentPeriodScores] {
            guard let scores else { continue }
            if let s = scores.currentScore { out.formUnion([String(s), String(format: "%.1f", s), String(format: "%.0f", s)]) }
            if let s = scores.finalScore { out.formUnion([String(s), String(format: "%.1f", s), String(format: "%.0f", s)]) }
            if let g = scores.currentGrade { out.insert(g) }
            if let g = scores.finalGrade { out.insert(g) }
        }
        return out
    }
}
