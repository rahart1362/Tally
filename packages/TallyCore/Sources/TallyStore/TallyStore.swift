import TallyDomain

/// Sealed, versioned snapshot store (atomic replace), glance projection, and
/// user-state and sync-ledger stores.
public enum TallyStoreModule {
    public static let name = "TallyStore"
    public static let dependsOn = [TallyDomainModule.name]
}
