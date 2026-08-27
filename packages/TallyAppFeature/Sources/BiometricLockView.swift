import SwiftUI
import TallyDesignSystem
import TallySecurity

/// Full-screen lock overlay shown when the app requires biometric unlock.
/// Displayed over the main content when the user returns to the app with Face ID enabled.
public struct BiometricLockView: View {
    @ObservedObject private var biometricManager = BiometricAuthManager.shared
    @State private var showError = false
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // Dark blurred background
            Color.Tally.navyBackground
                .ignoresSafeArea()
            
            VStack(spacing: 32) {
                Spacer()
                
                // Tally branding
                Image("TallyEmblem")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                
                Image("TallyLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 40)
                
                Text("Locked")
                    .font(.Tally.headline)
                    .foregroundColor(.white.opacity(0.7))
                
                Spacer()
                
                // Unlock button
                Button(action: {
                    Task {
                        let success = await biometricManager.authenticate()
                        if !success {
                            showError = true
                        }
                    }
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: biometricManager.biometricIconName)
                            .font(.system(size: 22))
                        Text("Unlock with \(biometricManager.biometricName)")
                            .font(.Tally.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white.opacity(0.15))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 60)
            }
        }
        .alert("Authentication Failed", isPresented: $showError) {
            Button("Try Again") {
                Task {
                    await biometricManager.authenticate()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(biometricManager.biometricName) could not verify your identity.")
        }
        .onAppear {
            // Automatically prompt for Face ID when the lock screen appears
            Task {
                await biometricManager.authenticate()
            }
        }
    }
}
