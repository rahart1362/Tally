import Foundation

/// What a signed-in Canvas account can do (family-linking.md §6.2). An account can hold
/// both at once — an observer who also has their own coursework (§4.3 "both → parent mode
/// with a Me entry").
public enum Capability: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    case student
    case observer
}

/// What the account chose at onboarding ("I'm a student" / "I'm a parent or guardian",
/// family-linking.md §7.5 step 1). `AccountRoles.detect` only consults this for the one
/// case Canvas's own signals cannot resolve on their own — see its doc comment.
public enum DeclaredRole: Sendable, Equatable, Hashable, Codable {
    case student
    case parent
}

/// Opaque per-subject key (family-linking.md §6.2: "hex SHA-256(host|accountUserID|
/// subjectUserID), truncated; no names"). Mirrors `AccountKey` (`Model/CanvasSnapshot.swift`):
/// the *type* lives here so every layer shares one currency, but the hash derivation itself
/// is left to whichever layer already owns hashing for storage keys (`TallyStore`,
/// `AccountKey.derive(host:userID:)` — `StoreLayout.swift`) rather than duplicated here or
/// given a second, weaker implementation. Tests build one with any stable string.
public struct SubjectKey: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
}

/// One data subject in an account: the signed-in person themselves, or one student they
/// observe. Never carries a name — display names live only inside sealed per-subject
/// storage (family-linking.md §6.3), never in this identifier.
public struct Subject: Sendable, Hashable, Codable, Identifiable {
    public enum Kind: Sendable, Hashable, Codable, Equatable {
        case me
        case observee(canvasUserID: String)
    }

    public let id: SubjectKey
    public let kind: Kind

    public init(id: SubjectKey, kind: Kind) {
        self.id = id
        self.kind = kind
    }
}

/// One signed-in account's capabilities and the subjects they grant access to
/// (family-linking.md §6.2, §4.3 "Role check after sign-in"). `subjects[0] == .me`
/// whenever `capabilities.contains(.student)` — `.me` always sorts first when present, so
/// the header switcher's default lands on the account's own data (family-linking.md §7.1).
public struct AccountRoles: Sendable, Equatable {
    public let capabilities: Set<Capability>
    public let subjects: [Subject]

    public init(capabilities: Set<Capability>, subjects: [Subject]) {
        self.capabilities = capabilities
        self.subjects = subjects
    }

    /// Detects capabilities and subjects from what Canvas reports plus, for the one case
    /// Canvas can't resolve alone, what the account declared at onboarding.
    ///
    /// Canvas exposes no single "this is a parent account" flag: an observer account that
    /// has not yet linked any student has exactly the same two signals (no student
    /// enrolment, an empty `GET /users/self/observees`) as a brand-new, role-less account.
    /// `declaredRole == .parent` is what distinguishes "parent, zero observees so far"
    /// (family-linking.md §10 FAM-02's fourth fixture — `capabilities == [.observer]`,
    /// `subjects == []`, so the app shows "no students linked yet" rather than a generic
    /// "we don't recognise this account") from that role-less account (`capabilities ==
    /// []`). It plays no part in any other case: a real student enrolment or a non-empty
    /// observees list always wins on its own, matching §4.3's own three explicit branches.
    ///
    /// - Parameters:
    ///   - hasOwnStudentEnrollment: any of the account's own enrolments is a student
    ///     enrolment (drives the `.student` capability and the `.me` subject).
    ///   - observeeCanvasUserIDs: the ids from `GET /users/self/observees` (O1), in
    ///     whatever order the caller received them.
    ///   - declaredRole: the onboarding choice, if any (`nil` when re-detecting after sign-in
    ///     with no fresh declaration to hand, e.g. a background refresh).
    ///   - subjectKey: derives the opaque `SubjectKey` for one `Subject.Kind` — the actual
    ///     hash lives in the caller's storage layer (see `SubjectKey`'s doc comment); this
    ///     function only decides *which* subjects exist, never how they are keyed.
    public static func detect(hasOwnStudentEnrollment: Bool, observeeCanvasUserIDs: [String],
                              declaredRole: DeclaredRole?,
                              subjectKey: (Subject.Kind) -> SubjectKey) -> AccountRoles {
        var capabilities: Set<Capability> = []
        if hasOwnStudentEnrollment { capabilities.insert(.student) }
        if !observeeCanvasUserIDs.isEmpty || declaredRole == .parent { capabilities.insert(.observer) }

        var subjects: [Subject] = []
        if hasOwnStudentEnrollment { subjects.append(Subject(id: subjectKey(.me), kind: .me)) }
        for canvasUserID in observeeCanvasUserIDs {
            let kind = Subject.Kind.observee(canvasUserID: canvasUserID)
            subjects.append(Subject(id: subjectKey(kind), kind: kind))
        }
        return AccountRoles(capabilities: capabilities, subjects: subjects)
    }
}

/// Resolves the header switcher's active subject (family-linking.md §6.2 "`activeSubject`
/// is app-wide state... persisted in `user-state` as an opaque `SubjectKey`"). Pure: the
/// caller reads the persisted key and the current subject list, and this decides what to
/// show — never invents a new subject, never mutates anything.
public enum ActiveSubjectPolicy {
    /// The previously active subject if it still exists, else `.me` if the account has it,
    /// else the first subject in `subjects`, else `nil` (the zero-subjects empty state).
    public static func resolve(persisted: SubjectKey?, subjects: [Subject]) -> SubjectKey? {
        if let persisted, subjects.contains(where: { $0.id == persisted }) { return persisted }
        if let me = subjects.first(where: { $0.kind == .me }) { return me.id }
        return subjects.first?.id
    }
}
