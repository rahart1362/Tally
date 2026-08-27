import Foundation

public actor CacheManager {
    public static let shared = CacheManager()
    private let cacheDirectory: URL
    
    /// Maximum cache age before automatic eviction (7 days).
    private let maxCacheAge: TimeInterval = 7 * 24 * 60 * 60
    
    /// Maximum total cache size in bytes (50 MB).
    private let maxCacheSize: Int = 50 * 1024 * 1024
    
    private init() {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        self.cacheDirectory = paths[0].appendingPathComponent("TallyCache")
        try? FileManager.default.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
    }
    
    public func save<T: Encodable>(_ object: T, key: String) throws {
        let data = try JSONEncoder().encode(object)
        let fileURL = cacheDirectory.appendingPathComponent(key)
        try data.write(to: fileURL, options: .completeFileProtection)
    }
    
    public func load<T: Decodable>(key: String, as type: T.Type) throws -> T? {
        let fileURL = cacheDirectory.appendingPathComponent(key)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(T.self, from: data)
    }
    
    /// Remove a specific cached entry.
    public func remove(key: String) {
        let fileURL = cacheDirectory.appendingPathComponent(key)
        try? FileManager.default.removeItem(at: fileURL)
    }
    
    /// Evict stale cache entries older than `maxCacheAge` and enforce `maxCacheSize`.
    /// Call this on app launch or periodically to prevent unbounded disk growth.
    public func pruneStaleEntries() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: .skipsHiddenFiles
        ) else { return }
        
        let now = Date()
        var remainingFiles: [(url: URL, date: Date, size: Int)] = []
        
        for fileURL in files {
            guard let attrs = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let modDate = attrs.contentModificationDate,
                  let fileSize = attrs.fileSize else {
                continue
            }
            
            // Evict files older than maxCacheAge
            if now.timeIntervalSince(modDate) > maxCacheAge {
                try? fm.removeItem(at: fileURL)
            } else {
                remainingFiles.append((url: fileURL, date: modDate, size: fileSize))
            }
        }
        
        // Enforce max cache size by evicting oldest files first
        let totalSize = remainingFiles.reduce(0) { $0 + $1.size }
        if totalSize > maxCacheSize {
            let sorted = remainingFiles.sorted { $0.date < $1.date }
            var freed = 0
            let excess = totalSize - maxCacheSize
            for file in sorted {
                guard freed < excess else { break }
                try? fm.removeItem(at: file.url)
                freed += file.size
            }
        }
    }
}
