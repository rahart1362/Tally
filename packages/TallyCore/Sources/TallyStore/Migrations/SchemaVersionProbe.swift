import Foundation

/// Shared by `UserStateStore` and `SyncLedgerStore`: peek a payload's `schemaVersion` field
/// without fully decoding it, so the store can pick the right migration path.
struct SchemaVersionProbe: Decodable {
    let schemaVersion: Int
}

enum SchemaVersionProbeError: Error, Equatable {
    /// A payload names a schema version this build has never heard of (e.g. a downgrade after a
    /// newer version of the app wrote it). There is nothing to migrate *to*, so the caller must
    /// not silently coerce it; `UserStateStore`/`SyncLedgerStore` surface this as `.unavailable`.
    case unsupportedFutureVersion(Int)
}

func peekSchemaVersion(_ data: Data) throws -> Int {
    try JSONDecoder().decode(SchemaVersionProbe.self, from: data).schemaVersion
}
