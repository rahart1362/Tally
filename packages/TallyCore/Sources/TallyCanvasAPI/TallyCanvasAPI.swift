import TallyDomain

/// Canvas REST client: transport port, endpoint catalogue, Link-header paging,
/// request scheduling, DTOs, and DTO-to-domain mappers.
public enum TallyCanvasAPIModule {
    public static let name = "TallyCanvasAPI"
    public static let dependsOn = [TallyDomainModule.name]
}
