import TallyDomain

/// TallyStore's own named constants, added onto the shared `TallyConfig` (architecture.md §3.1:
/// "TallyConfig for every constant"). These live here, not in `TallyDomain/Config/TallyConfig.swift`,
/// because this worktree's scope is the `TallyStore` target only; `TallyDomain` is owned by
/// another engineer. Extending the existing public enum keeps every constant reachable the same
/// way (`TallyConfig.xyz`) without touching a file outside this target.
extension TallyConfig {
    /// `AccountKey` is a truncated hex SHA-256 of `host|userID` (architecture.md §3.2). 16 bytes
    /// (128 bits) keeps paths short while making an accidental collision practically impossible.
    public static let accountKeyHexLength = 32
}
