import Foundation

public struct CacheMetadata: Codable {
    public var lastSuccessfulRefreshAt: Date?
    public var lastAttemptedRefreshAt: Date?
    public var isStale: Bool
    
    public init(lastSuccessfulRefreshAt: Date? = nil, lastAttemptedRefreshAt: Date? = nil, isStale: Bool = false) {
        self.lastSuccessfulRefreshAt = lastSuccessfulRefreshAt
        self.lastAttemptedRefreshAt = lastAttemptedRefreshAt
        self.isStale = isStale
    }
}

public class CacheMetadataManager {
    public static let shared = CacheMetadataManager()
    private let defaults = UserDefaults.standard
    private let metadataKey = "TallyCacheMetadata"
    
    private init() {}
    
    public var metadata: CacheMetadata {
        get {
            if let data = defaults.data(forKey: metadataKey),
               let meta = try? JSONDecoder().decode(CacheMetadata.self, from: data) {
                return meta
            }
            return CacheMetadata()
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: metadataKey)
            }
        }
    }
}
