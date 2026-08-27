import SwiftUI
import TallySecurity

public struct AppRootView: View {
    @ObservedObject private var biometricManager = BiometricAuthManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var isLoggedIn: Bool = false
    
    public init() {}
    
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
        }
        .animation(.easeInOut(duration: 0.3), value: biometricManager.isLocked)
        .animation(.easeInOut(duration: 0.3), value: isLoggedIn)
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
