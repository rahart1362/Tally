import Foundation
import TallyDomain

/// AGE-1 (EB-01(c)): **the one field this whole feature may ever write to disk.** Binding
/// invariant (dossier §2): "the age range or category is NEVER persisted, logged, sent or shared.
/// Only the date of the last request may be stored... keep that a single, easily removed field."
/// `AgeRequestRecordStore` reads and writes exactly this file and nothing else; deleting it (or
/// this whole type) removes every trace of age-assurance state this app has ever kept.
public struct AgeRequestRecord: Codable, Sendable, Equatable {
    public var lastRequestedAt: Date

    public init(lastRequestedAt: Date) {
        self.lastRequestedAt = lastRequestedAt
    }
}

/// Reads and writes `<root>/age-request.json`: account-independent (the request happens before
/// any sign-in, EB-01(b): "first launch after install"), unsealed like `accounts.json` — a date is
/// not student content — and excluded from backup for the same reason `accounts.json` is: a
/// restored backup should not fake out the 12-month re-request floor. Synchronous, like
/// `AccountDirectoryStore`: callers are actors or `@concurrent` functions, never the main actor.
public struct AgeRequestRecordStore: Sendable {
    public static let fileName = "age-request.json"

    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public var fileURL: URL { root.appendingPathComponent(Self.fileName) }

    /// `nil` for "never requested" and for "unreadable right now" alike: both read the same way to
    /// `AgeRequestPolicy` (a record it cannot read yet is not evidence of a recent request, so it
    /// never suppresses the first-launch trigger; the next readable launch sees the true date).
    public func load() -> AgeRequestRecord? {
        guard let data = try? ProtectedFile.read(fileURL) else { return nil }
        return try? JSONDecoder().decode(AgeRequestRecord.self, from: data)
    }

    public func save(_ record: AgeRequestRecord) throws {
        try ProtectedFile.prepareDirectory(root, excludeFromBackup: true)
        try ProtectedFile.atomicWrite(try JSONEncoder().encode(record), to: fileURL, excludeFromBackup: true)
    }

    /// Removes the one field this feature ever wrote (owner review, or a future "forget my age
    /// signal" control — not wired to anything yet, kept here so the removal path exists).
    public func reset() {
        ProtectedFile.remove(fileURL)
    }
}

/// AGE-1 (EB-02/EB-03): **never age data.** `lastAcknowledgedSignificantChangeVersion` is the app's
/// own `CFBundleShortVersionString` (public App Store metadata, not a person's age); `lastKnownAgeRatingCode`
/// is `AppStore.ageRatingCode` (the APP's rating, not the user's). Kept out of `AgeRequestRecord`
/// on purpose, so that record's "single, easily removed field" stays exactly that — removing this
/// file only resets "have I already shown this version's significant-change flow," never the
/// age-request date.
public struct SignificantChangeVersionState: Codable, Sendable, Equatable {
    public var lastAcknowledgedSignificantChangeVersion: String?
    public var lastKnownAgeRatingCode: Int?

    public init(lastAcknowledgedSignificantChangeVersion: String? = nil, lastKnownAgeRatingCode: Int? = nil) {
        self.lastAcknowledgedSignificantChangeVersion = lastAcknowledgedSignificantChangeVersion
        self.lastKnownAgeRatingCode = lastKnownAgeRatingCode
    }
}

/// Reads and writes `<root>/significant-change-state.json`, beside `age-request.json`.
public struct SignificantChangeVersionStore: Sendable {
    public static let fileName = "significant-change-state.json"

    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public var fileURL: URL { root.appendingPathComponent(Self.fileName) }

    public func load() -> SignificantChangeVersionState? {
        guard let data = try? ProtectedFile.read(fileURL) else { return nil }
        return try? JSONDecoder().decode(SignificantChangeVersionState.self, from: data)
    }

    public func save(_ state: SignificantChangeVersionState) throws {
        try ProtectedFile.prepareDirectory(root, excludeFromBackup: true)
        try ProtectedFile.atomicWrite(try JSONEncoder().encode(state), to: fileURL, excludeFromBackup: true)
    }

    /// SEC2-13 (owner ruling): Sign Out & Erase ("delete all") removes this alongside
    /// `AgeRequestRecordStore`'s own file — an account deletion must leave nothing AGE-1 wrote,
    /// even though neither file is account-scoped. EB-26's "Erase Saved Data" never calls this:
    /// it is not an account deletion, so both AGE-1 files stay.
    public func reset() {
        ProtectedFile.remove(fileURL)
    }
}
