import Foundation

/// One person from Canvas's observer/observee lists (family-linking.md §6.1 S1/O1): a
/// student's "Who can see my Canvas" (§7.2), or a parent's "Linked students" (§7.3).
/// Transient and display-only: fetched fresh for those two screens, never itself
/// persisted — storage keys everything by the opaque, name-free `SubjectKey` instead
/// (family-linking.md §6.3's "no names" rule, `Subject.swift`).
public struct ObservedUser: Sendable, Equatable, Identifiable {
    public var id: String { canvasUserID }
    public let canvasUserID: String
    public let name: String
    public let avatarURL: URL?

    public init(canvasUserID: String, name: String, avatarURL: URL?) {
        self.canvasUserID = canvasUserID
        self.name = name
        self.avatarURL = avatarURL
    }
}

/// One pairing code the student created (family-linking.md §4.2 "Invite a parent", §7.4):
/// `POST /api/v1/users/self/observer_pairing_codes` (W1). Single-use, dead after
/// `expiresAt` (Canvas: 7 days) or first successful use — Tally never learns which.
public struct PairingInvite: Sendable, Equatable {
    public let code: String
    public let expiresAt: Date

    public init(code: String, expiresAt: Date) {
        self.code = code
        self.expiresAt = expiresAt
    }
}
