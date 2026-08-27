import SwiftUI
import AuthenticationServices
import TallySecurity
import TallyDesignSystem

public struct LoginView: View {
    @State private var isLoggingIn = false
    @State private var loginError: String? = nil
    
    // Using a binding to tell AppRootView that login is complete
    @Binding public var isLoggedIn: Bool
    
    public init(isLoggedIn: Binding<Bool>) {
        self._isLoggedIn = isLoggedIn
    }
    
    public var body: some View {
        ZStack {
            Color.Tally.navyBackground.ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                // Tally Wordmark (Using imported XCAssets)
                VStack(spacing: 20) {
                    Image("TallyLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 240)
                }
                
                Spacer()
                
                if let error = loginError {
                    Text(error)
                        .font(.Tally.caption)
                        .foregroundColor(Color.Tally.alertRed)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                Button(action: {
                    startMockOAuth()
                }) {
                    HStack {
                        if isLoggingIn {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Connect with Canvas")
                                .font(.Tally.headline)
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.Tally.calculusBlue) // Canvas-like blue
                    .cornerRadius(14)
                }
                .disabled(isLoggingIn)
                .padding(.horizontal, 32)
                .padding(.bottom, 60)
            }
        }
    }
    
    /// Starts a simulated ASWebAuthenticationSession for Canvas OAuth.
    /// In a real implementation, this would point to the Canvas /login/oauth2/auth endpoint.
    private func startMockOAuth() {
        isLoggingIn = true
        loginError = nil
        
        // Simulating the delay of a web authentication flow
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            do {
                // Generate a mock OAuth token
                let mockToken = "mock_canvas_token_\(UUID().uuidString)"
                
                // Securely save the token to the Keychain using our KeychainManager
                try KeychainManager.shared.save(token: mockToken, forAccount: "canvas")
                
                // Update AppRootView state
                withAnimation {
                    self.isLoggedIn = true
                }
            } catch {
                self.loginError = "Failed to save secure token: \(error.localizedDescription)"
                self.isLoggingIn = false
            }
        }
    }
}
