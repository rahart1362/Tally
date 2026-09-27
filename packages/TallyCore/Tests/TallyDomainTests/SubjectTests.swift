import Foundation
import Testing
@testable import TallyDomain

@Suite("AccountRoles.detect and ActiveSubjectPolicy (FAM-02)")
struct SubjectTests {
    /// A trivial, order-preserving stand-in for the real hash (which lives in TallyStore);
    /// good enough to prove `detect` wires subjects up correctly.
    private func key(_ kind: Subject.Kind) -> SubjectKey {
        switch kind {
        case .me: SubjectKey("me")
        case .observee(let id): SubjectKey("observee-\(id)")
        }
    }

    @Test func studentOnly() {
        let roles = AccountRoles.detect(hasOwnStudentEnrollment: true, observeeCanvasUserIDs: [],
                                        declaredRole: .student, subjectKey: key)
        #expect(roles.capabilities == [.student])
        #expect(roles.subjects == [Subject(id: SubjectKey("me"), kind: .me)])
    }

    @Test func parentOnlyWithObservees() {
        let roles = AccountRoles.detect(hasOwnStudentEnrollment: false, observeeCanvasUserIDs: ["4820117", "4820118"],
                                        declaredRole: .parent, subjectKey: key)
        #expect(roles.capabilities == [.observer])
        #expect(roles.subjects == [
            Subject(id: SubjectKey("observee-4820117"), kind: .observee(canvasUserID: "4820117")),
            Subject(id: SubjectKey("observee-4820118"), kind: .observee(canvasUserID: "4820118")),
        ])
    }

    /// A non-empty observees list is load-bearing on its own — no onboarding declaration
    /// is needed to recognise a parent who has already linked a student.
    @Test func parentWithObserveesNeedsNoDeclaredRole() {
        let roles = AccountRoles.detect(hasOwnStudentEnrollment: false, observeeCanvasUserIDs: ["4820117"],
                                        declaredRole: nil, subjectKey: key)
        #expect(roles.capabilities == [.observer])
        #expect(roles.subjects.count == 1)
    }

    @Test func both() {
        let roles = AccountRoles.detect(hasOwnStudentEnrollment: true, observeeCanvasUserIDs: ["4820117"],
                                        declaredRole: nil, subjectKey: key)
        #expect(roles.capabilities == [.student, .observer])
        // .me sorts first (family-linking.md §6.2 "subjects[0] == .me").
        #expect(roles.subjects.first == Subject(id: SubjectKey("me"), kind: .me))
        #expect(roles.subjects.count == 2)
    }

    /// family-linking.md §10 FAM-02's fourth fixture: a parent account with nothing linked
    /// yet. Canvas's own signals (no enrolment, empty observees) are indistinguishable from
    /// a role-less account, so only the onboarding declaration tells them apart.
    @Test func parentWithZeroObserveesStillGetsTheObserverCapability() {
        let roles = AccountRoles.detect(hasOwnStudentEnrollment: false, observeeCanvasUserIDs: [],
                                        declaredRole: .parent, subjectKey: key)
        #expect(roles.capabilities == [.observer])
        #expect(roles.subjects.isEmpty)
    }

    @Test func noSignalsAndNoDeclarationYieldsNoCapabilities() {
        let roles = AccountRoles.detect(hasOwnStudentEnrollment: false, observeeCanvasUserIDs: [],
                                        declaredRole: nil, subjectKey: key)
        #expect(roles.capabilities.isEmpty)
        #expect(roles.subjects.isEmpty)
    }

    @Test func subjectKeyContainsNoNames() {
        // SubjectKey only ever wraps whatever opaque string the caller's hash produced —
        // this test's own `key(_:)` stand-in never touches a name, and neither does the
        // production type: `Subject`/`SubjectKey` have no name-bearing property at all.
        let roles = AccountRoles.detect(hasOwnStudentEnrollment: false, observeeCanvasUserIDs: ["4820117"],
                                        declaredRole: nil, subjectKey: key)
        #expect(roles.subjects.allSatisfy { !$0.id.rawValue.isEmpty && !$0.id.rawValue.contains("Alex") })
    }

    // MARK: - ActiveSubjectPolicy

    private let me = Subject(id: SubjectKey("me"), kind: .me)
    private let maya = Subject(id: SubjectKey("s-maya"), kind: .observee(canvasUserID: "1"))
    private let leo = Subject(id: SubjectKey("s-leo"), kind: .observee(canvasUserID: "2"))

    @Test func keepsThePersistedSubjectWhenItStillExists() {
        let resolved = ActiveSubjectPolicy.resolve(persisted: leo.id, subjects: [me, maya, leo])
        #expect(resolved == leo.id)
    }

    @Test func fallsBackToMeWhenThePersistedSubjectIsGone() {
        let resolved = ActiveSubjectPolicy.resolve(persisted: leo.id, subjects: [me, maya])
        #expect(resolved == me.id)
    }

    @Test func fallsBackToTheFirstSubjectWhenThereIsNoMe() {
        let resolved = ActiveSubjectPolicy.resolve(persisted: nil, subjects: [maya, leo])
        #expect(resolved == maya.id)
    }

    @Test func nilWhenThereAreNoSubjectsAtAll() {
        #expect(ActiveSubjectPolicy.resolve(persisted: nil, subjects: []) == nil)
    }

    @Test func nilPersistedStillPrefersMe() {
        let resolved = ActiveSubjectPolicy.resolve(persisted: nil, subjects: [maya, me, leo])
        #expect(resolved == me.id)
    }
}
