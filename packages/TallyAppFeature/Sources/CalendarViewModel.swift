import Foundation
import TallyData

@MainActor
public class CalendarViewModel: ObservableObject {
    @Published public var isLoading: Bool = false
    
    public init() {}
    
    public func loadData() {
        self.isLoading = true
        // Load from CacheManager
        self.isLoading = false
    }
}
