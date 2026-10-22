import Foundation
import TallyDomain
import TallyFeatures
import TallyStore

/// AGE-1 (EB-01(c)): `AgeRequestRecordStore`'s one `Date` field (TallyStore, Linux-testable, plain
/// JSON like `accounts.json`), behind `AgeRequestRecordStoring` so `AgeAssuranceModel` never calls
/// the file system directly. Every method is `@concurrent`, as `KeychainAppLockPreferenceStore`'s
/// are: file I/O never runs on the main actor.
public final class AgeRequestRecordFileStore: AgeRequestRecordStoring, Sendable {
    private let root: @Sendable () throws -> URL

    public init(root: @escaping @Sendable () throws -> URL) {
        self.root = root
    }

    @concurrent
    public func load() async -> AgeRequestRecord? {
        guard let root = try? root() else { return nil }
        return AgeRequestRecordStore(root: root).load()
    }

    @concurrent
    public func save(_ record: AgeRequestRecord) async throws {
        try AgeRequestRecordStore(root: try root()).save(record)
    }
}

/// AGE-1 (EB-02/EB-03): the non-age `SignificantChangeVersionState` file, the same shape.
public final class SignificantChangeVersionFileStore: SignificantChangeVersionStoring, Sendable {
    private let root: @Sendable () throws -> URL

    public init(root: @escaping @Sendable () throws -> URL) {
        self.root = root
    }

    @concurrent
    public func load() async -> SignificantChangeVersionState? {
        guard let root = try? root() else { return nil }
        return SignificantChangeVersionStore(root: root).load()
    }

    @concurrent
    public func save(_ state: SignificantChangeVersionState) async throws {
        try SignificantChangeVersionStore(root: try root()).save(state)
    }
}
