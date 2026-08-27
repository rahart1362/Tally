import SwiftUI
import TallySecurity
import TallyData

public struct AppRootView: View {
    @ObservedObject private var biometricManager = BiometricAuthManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("isLoggedIn") private var isLoggedIn: Bool = false
    
    public init() {
        // Register background task early
        BackgroundSyncManager.shared.registerTask()
    }
    
    public var body: some View {
        ZStack {
            if isLoggedIn {
                MainTabView()
            } else {
                LoginView(isLoggedIn: $isLoggedIn)
            }
            
            // Overlay biometric lock screen when the app is locked
            if biometricManager.isLocked {
                BiometricLockView()
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .onAppear {
            isLoggedIn = KeychainManager.shared.hasToken(forAccount: "canvas")
            if isLoggedIn {
                forceRefresh()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: biometricManager.isLocked)
        .animation(.easeInOut(duration: 0.3), value: isLoggedIn)
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .background:
                // Lock the app when it goes to background (if biometric is enabled)
                if isLoggedIn {
                    biometricManager.lockIfEnabled()
                }
                // Schedule next background refresh based on battery/6h policy
                BackgroundSyncManager.shared.scheduleNextRefresh()
            case .active:
                // Refresh biometric availability when returning to foreground
                biometricManager.checkBiometricAvailability()
                // Force an on-demand refresh when launching/foregrounding
                if isLoggedIn {
                    forceRefresh()
                }
            default:
                break
            }
        }
        .onChange(of: isLoggedIn) { loggedIn in
            if loggedIn {
                forceRefresh()
            }
        }
    }
    
    private func forceRefresh() {
        Task {
            await RefreshOrchestrator.shared.refreshAll()
        }
    }
}

