import SwiftUI
import TallySecurity

public struct AppRootView: View {
    @ObservedObject private var biometricManager = BiometricAuthManager.shared
    @Environment(\.scenePhase) private var scenePhase
    
    public init() {}
    
    public var body: some View {
        ZStack {
            MainTabView()
            
            // Overlay biometric lock screen when the app is locked
            if biometricManager.isLocked {
                BiometricLockView()
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: biometricManager.isLocked)
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .background:
                // Lock the app when it goes to background (if biometric is enabled)
                biometricManager.lockIfEnabled()
            case .active:
                // Refresh biometric availability when returning to foreground
                biometricManager.checkBiometricAvailability()
            default:
                break
            }
        }
    }
}
