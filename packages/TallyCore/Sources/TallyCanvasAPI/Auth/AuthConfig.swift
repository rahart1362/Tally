import TallyDomain

/// `TallyCanvasAPI`'s own named constants, added onto the shared `TallyConfig` (architecture.md
/// §3.1: "TallyConfig for every constant"), the same pattern `TallyStore/Config/StoreConfig.swift`
/// uses for `accountKeyHexLength`.
extension TallyConfig {
    /// SEC1-05: `InstitutionID.derive(host:)` is a truncated hex SHA-256 of the institution's
    /// Canvas host, used only in the OAuth redirect path. 16 hex characters (64 bits) is plenty to
    /// make an accidental collision between two real institutions practically impossible, while
    /// keeping the redirect path short.
    public static let institutionIdHexLength = 16
}
