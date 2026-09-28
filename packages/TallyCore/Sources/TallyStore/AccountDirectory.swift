import Foundation
import TallyDomain

/// One signed-in Canvas account, as `accounts.json` records it (architecture.md §3.2's layout
/// table: "account list: host, canvasUserID, clientRegistrationID, displayLabel").
///
/// encryption.md §3.2: the file sits in the App Group (the widget reads it to find its account's
/// glance), is not sealed, and carries **no student content**. `displayLabel` is the school's name
/// as the student chose it on the sign-in screen, never a person's name; the key is the opaque
/// `AccountKey` hash; there are no tokens (those live in the Keychain only).
public struct AccountRecord: Codable, Sendable, Equatable {
    public let accountKey: AccountKey
    /// The Canvas host (`canvas.school.edu`).
    public let host: String
    public let canvasUserID: String
    /// The institution's OAuth client ID (`ClientRegistration.clientID`): token refresh and revoke
    /// need it.
    public let clientID: String
    /// The school's name, for the UI. Never a student's name (encryption.md §3.2).
    public let displayLabel: String

    public init(accountKey: AccountKey, host: String, canvasUserID: String, clientID: String, displayLabel: String) {
        self.accountKey = accountKey
        self.host = host
        self.canvasUserID = canvasUserID
        self.clientID = clientID
        self.displayLabel = displayLabel
    }

    /// A record for `host`/`userID`, keyed by `AccountKey.derive(host:userID:)`.
    public static func derived(host: String, canvasUserID: String, clientID: String, displayLabel: String) -> AccountRecord {
        AccountRecord(accountKey: .derive(host: host, userID: canvasUserID), host: host, canvasUserID: canvasUserID,
                      clientID: clientID, displayLabel: displayLabel)
    }
}

/// The contents of `accounts.json`. v1 ships one active account (security.md D5); the list shape
/// is what the family-linking design extends (family-linking.md: `+ capabilities, + subjectKeys[]`).
public struct AccountDirectory: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public private(set) var accounts: [AccountRecord]
    public private(set) var activeAccountKey: AccountKey?

    public init(accounts: [AccountRecord] = [], activeAccountKey: AccountKey? = nil) {
        schemaVersion = Self.currentSchemaVersion
        self.accounts = accounts
        self.activeAccountKey = activeAccountKey
    }

    public static let empty = AccountDirectory()

    /// The active account, when its record is present.
    public var active: AccountRecord? {
        guard let activeAccountKey else { return nil }
        return accounts.first { $0.accountKey == activeAccountKey }
    }

    /// Adds `record` (replacing a record with the same key, so a re-sign-in never duplicates it)
    /// and makes it the active account.
    public mutating func activate(_ record: AccountRecord) {
        accounts.removeAll { $0.accountKey == record.accountKey }
        accounts.append(record)
        activeAccountKey = record.accountKey
    }

    /// Removes the record for `key`; clears the active account if it was that one.
    public mutating func remove(_ key: AccountKey) {
        accounts.removeAll { $0.accountKey == key }
        if activeAccountKey == key { activeAccountKey = nil }
    }
}

public enum AccountDirectoryLoadResult: Equatable, Sendable {
    case loaded(AccountDirectory)
    /// No file (never signed in, or signed out), an unknown schema, or an undecodable file. There
    /// is no account to open either way.
    case absent
    /// The file exists but could not be read (the device is locked before first unlock, or an I/O
    /// error). The caller must not treat this as "signed out": nothing is deleted.
    case unavailable
}

/// Reads and writes `<root>/accounts.json`, where `root` is the same store root `StoreLayout`
/// uses. Every write is atomic (`ProtectedFile.atomicWrite`: temp file, then rename), with the
/// store's protection class and backup exclusion, so a crash leaves the old or the new file, never
/// a torn one.
///
/// Synchronous, like `ProtectedFile`: callers are actors or `@concurrent` functions, never the
/// main actor. Writes are read-modify-write; the app never runs a sign-in and a sign-out at once.
public struct AccountDirectoryStore: Sendable {
    public static let fileName = "accounts.json"

    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public var fileURL: URL { root.appendingPathComponent(Self.fileName) }

    public func load() -> AccountDirectoryLoadResult {
        let data: Data
        do {
            guard let read = try ProtectedFile.read(fileURL) else { return .absent }
            data = read
        } catch {
            return .unavailable
        }
        guard let directory = try? JSONDecoder().decode(AccountDirectory.self, from: data),
              directory.schemaVersion == AccountDirectory.currentSchemaVersion else { return .absent }
        return .loaded(directory)
    }

    /// The active account, or `nil` when there is none (or the file cannot be read).
    public func activeAccount() -> AccountRecord? {
        guard case .loaded(let directory) = load() else { return nil }
        return directory.active
    }

    public func save(_ directory: AccountDirectory) throws {
        try ProtectedFile.prepareDirectory(root, excludeFromBackup: true)
        try ProtectedFile.atomicWrite(try JSONEncoder().encode(directory), to: fileURL, excludeFromBackup: true)
    }

    /// Sign-in (perf-app-runtime.md §2.4 S3): records `record` and makes it the active account.
    public func activate(_ record: AccountRecord) throws {
        var directory = currentOrEmpty()
        directory.activate(record)
        try save(directory)
    }

    /// Sign-out: forgets `key`. Removes the file when no account is left.
    public func remove(_ key: AccountKey) throws {
        var directory = currentOrEmpty()
        directory.remove(key)
        if directory.accounts.isEmpty {
            ProtectedFile.remove(fileURL)
        } else {
            try save(directory)
        }
    }

    /// Sign-in and sign-out rewrite the whole file; an unreadable or undecodable file is replaced.
    private func currentOrEmpty() -> AccountDirectory {
        if case .loaded(let directory) = load() { return directory }
        return .empty
    }
}
