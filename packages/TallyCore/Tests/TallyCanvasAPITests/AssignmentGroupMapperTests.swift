import Foundation
import Testing
import TallyDomain
import TallyTestSupport
@testable import TallyCanvasAPI

@Suite("Assignment group mapping (fixtures)")
struct AssignmentGroupMapperTests {
    private func groupFiles(_ dir: String) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: Fixtures.root().appendingPathComponent(dir), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" && !$0.lastPathComponent.hasSuffix(".headers.json") }
    }

    @Test(arguments: Fixtures.personas.filter { $0 != "empty" })
    func everyPersonaCourseDecodes(_ persona: String) throws {
        let files = try groupFiles("personas/\(persona)/assignment_groups")
        #expect(!files.isEmpty)
        for file in files {
            let courseID = CanvasID<Course>(file.deletingPathExtension().lastPathComponent)
            let mapped = try AssignmentGroupMapper.map(Data(contentsOf: file), courseID: courseID)
            #expect(mapped.dropped == 0)
            #expect(mapped.items.flatMap(\.assignments).allSatisfy { $0.courseID == courseID })
        }
    }

    @Test func dropRulesNeverDropAndWeights() throws {
        let groups = try AssignmentGroupMapper.map(Fixtures.data("scenarios/assignment_groups/never-drop.json"), courseID: "58000").items
        let rules = try #require(groups.first?.rules)
        #expect(rules.dropLowest == 1 && rules.neverDrop == ["1290000"])
        let highest = try AssignmentGroupMapper.map(Fixtures.data("scenarios/assignment_groups/drop-highest.json"), courseID: "58000").items
        #expect(highest.contains { $0.rules.dropHighest > 0 })
    }

    @Test func unpostedScoresAreWithheldAndOmissionIsKept() throws {
        let assignments = try AssignmentGroupMapper.map(Fixtures.data("scenarios/assignment_groups/unposted-and-omitted.json"), courseID: "58000")
            .items.flatMap(\.assignments)
        let unposted = try #require(assignments.first { $0.id == "1290001" })
        #expect(unposted.submission?.postedAt == nil && unposted.submission?.score == nil)
        #expect(assignments.first { $0.id == "1290002" }?.omitFromFinalGrade == true)
        #expect(assignments.first { $0.id == "1290005" }?.submission?.workflowState == "pending_review")
    }

    @Test func gradingTypesAndFlags() throws {
        let passFail = try AssignmentGroupMapper.map(Fixtures.data("scenarios/assignment_groups/pass-fail.json"), courseID: "58000").items
        #expect(passFail.flatMap(\.assignments).contains { $0.gradingType == .passFail })
        let excused = try AssignmentGroupMapper.map(Fixtures.data("scenarios/assignment_groups/excused.json"), courseID: "58000").items
        #expect(excused.flatMap(\.assignments).contains { $0.submission?.excused == true })
        let lateMissing = try AssignmentGroupMapper.map(Fixtures.data("scenarios/assignment_groups/late-and-missing.json"), courseID: "58000").items.flatMap(\.assignments)
        #expect(lateMissing.contains { $0.submission?.late == true } && lateMissing.contains { $0.submission?.missing == true })
    }
}
