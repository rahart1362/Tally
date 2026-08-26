import Foundation

public actor CacheManager {
    public static let shared = CacheManager()
    private let cacheDirectory: URL
    
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
}
