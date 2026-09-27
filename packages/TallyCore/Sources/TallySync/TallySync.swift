import TallyCanvasAPI
import TallyDomain
import TallyStore

/// Refresh coordinator (10-second live budget, late self-heal) and the
/// post-commit pipeline: notification and calendar reconcilers.
public enum TallySyncModule {
    public static let name = "TallySync"
    public static let dependsOn = [TallyDomainModule.name, TallyCanvasAPIModule.name, TallyStoreModule.name]
}
