import Foundation
import TallyCache

public class RefreshOrchestrator: ObservableObject {
    public static let shared = RefreshOrchestrator()
    
    @Published public var isRefreshing = false
    @Published public var isShowingStaleData = false
    @Published public var lastRefreshed: Date? = nil
    
    private let timeoutInterval: TimeInterval = 10.0
    
    public init() {}
    
    /// Legacy stand-in for the refresh path: toggles refresh state only.
    /// It fetches nothing and writes nothing (see PMO ruling R12).
    public func refreshAll() async {
        await MainActor.run {
            self.isRefreshing = true
            self.isShowingStaleData = false
        }
        
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(timeoutInterval * 1_000_000_000))
            if !Task.isCancelled {
                await MainActor.run { [weak self] in
                    if self?.isRefreshing == true {
                        self?.isShowingStaleData = true
                    }
                }
            }
        }
        
        do {
            // LEGACY PLACEHOLDER (M0): there is still no Canvas call here; it is
            // replaced by TallyCore's RefreshCoordinator in M1/M2. The fabricated
            // calendar event and exam notification that used to be written to
            // the user's real Calendar and notification centre were removed
            // (PMO ruling R12, data-integrity defect).
            try await Task.sleep(nanoseconds: 1_500_000_000)

            timeoutTask.cancel()
            
            await MainActor.run { [weak self] in
                self?.isRefreshing = false
                self?.isShowingStaleData = false
                self?.lastRefreshed = Date()
            }
        } catch {
            timeoutTask.cancel()
            await MainActor.run { [weak self] in
                self?.isRefreshing = false
                self?.isShowingStaleData = true
            }
        }
    }
}
