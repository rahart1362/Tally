import Foundation
import TallyCache
import TallyCanvasKit

public class RefreshOrchestrator: ObservableObject {
    public static let shared = RefreshOrchestrator()
    
    @Published public var isRefreshing = false
    @Published public var isShowingStaleData = false
    
    private let timeoutInterval: TimeInterval = 10.0
    
    public init() {}
    
    public func refreshData(apiClient: CanvasAPIClient) async {
        await MainActor.run {
            self.isRefreshing = true
            self.isShowingStaleData = false
        }
        
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(timeoutInterval * 1_000_000_000))
            if !Task.isCancelled {
                await MainActor.run {
                    if self.isRefreshing {
                        self.isShowingStaleData = true
                    }
                }
            }
        }
        
        do {
            var meta = CacheMetadataManager.shared.metadata
            meta.lastAttemptedRefreshAt = Date()
            CacheMetadataManager.shared.metadata = meta
            
            // Fetch courses
            let courses = try await apiClient.getCourses()
            try await CacheManager.shared.save(courses, key: "courses")
            
            timeoutTask.cancel()
            
            await MainActor.run {
                var updatedMeta = CacheMetadataManager.shared.metadata
                updatedMeta.lastSuccessfulRefreshAt = Date()
                updatedMeta.isStale = false
                CacheMetadataManager.shared.metadata = updatedMeta
                self.isRefreshing = false
                self.isShowingStaleData = false
            }
        } catch {
            timeoutTask.cancel()
            await MainActor.run {
                var errorMeta = CacheMetadataManager.shared.metadata
                errorMeta.isStale = true
                CacheMetadataManager.shared.metadata = errorMeta
                self.isRefreshing = false
                self.isShowingStaleData = true
            }
        }
    }
}
